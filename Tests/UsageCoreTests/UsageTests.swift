import Foundation
import UsageCore

@main
struct UsageChecks {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func window(_ percent: Double = 90) -> UsageWindow {
        UsageWindow(id: "weekly", title: "Semana", usedPercent: percent, resetsAt: now.addingTimeInterval(3600), observedAt: now)
    }
    func testThresholdAndSeparateChannelsAndReset() {
        var ledger = AlertLedger()
        checkFalse(ledger.shouldDeliver(provider: "Claude", window: window(89.9), threshold: 90, channel: "mac", now: now))
        checkTrue(ledger.shouldDeliver(provider: "Claude", window: window(), threshold: 90, channel: "mac", now: now))
        ledger.acknowledge(provider: "Claude", window: window(), channel: "mac", now: now)
        checkFalse(ledger.shouldDeliver(provider: "Claude", window: window(), threshold: 90, channel: "mac", now: now))
        checkTrue(ledger.shouldDeliver(provider: "Claude", window: window(), threshold: 90, channel: "ntfy", now: now))
        var next = window(); next.resetsAt = now.addingTimeInterval(7200)
        checkTrue(ledger.shouldDeliver(provider: "Claude", window: next, threshold: 90, channel: "mac", now: now))
    }
    func testStaleExpiredAndInvalidDataCannotAlert() {
        var stale = window(); stale.observedAt = now.addingTimeInterval(-901)
        var expired = window(); expired.resetsAt = now
        var future = window(); future.observedAt = now.addingTimeInterval(120)
        for sample in [stale, expired, future, window(.nan), window(-1)] {
            checkFalse(AlertLedger().shouldDeliver(provider: "Claude", window: sample, threshold: 90, channel: "mac", now: now))
        }
    }
    func testLedgerSurvivesRestart() throws {
        var ledger = AlertLedger()
        ledger.acknowledge(provider: "Codex", window: window(), channel: "mac", now: now)
        let restored = try JSONDecoder().decode(AlertLedger.self, from: JSONEncoder().encode(ledger))
        checkFalse(restored.shouldDeliver(provider: "Codex", window: window(), threshold: 90, channel: "mac", now: now))
    }
    func testCodexUsesAllBucketsWithoutDuplicatingFallback() throws {
        let json = #"{"rateLimits":{"primary":{"usedPercent":1,"resetsAt":1800003600}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":95,"windowDurationMins":300,"resetsAt":1800003600},"secondary":null},"other":{"primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":1800600000}}}}"#
        let windows = try UsageParsing.codex(Data(json.utf8), now: now)
        checkEqual(windows.count, 2)
        checkEqual(windows.first?.usedPercent, 95)
    }
    func testMissingLimitsAreUnknownNotZero() throws {
        checkTrue(try UsageParsing.codex(Data("{}".utf8)).isEmpty)
        checkTrue(try UsageParsing.claude(Data(#"{"observed_at":1800000000,"rate_limits":{}}"#.utf8)).isEmpty)
    }
    func testDevinExplicitUnitsAndResetFormats() throws {
        let data = Data(#"{"daily_percentage":1,"daily_reset_at":"2027-01-16T09:00:00Z","weekly_percentage":0.9,"weekly_reset_at":1800600000000}"#.utf8)
        let percentage = try UsageParsing.devin(data, now: now)
        checkEqual(percentage[0].usedPercent, 1)
        checkEqual(percentage[1].usedPercent, 0.9)
        checkEqual(percentage[1].resetsAt.timeIntervalSince1970, 1_800_600_000)
    }
    func testDevinPercentageIsNotMultipliedAgain() throws {
        let data = Data(#"{"daily_percentage":0,"daily_reset_at":1800003600,"weekly_percentage":100,"weekly_reset_at":1800600000}"#.utf8)
        let windows = try UsageParsing.devin(data, now: now)
        checkEqual(windows[1].usedPercent, 100)
    }
    func testDevinWithoutResetCannotTriggerFalseCycleAlerts() throws {
        checkTrue(try UsageParsing.devin(Data(#"{"daily_percentage":95}"#.utf8)).isEmpty)
    }
    func testNtfyDestinationValidation() throws {
        let destination = try NtfyDestination(server: "https://ntfy.sh/", topic: "usagebar_A1-b2")
        checkEqual(destination.server.absoluteString, "https://ntfy.sh")
        checkEqual(destination.subscriptionURL.absoluteString, "https://ntfy.sh/usagebar_A1-b2")
        checkEqual(try NtfyDestination(server: "http://localhost:2586", topic: "local").topic, "local")
        checkThrows(NtfyConfigurationError.insecureServer) {
            _ = try NtfyDestination(server: "http://example.com", topic: "topic")
        }
        checkThrows(NtfyConfigurationError.invalidTopic) {
            _ = try NtfyDestination(server: "https://ntfy.sh", topic: "easy topic")
        }
    }
}

private func checkTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value, "Expected true", file: file, line: line)
}
private func checkFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(!value, "Expected false", file: file, line: line)
}
private func checkEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    precondition(lhs == rhs, "Values differ", file: file, line: line)
}
private func checkThrows<E: Error & Equatable>(_ expected: E, _ operation: () throws -> Void,
                                                file: StaticString = #file, line: UInt = #line) {
    do {
        try operation()
        preconditionFailure("Expected error", file: file, line: line)
    } catch let error as E {
        precondition(error == expected, "Unexpected error", file: file, line: line)
    } catch {
        preconditionFailure("Wrong error type", file: file, line: line)
    }
}
extension UsageChecks {
    static func main() throws {
        let checks = UsageChecks()
        checks.testThresholdAndSeparateChannelsAndReset()
        checks.testStaleExpiredAndInvalidDataCannotAlert()
        try checks.testLedgerSurvivesRestart()
        try checks.testCodexUsesAllBucketsWithoutDuplicatingFallback()
        try checks.testMissingLimitsAreUnknownNotZero()
        try checks.testDevinExplicitUnitsAndResetFormats()
        try checks.testDevinWithoutResetCannotTriggerFalseCycleAlerts()
        try checks.testDevinPercentageIsNotMultipliedAgain()
        try checks.testNtfyDestinationValidation()
        print("9 UsageCore checks passed")
    }
}
