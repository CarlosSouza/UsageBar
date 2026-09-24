import Foundation

public enum NtfyConfigurationError: LocalizedError, Equatable {
    case invalidServer
    case insecureServer
    case invalidTopic

    public var errorDescription: String? {
        switch self {
        case .invalidServer: "Informe uma URL de servidor ntfy válida."
        case .insecureServer: "Use HTTPS no servidor ntfy. HTTP é aceito apenas para localhost."
        case .invalidTopic: "O tópico deve ter de 1 a 64 letras, números, hífens ou underscores."
        }
    }
}

public struct NtfyDestination: Equatable, Sendable {
    public let server: URL
    public let topic: String

    public init(server rawServer: String, topic rawTopic: String) throws {
        let cleanedServer = rawServer.trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = rawTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: cleanedServer),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw NtfyConfigurationError.invalidServer
        }
        let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard scheme == "https" || (scheme == "http" && isLoopback) else {
            throw NtfyConfigurationError.insecureServer
        }
        components.path = components.path.replacingOccurrences(of: #"/+$"#, with: "", options: .regularExpression)
        guard let server = components.url else { throw NtfyConfigurationError.invalidServer }
        guard topic.range(of: #"^[-_A-Za-z0-9]{1,64}$"#, options: .regularExpression) != nil else {
            throw NtfyConfigurationError.invalidTopic
        }
        self.server = server
        self.topic = topic
    }

    public var subscriptionURL: URL { server.appendingPathComponent(topic) }
}

public struct UsageWindow: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var usedPercent: Double
    public var resetsAt: Date
    public var observedAt: Date

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date, observedAt: Date) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.observedAt = observedAt
    }

    public func isFresh(at now: Date) -> Bool {
        usedPercent.isFinite && usedPercent >= 0 && observedAt <= now.addingTimeInterval(60)
            && now.timeIntervalSince(observedAt) < 900 && resetsAt > now
    }
}

/// Shared with the desktop widget through Application Support; only metrics, never credentials.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Provider: Codable, Equatable, Sendable {
        public var id: String
        public var threshold: Double
        public var windows: [UsageWindow]
        public var error: String?

        public init(id: String, threshold: Double, windows: [UsageWindow], error: String?) {
            self.id = id
            self.threshold = threshold
            self.windows = windows
            self.error = error
        }

        public func isFresh(at now: Date) -> Bool {
            error == nil && !windows.isEmpty && windows.allSatisfy { $0.isFresh(at: now) }
        }

        /// Keeps the original order but, when there are more windows than slots, shows the most consumed ones.
        public func topWindows(_ limit: Int) -> [UsageWindow] {
            guard windows.count > limit else { return windows }
            let kept = Set(windows.sorted { $0.usedPercent > $1.usedPercent }.prefix(limit).map(\.id))
            return windows.filter { kept.contains($0.id) }
        }
    }

    public static let fileName = "widget.json"
    public var providers: [Provider]

    public init(providers: [Provider]) { self.providers = providers }

    public static func decode(_ data: Data) throws -> WidgetSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public func provider(_ id: String) -> Provider? { providers.first { $0.id == id } }

    /// Moments after `now` when a window turns stale or resets, so the widget redraws without the app.
    public func transitions(after now: Date) -> [Date] {
        let moments = providers.flatMap(\.windows).flatMap { [$0.observedAt.addingTimeInterval(900), $0.resetsAt] }
        return Array(Set(moments.filter { $0 > now })).sorted()
    }
}

/// A delivery is acknowledged only after its channel accepts it. State persists across launches.
public struct AlertLedger: Codable, Sendable {
    public var delivered: [String: Date] = [:]
    public init() {}

    public func key(provider: String, window: UsageWindow, channel: String) -> String {
        "\(provider)|\(window.id)|\(Int(window.resetsAt.timeIntervalSince1970))|\(channel)"
    }

    public func shouldDeliver(provider: String, window: UsageWindow, threshold: Double, channel: String, now: Date) -> Bool {
        threshold > 0 && threshold <= 100 && window.isFresh(at: now)
            && window.usedPercent >= threshold
            && delivered[key(provider: provider, window: window, channel: channel)] == nil
    }

    public mutating func acknowledge(provider: String, window: UsageWindow, channel: String, now: Date) {
        delivered = delivered.filter { $0.value > now.addingTimeInterval(-100 * 86400) }
        delivered[key(provider: provider, window: window, channel: channel)] = now
    }
}

public enum UsageParsing {
    public static func devin(_ data: Data, now: Date = Date()) throws -> [UsageWindow] {
        // The dashboard percentage fields are already percentages, including decimals.
        struct Payload: Decodable {
            let daily_percentage: Double?
            let weekly_percentage: Double?
            let daily_reset_at: ResetDate?
            let weekly_reset_at: ResetDate?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return [("daily", "Diário", payload.daily_percentage, payload.daily_reset_at),
                ("weekly", "Semanal", payload.weekly_percentage, payload.weekly_reset_at)].compactMap { id, title, value, reset in
            guard let value, value.isFinite, value >= 0, let reset else { return nil }
            return UsageWindow(id: id, title: title, usedPercent: value, resetsAt: reset.date, observedAt: now)
        }
    }

    public static func codex(_ data: Data, now: Date = Date()) throws -> [UsageWindow] {
        struct Window: Decodable { let usedPercent: Double; let windowDurationMins: Int?; let resetsAt: Double }
        struct Bucket: Decodable { let limitName: String?; let primary: Window?; let secondary: Window? }
        struct Reply: Decodable { let rateLimits: Bucket?; let rateLimitsByLimitId: [String: Bucket]? }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        let buckets = reply.rateLimitsByLimitId ?? reply.rateLimits.map { ["codex": $0] } ?? [:]
        return buckets.sorted(by: { $0.key < $1.key }).flatMap { id, bucket in
            [("primary", bucket.primary), ("secondary", bucket.secondary)].compactMap { kind, value in
                guard let value, value.usedPercent.isFinite, value.usedPercent >= 0 else { return nil }
                let minutes = value.windowDurationMins
                let period = minutes.map { $0 >= 1440 ? "\($0 / 1440) dias" : ($0 >= 60 ? "\($0 / 60) horas" : "\($0) min") } ?? kind
                return UsageWindow(id: "\(id).\(kind)", title: "\(bucket.limitName ?? id) · \(period)", usedPercent: value.usedPercent, resetsAt: Date(timeIntervalSince1970: value.resetsAt), observedAt: now)
            }
        }
    }

    public static func claude(_ data: Data) throws -> [UsageWindow] {
        struct Window: Decodable { let used_percentage: Double; let resets_at: Double }
        struct Snapshot: Decodable { let observed_at: Double; let rate_limits: [String: Window] }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        return snapshot.rate_limits.sorted(by: { $0.key < $1.key }).compactMap { id, value in
            guard value.used_percentage.isFinite, value.used_percentage >= 0 else { return nil }
            return UsageWindow(id: id, title: id == "five_hour" ? "5 horas" : id == "seven_day" ? "7 dias" : id,
                               usedPercent: value.used_percentage, resetsAt: Date(timeIntervalSince1970: value.resets_at),
                               observedAt: Date(timeIntervalSince1970: snapshot.observed_at))
        }
    }
}

private struct ResetDate: Decodable {
    let date: Date
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let number = try? value.decode(Double.self), number.isFinite, number > 0 {
            date = Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1000 : number)
            return
        }
        let string = try value.decode(String.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string) { date = parsed; return }
        throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid reset timestamp")
    }
}
