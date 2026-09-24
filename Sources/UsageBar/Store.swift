import AppKit
import SwiftUI
import UserNotifications
import WidgetKit
import UsageCore

struct Preferences: Codable {
    var claudeThreshold = 90.0
    var codexThreshold = 90.0
    var devinThreshold = 90.0
    var claudeEnabled = true
    var codexEnabled = true
    var devinEnabled = false
    var devinOrganization = ""
    var macAlerts = false
    var ntfyAlerts = false
    var ntfyServer = "https://ntfy.sh"
    var ntfyTopic = Preferences.makeNtfyTopic()
    var codexPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path

    init() {}

    private enum CodingKeys: String, CodingKey {
        case claudeThreshold, codexThreshold, devinThreshold
        case claudeEnabled, codexEnabled, devinEnabled, devinOrganization
        case macAlerts, ntfyAlerts, ntfyServer, ntfyTopic, codexPath
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        claudeThreshold = try values.decodeIfPresent(Double.self, forKey: .claudeThreshold) ?? claudeThreshold
        codexThreshold = try values.decodeIfPresent(Double.self, forKey: .codexThreshold) ?? codexThreshold
        devinThreshold = try values.decodeIfPresent(Double.self, forKey: .devinThreshold) ?? devinThreshold
        claudeEnabled = try values.decodeIfPresent(Bool.self, forKey: .claudeEnabled) ?? claudeEnabled
        codexEnabled = try values.decodeIfPresent(Bool.self, forKey: .codexEnabled) ?? codexEnabled
        devinEnabled = try values.decodeIfPresent(Bool.self, forKey: .devinEnabled) ?? devinEnabled
        devinOrganization = try values.decodeIfPresent(String.self, forKey: .devinOrganization) ?? devinOrganization
        macAlerts = try values.decodeIfPresent(Bool.self, forKey: .macAlerts) ?? macAlerts
        ntfyAlerts = try values.decodeIfPresent(Bool.self, forKey: .ntfyAlerts) ?? ntfyAlerts
        ntfyServer = try values.decodeIfPresent(String.self, forKey: .ntfyServer) ?? ntfyServer
        ntfyTopic = try values.decodeIfPresent(String.self, forKey: .ntfyTopic) ?? ntfyTopic
        codexPath = try values.decodeIfPresent(String.self, forKey: .codexPath) ?? codexPath
    }

