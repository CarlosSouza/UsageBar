import Foundation
import CodexMultiAuth

extension UsageChecks {
    static func checkInstalledMultiAuth() throws {
        let snapshot = try MultiAuthClient(executable: MultiAuthClient.defaultExecutable).limits()
        print("Installed multi-auth: schema \(snapshot.schemaVersion), \(snapshot.accounts.count) accounts, \(snapshot.selectedAccount?.windows.count ?? 0) selected-account windows decoded")
    }

    static func runMultiAuthChecks() throws {
        let snapshot = try MultiAuthSnapshot.decode(Data(multiAuthFixture.utf8))
        requireMultiAuth(snapshot.selectedAccount?.index == 1)
        requireMultiAuth(snapshot.selectedAccount?.commandIndex == 2)
        let windows = snapshot.selectedAccount!.windows
        requireMultiAuth(windows.count == 2)
        requireMultiAuth(windows[0].usedPercent == 91)
        requireMultiAuth(windows[0].observedAt.timeIntervalSince1970 == 1_800_000_000)
        requireMultiAuth(windows[0].resetsAt.timeIntervalSince1970 == 1_800_003_600)
        requireMultiAuth(windows[0].title == "5h" && windows[1].title == "7d")
        requireMultiAuth(!windows[0].isFresh(at: Date(timeIntervalSince1970: 1_800_000_901)))

        let empty = #"{"schemaVersion":1,"selection":{"pinnedIndex":null,"routedIndex":null},"accounts":[]}"#
        requireMultiAuth(try MultiAuthSnapshot.decode(Data(empty.utf8)).accounts.isEmpty)
        requireMultiAuth(snapshot.accounts[0].windows.isEmpty)
        let unauthorized = multiAuthFixture.replacingOccurrences(of: "\"status\":200", with: "\"status\":401")
        requireMultiAuth(try MultiAuthSnapshot.decode(Data(unauthorized.utf8)).selectedAccount!.windows.isEmpty)
        let unknown = multiAuthFixture.replacingOccurrences(of: "\"usedPercent\":91", with: "\"usedPercent\":null")
        requireMultiAuth(try MultiAuthSnapshot.decode(Data(unknown.utf8)).selectedAccount!.windows.count == 1)
        let invalid = multiAuthFixture.replacingOccurrences(of: "\"usedPercent\":91", with: "\"usedPercent\":-1")
        requireMultiAuth(try MultiAuthSnapshot.decode(Data(invalid.utf8)).selectedAccount!.windows.count == 1)

        try expectMultiAuthError(.unsupportedSchema) {
            _ = try MultiAuthSnapshot.decode(Data(multiAuthFixture.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2").utf8))
        }
        try expectMultiAuthError(.invalidAccounts) {
            _ = try MultiAuthSnapshot.decode(Data(multiAuthFixture.replacingOccurrences(of: "\"index\":0", with: "\"index\":1").utf8))
        }
        try expectMultiAuthError(.invalidAccounts) {
            _ = try MultiAuthSnapshot.decode(Data(multiAuthFixture.replacingOccurrences(of: "\"routedIndex\":1", with: "\"routedIndex\":null").utf8))
        }

        let fixture = try makeMultiAuthExecutable()
        let client = MultiAuthClient(executable: fixture.appendingPathComponent("mock-cli").path)
        let account = try client.limits().selectedAccount!
        try client.select(account)
        let arguments = try String(contentsOf: fixture.appendingPathComponent("arguments"), encoding: .utf8)
        requireMultiAuth(arguments.contains("switch 2\n"))
        requireMultiAuth(try client.limits().selection.pinnedIndex == 1)
        try client.unpin()
        requireMultiAuth(try client.limits().selection.pinnedIndex == nil)
        _ = try client.limits(refresh: true)
        requireMultiAuth(try String(contentsOf: fixture.appendingPathComponent("arguments"), encoding: .utf8).contains("limits --json --refresh"))

        let changed = multiAuthFixture.replacingOccurrences(of: "Account 2", with: "Different account")
        try Data(changed.utf8).write(to: fixture.appendingPathComponent("snapshot.json"))
        let before = try Data(contentsOf: fixture.appendingPathComponent("arguments"))
        try expectMultiAuthError(.invalidAccounts) { try client.select(account) }
        let after = try String(contentsOf: fixture.appendingPathComponent("arguments"), encoding: .utf8)
        requireMultiAuth(after == String(decoding: before, as: UTF8.self) + "limits --json\n")

        try Data("failure".utf8).write(to: fixture.appendingPathComponent("mode"))
        try expectMultiAuthError(.commandFailed) { _ = try client.limits() }
        try Data("timeout".utf8).write(to: fixture.appendingPathComponent("mode"))
        let impatient = MultiAuthClient(executable: client.executable, timeout: 0.25)
        try expectMultiAuthError(.timedOut) { _ = try impatient.limits() }
        try Data("oversized".utf8).write(to: fixture.appendingPathComponent("mode"))
        try expectMultiAuthError(.commandFailed) { _ = try client.limits() }
        print("7 multi-auth checks passed: schema, quotas, commands, stale selection, errors, timeout, output limit")
    }
}

private func expectMultiAuthError(_ expected: MultiAuthError, operation: () throws -> Void) throws {
    do {
        try operation()
        preconditionFailure("Expected multi-auth error")
    } catch let error as MultiAuthError {
        requireMultiAuth(error == expected)
    }
}

private let multiAuthFixture = #"{"schemaVersion":1,"selection":{"pinnedIndex":null,"routedIndex":1},"accounts":[{"index":0,"label":"Account 1","enabled":false,"current":false,"quota":null},{"index":1,"label":"Account 2","enabled":true,"current":true,"quota":{"updatedAt":1800000000000,"status":200,"planType":"plus","primary":{"usedPercent":91,"windowMinutes":300,"resetAtMs":1800003600000},"secondary":{"usedPercent":20,"windowMinutes":10080,"resetAtMs":1800600000000}}}]}"#

private func makeMultiAuthExecutable() throws -> URL {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/multi-auth-checks/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(multiAuthFixture.utf8).write(to: directory.appendingPathComponent("snapshot.json"))
    let script = """
    #!/usr/bin/env python3
    import json
    import pathlib
    import sys
    import time
    root = pathlib.Path(__file__).parent
    with (root / "arguments").open("a") as output:
        output.write(" ".join(sys.argv[1:]) + "\\n")
    mode = (root / "mode").read_text() if (root / "mode").exists() else ""
    if mode == "failure":
        print("Untrusted diagnostic", file=sys.stderr)
        sys.exit(1)
    if mode == "timeout":
        time.sleep(5)
    if mode == "oversized":
        print("x" * 4100000)
        sys.exit(0)
    path = root / "snapshot.json"
    state = json.loads(path.read_text())
    if sys.argv[1] == "limits":
        print(json.dumps(state))
    elif sys.argv[1] == "switch":
        state["selection"]["pinnedIndex"] = int(sys.argv[2]) - 1
        path.write_text(json.dumps(state))
    elif sys.argv[1] == "unpin":
        state["selection"]["pinnedIndex"] = None
        path.write_text(json.dumps(state))
    else:
        sys.exit(1)
    """
    let executable = directory.appendingPathComponent("mock-cli")
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    return directory
}

private func requireMultiAuth(_ value: Bool) { precondition(value) }
