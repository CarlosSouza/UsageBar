import Foundation
import Security
import UserNotifications
import UsageCore

struct AppFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Keychain {
    static func save(_ value: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: "local.usagebar", kSecAttrAccount as String: account]
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AppFailure("Não foi possível remover a chave (\(status)).") }
            return
        }
        let attributes = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AppFailure("Não foi possível salvar no Chaves (\(status)).") }
    }

    static func read(_ account: String) throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "local.usagebar", kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw AppFailure("Não foi possível ler o Chaves (\(status)).")
        }
        return value
    }
}

/// A short-lived, read-only app-server connection. No conversations or model calls are created.
final class CodexReader: @unchecked Sendable {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var buffer = Data()
    private var responses: [Int: [String: Any]] = [:]

    func read(executable: String) throws -> [UsageWindow] {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw AppFailure("Selecione o executável do Codex nos ajustes e faça login pelo Codex.")
        }
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            lock.lock()
            defer { lock.unlock() }
            if chunk.isEmpty { signal.signal(); return }
            buffer.append(chunk)
            if buffer.count > 2_000_000 { buffer.removeAll(); signal.signal(); return }
            while let end = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: end)
                buffer.removeSubrange(...end)
                if let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = value["id"] as? Int {
                    responses[id] = value
                    signal.signal()
                }
            }
        }
        try process.run()
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }
        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        func reply(_ id: Int) throws -> [String: Any] {
            let deadline = DispatchTime.now() + 20
            while true {
                lock.lock(); let result = responses.removeValue(forKey: id); lock.unlock()
                if let result {
                    if result["error"] != nil { throw AppFailure("Codex recusou a leitura. Confira o login da assinatura e a versão do CLI.") }
                    guard let body = result["result"] as? [String: Any] else { throw AppFailure("Resposta inesperada do Codex.") }
                    return body
                }
                guard signal.wait(timeout: deadline) == .success else { throw AppFailure("O Codex não respondeu em 20 segundos.") }
                if !process.isRunning { throw AppFailure("O Codex encerrou a conexão. Confira a instalação do CLI.") }
            }
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "usagebar", "title": "UsageBar", "version": "0.1.0"]]])
        _ = try reply(1)
        try send(["method": "initialized", "params": [:]])
        try send(["id": 2, "method": "account/rateLimits/read", "params": [:]])
        let body = try reply(2)
        return try UsageParsing.codex(JSONSerialization.data(withJSONObject: body))
    }
}

enum Notifications {
    static func local(title: String, message: String, id: String) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            throw AppFailure("Permita notificações do UsageBar nos ajustes do macOS.")
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    static func ntfy(server: String, topic: String, title: String, message: String) async throws {
        let destination = try NtfyDestination(server: server, topic: topic)
        let token = try Keychain.read("ntfy-token").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.contains("\n"), !token.contains("\r") else {
            throw AppFailure("O token ntfy contém caracteres inválidos.")
        }
        var request = URLRequest(url: destination.server)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "topic": destination.topic,
            "title": title,
            "message": message,
            "priority": 3,
            "tags": ["chart_with_upwards_trend"],
        ])
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AppFailure("ntfy não aceitou o alerta (HTTP \(status)). Confira servidor, tópico e token.")
        }
    }
}

// Reject redirects so the session credential remains scoped to the Devin origin.
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum DevinReader {
    static func read(organization: String) async throws -> [UsageWindow] {
        let org = organization.trimmingCharacters(in: .whitespacesAndNewlines)
        guard org.range(of: #"^org[_-][A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            throw AppFailure("Informe o ID interno da organização Devin (org_… ou org-…).")
        }
        var token = try Keychain.read("devin-token").trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("bearer ") { token = String(token.dropFirst(7)) }
        guard !token.isEmpty, !token.contains("\n"), !token.contains("\r") else {
            throw AppFailure("Salve a sessão do Devin nos ajustes. Consulte o guia de conexão.")
        }
        var request = URLRequest(url: URL(string: "https://app.devin.ai/api/\(org)/billing/quota/usage")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(org, forHTTPHeaderField: "x-cog-org-id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppFailure("Resposta inesperada do Devin.") }
        if http.statusCode == 401 || http.statusCode == 403 { throw AppFailure("Sessão Devin expirada ou organização sem acesso. Atualize a conexão nos ajustes.") }
        guard http.statusCode == 200 else { throw AppFailure("Devin indisponível (HTTP \(http.statusCode)). Nova tentativa em 5 min.") }
        let windows = try UsageParsing.devin(data)
        guard !windows.isEmpty else { throw AppFailure("Devin não retornou cotas compatíveis com esta integração experimental.") }
        return windows
    }
}