    static func makeNtfyTopic() -> String {
        "usagebar_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

struct ProviderState {
    var windows: [UsageWindow] = []
    var error: String?
}

/// Cópia das leituras em ~/Library/Application Support/UsageBar/<provedor>.json, no mesmo espírito
/// do claude.json: só percentuais, renovações e horário de observação. Scripts locais podem ler
/// esses arquivos em vez de guardar tokens.
struct ProviderExport: Codable {
    var observed_at: Double
    var windows: [UsageWindow]
    var error: String?

    static func write(_ state: ProviderState, as name: String) {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/UsageBar")
        let target = directory.appendingPathComponent("\(name).json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            encoder.outputFormatting = [.sortedKeys]
            let payload = ProviderExport(observed_at: Date().timeIntervalSince1970, windows: state.windows, error: state.error)
            try encoder.encode(payload).write(to: target, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        } catch {
            // Exportação é auxiliar: falha aqui não pode derrubar a leitura nem o alerta.
        }
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var preferences: Preferences { didSet { savePreferences() } }
    @Published var claude = ProviderState()
    @Published var codex = ProviderState()
    @Published var devin = ProviderState()
    @Published var refreshing = false
    @Published var notice: String?
    @Published var notificationError: String?
    private var ledger: AlertLedger
    private var timer: Task<Void, Never>?
    private var lastCodexRead = Date.distantPast
    private var lastDevinRead = Date.distantPast
    private var retryAfter: [String: Date] = [:]
    private var lastWidgetSnapshot: WidgetSnapshot?
    private let defaults = UserDefaults.standard

    init() {
        preferences = UserDefaults.standard.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        ledger = UserDefaults.standard.data(forKey: "ledger").flatMap { try? JSONDecoder().decode(AlertLedger.self, from: $0) } ?? AlertLedger()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    var menuLabel: String {
        let active = (preferences.claudeEnabled && claude.error == nil ? claude.windows : [])
            + (preferences.codexEnabled && codex.error == nil ? codex.windows : [])
            + (preferences.devinEnabled && devin.error == nil ? devin.windows : [])
        guard let max = active.filter({ $0.isFresh(at: Date()) }).map(\.usedPercent).max() else { return "Usage" }
        return "\(Int(max.rounded()))%"
    }

    private func savePreferences() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "preferences") }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        if preferences.claudeEnabled {
            do {
                let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/UsageBar/claude.json")
                claude = ProviderState(windows: try UsageParsing.claude(Data(contentsOf: path)))
                if claude.windows.isEmpty { claude.error = "Aguardando métricas da assinatura no Claude Code." }
            } catch {
                claude.error = "Conecte a statusline do Claude Code. Veja o guia nos ajustes."
            }
            await evaluate(provider: "Claude", windows: claude.windows, threshold: preferences.claudeThreshold, valid: claude.error == nil)
        }
        if preferences.codexEnabled && Date().timeIntervalSince(lastCodexRead) >= 300 {
            lastCodexRead = Date()
            let path = preferences.codexPath
            do {
                let windows = try await Task.detached { try CodexReader().read(executable: path) }.value
                codex = ProviderState(windows: windows, error: windows.isEmpty ? "Nenhum limite disponível. Confira o login com a assinatura." : nil)
            } catch { codex.error = error.localizedDescription }
            ProviderExport.write(codex, as: "codex")
        }
        if preferences.codexEnabled {
            await evaluate(provider: "Codex", windows: codex.windows, threshold: preferences.codexThreshold, valid: codex.error == nil)
        }
        if preferences.devinEnabled && Date().timeIntervalSince(lastDevinRead) >= 300 {
            lastDevinRead = Date()
            do {
                devin = ProviderState(windows: try await DevinReader.read(organization: preferences.devinOrganization))
            } catch { devin.error = error.localizedDescription }
            ProviderExport.write(devin, as: "devin")
        }
        if preferences.devinEnabled {
            await evaluate(provider: "Devin", windows: devin.windows, threshold: preferences.devinThreshold, valid: devin.error == nil)
        }
        publishWidgetSnapshot()
    }

    private func publishWidgetSnapshot() {
        let providers: [WidgetSnapshot.Provider] = [
            preferences.claudeEnabled ? .init(id: "claude", threshold: preferences.claudeThreshold, windows: claude.windows, error: claude.error) : nil,
            preferences.codexEnabled ? .init(id: "codex", threshold: preferences.codexThreshold, windows: codex.windows, error: codex.error) : nil,
            preferences.devinEnabled ? .init(id: "devin", threshold: preferences.devinThreshold, windows: devin.windows, error: devin.error) : nil
        ].compactMap { $0 }
        let snapshot = WidgetSnapshot(providers: providers)
        guard snapshot != lastWidgetSnapshot else { return }
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/UsageBar")
        let target = directory.appendingPathComponent(WidgetSnapshot.fileName)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try snapshot.encoded().write(to: target, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            lastWidgetSnapshot = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // O widget é auxiliar: falha aqui não pode derrubar a leitura nem o alerta.
        }
    }

    private func evaluate(provider: String, windows: [UsageWindow], threshold: Double, valid: Bool) async {
        guard valid else { return }
        for window in windows {
            for channel in ["mac", "ntfy"] {
                guard channel == "mac" ? preferences.macAlerts : preferences.ntfyAlerts else { continue }
                let now = Date()
                let key = ledger.key(provider: provider, window: window, channel: channel)
                guard (retryAfter[key] ?? .distantPast) <= now,
                      ledger.shouldDeliver(provider: provider, window: window, threshold: threshold, channel: channel, now: now) else { continue }
                let title = "\(provider): \(Int(window.usedPercent.rounded()))% consumido"
                let message = "\(window.title). Limite de alerta: \(Int(threshold))%. Renova em \(window.resetsAt.formatted(date: .abbreviated, time: .shortened))."
                do {
                    if channel == "mac" { try await Notifications.local(title: title, message: message, id: key) }
                    else {
                        try await Notifications.ntfy(server: preferences.ntfyServer, topic: preferences.ntfyTopic,
                                                     title: title, message: message)
                    }
                    ledger.acknowledge(provider: provider, window: window, channel: channel, now: now)
                    if let data = try? JSONEncoder().encode(ledger) { defaults.set(data, forKey: "ledger") }
                    notificationError = nil
                } catch {
                    notificationError = error.localizedDescription
                    retryAfter[key] = now.addingTimeInterval(300)
                }
            }
        }
    }

    func authorizeMac() async {
        do {
            preferences.macAlerts = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            notice = preferences.macAlerts ? "Notificações no Mac ativadas." : "Permissão negada. Ajuste em Ajustes do Sistema → Notificações."
        } catch { notice = error.localizedDescription }
    }

    func saveNtfy(token: String) {
        do {
            _ = try NtfyDestination(server: preferences.ntfyServer, topic: preferences.ntfyTopic)
            try Keychain.save(token.trimmingCharacters(in: .whitespacesAndNewlines), account: "ntfy-token")
            notice = "Configuração ntfy salva. Assine o tópico no app ntfy antes de testar."
        } catch { notice = error.localizedDescription }
    }

    func generateNtfyTopic() {
        preferences.ntfyTopic = Preferences.makeNtfyTopic()
        preferences.ntfyAlerts = false
        notice = "Novo tópico criado. Assine o novo endereço no app ntfy."
    }

    func saveDevin(token: String) {
        do {
            try Keychain.save(token.trimmingCharacters(in: .whitespacesAndNewlines), account: "devin-token")
            notice = "Sessão Devin salva no Chaves."
            lastDevinRead = .distantPast
        } catch { notice = error.localizedDescription }
    }

    func test(channel: String) async {
        do {
            if channel == "mac" { try await Notifications.local(title: "UsageBar", message: "Alerta de teste no Mac.", id: UUID().uuidString) }
            else {
                try await Notifications.ntfy(server: preferences.ntfyServer, topic: preferences.ntfyTopic,
                                             title: "UsageBar", message: "Alerta de teste para iPhone / Apple Watch.")
            }
            notice = "Alerta de teste aceito para entrega."
        } catch { notice = error.localizedDescription }
    }
}
