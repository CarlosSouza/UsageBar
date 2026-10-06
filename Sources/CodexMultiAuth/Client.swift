import Foundation
import UsageCore

public enum MultiAuthError: Error, LocalizedError, Equatable {
    case unsupportedSchema
    case invalidAccounts
    case commandFailed
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema: "Unsupported multi-auth schema. Update codex-multi-auth."
        case .invalidAccounts: "Invalid multi-auth account list. Refresh before switching."
        case .commandFailed: "Multi-auth command failed. Check the executable and your account connection."
        case .timedOut: "Multi-auth did not respond in time. Refresh to check the account selection."
        }
    }
}

public struct MultiAuthSnapshot: Decodable, Sendable {
    public struct Selection: Decodable, Sendable {
        public let pinnedIndex: Int?
        public let routedIndex: Int?
    }

    public struct Account: Decodable, Identifiable, Sendable {
        public let index: Int
        public let label: String
        public let enabled: Bool
        public let current: Bool
        public let quota: Quota?
        public var id: Int { index }
        public var commandIndex: Int { index + 1 }

        public var windows: [UsageWindow] {
            guard let quota, quota.status == 200, quota.updatedAt.isFinite else { return [] }
            return [("primary", quota.primary), ("secondary", quota.secondary)].compactMap { name, window in
                guard let window, let used = window.usedPercent, used.isFinite, used >= 0, used <= 100,
                      let reset = window.resetAtMs, reset.isFinite, reset > 0 else { return nil }
                let minutes = window.windowMinutes
                let title: String
                if let minutes, minutes > 0 {
                    title = minutes % 1440 == 0 ? "\(minutes / 1440)d" : minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes)m"
                } else {
                    title = name == "primary" ? "Primary" : "Secondary"
                }
                return UsageWindow(id: "multi-auth:\(index):\(label):\(name)", title: title, usedPercent: used,
                                   resetsAt: Date(timeIntervalSince1970: reset / 1000),
                                   observedAt: Date(timeIntervalSince1970: quota.updatedAt / 1000))
            }
        }
    }

    public struct Quota: Decodable, Sendable {
        public struct Window: Decodable, Sendable {
            public let usedPercent: Double?
            public let windowMinutes: Int?
            public let resetAtMs: Double?
        }
        public let updatedAt: Double
        public let status: Int
        public let planType: String?
        public let primary: Window?
        public let secondary: Window?
    }

    public let schemaVersion: Int
    public let selection: Selection
    public let accounts: [Account]
    public var selectedAccount: Account? { accounts.first { $0.index == selection.routedIndex } }

    public static func decode(_ data: Data) throws -> MultiAuthSnapshot {
        let snapshot = try JSONDecoder().decode(Self.self, from: data)
        guard snapshot.schemaVersion == 1 else { throw MultiAuthError.unsupportedSchema }
        let indices = Set(snapshot.accounts.map(\.index))
        guard indices.count == snapshot.accounts.count,
              snapshot.accounts.enumerated().allSatisfy({ $0.offset == $0.element.index }),
              snapshot.selection.pinnedIndex.map({ indices.contains($0) }) ?? true,
              snapshot.selection.routedIndex.map({ indices.contains($0) }) ?? snapshot.accounts.isEmpty,
              snapshot.selection.pinnedIndex.map({ $0 == snapshot.selection.routedIndex }) ?? true else {
            throw MultiAuthError.invalidAccounts
        }
        return snapshot
    }
}

public struct MultiAuthClient: Sendable {
    public let executable: String
    private let timeout: TimeInterval
    public init(executable: String, timeout: TimeInterval = 60) {
        self.executable = executable
        self.timeout = timeout
    }

    public static var defaultExecutable: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["/opt/homebrew/bin/codex-multi-auth", "/usr/local/bin/codex-multi-auth",
                          "\(home)/.local/bin/codex-multi-auth"]
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
            .map { "\($0)/codex-multi-auth" }
        return (candidates + paths).first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
    }

    public var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: executable) }

    public func limits(refresh: Bool = false) throws -> MultiAuthSnapshot {
        try MultiAuthSnapshot.decode(run(["limits", "--json"] + (refresh ? ["--refresh"] : [])))
    }

    public func select(_ account: MultiAuthSnapshot.Account) throws {
        let latest = try limits()
        guard latest.accounts.contains(where: { $0.index == account.index && $0.label == account.label && $0.enabled }) else {
            throw MultiAuthError.invalidAccounts
        }
        _ = try run(["switch", String(account.commandIndex)], captureOutput: false)
    }

    public func unpin() throws { _ = try run(["unpin"], captureOutput: false) }

    private func run(_ arguments: [String], captureOutput: Bool = true) throws -> Data {
        guard isInstalled else { throw MultiAuthError.commandFailed }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        let binaryDirectory = URL(fileURLWithPath: executable).deletingLastPathComponent().path
        environment["PATH"] = "\(binaryDirectory):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = captureOutput ? output : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + max(timeout, 0.01), execute: deadline)
        defer { deadline.cancel() }
        var data = Data()
        if captureOutput {
            while true {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                guard data.count + chunk.count <= 4_000_000 else {
                    process.terminate()
                    throw MultiAuthError.commandFailed
                }
                data.append(chunk)
            }
        }
        process.waitUntilExit()
        guard process.terminationReason == .exit else { throw MultiAuthError.timedOut }
        guard process.terminationStatus == 0 else { throw MultiAuthError.commandFailed }
        return data
    }
}
