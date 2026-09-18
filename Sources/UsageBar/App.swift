import SwiftUI
import AppKit
import UserNotifications
import UsageCore

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct UsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()
    var body: some Scene {
        MenuBarExtra {
            Dashboard(store: store)
        } label: {
            Label(store.menuLabel, systemImage: "gauge.with.dots.needle.50percent")
        }
        .menuBarExtraStyle(.window)
        Window("Ajustes do UsageBar", id: "settings") {
            SettingsView(store: store)
        }
        .defaultSize(width: 560, height: 640)
        .windowResizability(.contentSize)
    }
}

struct Dashboard: View {
    @ObservedObject var store: Store
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("UsageBar").font(.title2.weight(.semibold))
                    Text("Limites das assinaturas").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.refreshing { ProgressView().controlSize(.small) }
            }
            ProviderView(name: "Claude", symbol: "sparkle", color: .orange, state: store.claude,
                         threshold: store.preferences.claudeThreshold, enabled: store.preferences.claudeEnabled)
            Divider()
            ProviderView(name: "Codex", symbol: "terminal", color: .teal, state: store.codex,
                         threshold: store.preferences.codexThreshold, enabled: store.preferences.codexEnabled)
            Divider()
            ProviderView(name: "Devin · experimental", symbol: "cpu", color: .blue, state: store.devin,
                         threshold: store.preferences.devinThreshold, enabled: store.preferences.devinEnabled,
                         disabledLabel: "Desativado")
            if !store.preferences.devinEnabled {
                Text("O login no navegador não conecta o UsageBar. Configure a sessão nos ajustes e ative o monitoramento.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Configurar Devin…") { openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }
                Link("Abrir site", destination: URL(string: "https://app.devin.ai/")!)
            }.font(.caption)
            if let error = store.notificationError {
                Label(error, systemImage: "bell.slash").font(.caption).foregroundStyle(.orange)
            }
            Divider()
            HStack {
                Button("Ajustes…") { openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
            Text("Claude acompanha o CLI. Codex e Devin: a cada 5 min.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(20).frame(width: 370)
    }
}

struct ProviderView: View {
    let name: String
    let symbol: String
    let color: Color
    let state: ProviderState
    let threshold: Double
    let enabled: Bool
    var disabledLabel: String = "Pausado"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(name, systemImage: symbol).font(.headline)
                Spacer()
                Text(enabled ? "Alerta em \(Int(threshold))%" : disabledLabel).font(.caption).foregroundStyle(.secondary)
            }
            if enabled {
                if let error = state.error {
                    Text(error).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if state.windows.isEmpty && state.error == nil {
                    Text("Aguardando dados…").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(state.windows) { window in
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(window.title).font(.subheadline)
                                Spacer()
                                Text("\(window.usedPercent, specifier: "%.0f")%")
                                    .font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
                            }
                            ProgressView(value: min(window.usedPercent, 100), total: 100)
                                .tint(window.usedPercent >= threshold ? .orange : color)
                                .accessibilityLabel("\(name), \(window.title), \(Int(window.usedPercent)) por cento consumido")
                            if !window.isFresh(at: context.date) || state.error != nil {
                                Text("Dados antigos · última leitura \(window.observedAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption2).foregroundStyle(.orange)
                            } else {
                                Text("Renova \(window.resetsAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

final class SettingsDraft: ObservableObject {
    @Published var ntfyToken = ""
    @Published var devinToken = ""
    @Published var testing = false
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @StateObject private var draft = SettingsDraft()
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Limites para alertar") {
                    Toggle("Monitorar Claude", isOn: $store.preferences.claudeEnabled)
                    threshold("Claude", value: $store.preferences.claudeThreshold)
                    Toggle("Monitorar Codex", isOn: $store.preferences.codexEnabled)
                    threshold("Codex", value: $store.preferences.codexThreshold)
                    Toggle("Monitorar Devin", isOn: $store.preferences.devinEnabled)
                    threshold("Devin", value: $store.preferences.devinThreshold)
                    Text("Um alerta por janela e por canal. Rearma quando o período renova. Dados antigos não disparam alertas.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Conexões") {
                    TextField("Executável do Codex", text: $store.preferences.codexPath)
                    Text("Use o mesmo Codex CLI conectado à sua assinatura. Mudanças são aplicadas na próxima consulta, em até 5 minutos.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Guia de conexão do Claude") {
                        if let resource = Bundle.main.resourceURL?.appendingPathComponent("README.md") { NSWorkspace.shared.open(resource) }
                    }
                }
                Section("Devin · conexão experimental") {
                    Text("O login no site fica no navegador. Esta versão precisa que você conecte a sessão manualmente.")
                        .font(.callout)
                    Text("1. No site Devin, abra Usage & Limits.\n2. No inspetor do navegador → Network, selecione a requisição /billing/quota/usage.\n3. Copie x-cog-org-id para o ID abaixo e o valor de Authorization para a sessão.\n4. Salve a sessão e ative Monitorar Devin.")
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    TextField("ID interno da organização", text: $store.preferences.devinOrganization)
                    SecureField("Sessão (Bearer token)", text: $draft.devinToken)
                    Button("Salvar sessão Devin") { store.saveDevin(token: draft.devinToken) }
                    Button("Abrir guia de conexão") {
                        if let resource = Bundle.main.resourceURL?.appendingPathComponent("README.md") { NSWorkspace.shared.open(resource) }
                    }
                    Text("Consulte o guia e confira os percentuais com o painel antes de ativar alertas. A sessão expira e precisa ser substituída. A compatibilidade com seu plano depende das cotas disponíveis no painel.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Notificações no Mac") {
                    Toggle("Alertar neste Mac", isOn: $store.preferences.macAlerts)
                    HStack {
                        Button("Permitir notificações") { Task { await store.authorizeMac() } }
                        Button("Testar no Mac") { runTest("mac") }.disabled(draft.testing)
                    }
                }
                Section("iPhone e Apple Watch · ntfy") {
                    TextField("Servidor", text: $store.preferences.ntfyServer)
                    TextField("Tópico", text: $store.preferences.ntfyTopic)
                    SecureField("Access token (opcional)", text: $draft.ntfyToken)
                    HStack {
                        Button("Salvar configuração") { store.saveNtfy(token: draft.ntfyToken) }
                        Button("Gerar outro tópico") { store.generateNtfyTopic() }
                    }
                    Text("No ntfy para iPhone, adicione uma assinatura usando:\nServidor: \(store.preferences.ntfyServer)\nTópico: \(store.preferences.ntfyTopic)")
                        .font(.caption).textSelection(.enabled)
                    HStack {
                        Button("Copiar tópico") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(store.preferences.ntfyTopic, forType: .string)
                            store.notice = "Tópico copiado. Cole apenas este valor no campo Topic do ntfy."
                        }
                        Button("Copiar URL web") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(ntfySubscriptionURL, forType: .string)
                            store.notice = "URL copiada. No app iOS, informe servidor e tópico separadamente."
                        }
                        Link("Abrir ntfy no navegador", destination: URL(string: "https://ntfy.sh/app")!)
                        Link("Guia do ntfy para iPhone", destination: URL(string: "https://docs.ntfy.sh/subscribe/phone/")!)
                    }
                    Toggle("Enviar alertas pelo ntfy", isOn: $store.preferences.ntfyAlerts)
                    Button("Testar no iPhone / Watch") { runTest("ntfy") }.disabled(draft.testing)
                    Text("Não cole https://ntfy.sh/... dentro do campo de tópico: isso causa 404. No ntfy.sh, o tópico funciona como senha; mantenha-o privado. O Mac precisa estar ligado, conectado e com o UsageBar aberto.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            if let notice = store.notice {
                Text(notice).font(.callout).textSelection(.enabled).padding([.horizontal, .bottom])
            }
        }
        .frame(width: 560, height: 680)
        .task {
            do { draft.ntfyToken = try Keychain.read("ntfy-token") }
            catch { store.notice = error.localizedDescription }
        }
    }
    private var ntfySubscriptionURL: String {
        (try? NtfyDestination(server: store.preferences.ntfyServer, topic: store.preferences.ntfyTopic))?
            .subscriptionURL.absoluteString ?? "Configuração inválida"
    }
    private func threshold(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).frame(width: 60, alignment: .leading)
            Slider(value: value, in: 1...100, step: 1)
            Text("\(Int(value.wrappedValue))%").monospacedDigit().frame(width: 42, alignment: .trailing)
        }
    }
    private func runTest(_ channel: String) {
        draft.testing = true
        Task { await store.test(channel: channel); draft.testing = false }
    }
}
