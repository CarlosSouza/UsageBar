import SwiftUI
import WidgetKit
import UsageCore

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snapshot = Self.load()
        completion(UsageEntry(date: .now, snapshot: context.isPreview && snapshot == nil ? .preview : snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date()
        let snapshot = Self.load()
        let moments = [now] + (snapshot?.transitions(after: now) ?? []).prefix(10)
        completion(Timeline(entries: moments.map { UsageEntry(date: $0, snapshot: snapshot) },
                            policy: .after(now.addingTimeInterval(1800))))
    }

    /// The sandbox redirects NSHomeDirectory to the container; the read-only exception covers the real home.
    private static func load() -> WidgetSnapshot? {
        guard let account = getpwuid(getuid()), let home = account.pointee.pw_dir else { return nil }
        let url = URL(fileURLWithPath: String(cString: home))
            .appendingPathComponent("Library/Application Support/UsageBar/\(WidgetSnapshot.fileName)")
        return (try? Data(contentsOf: url)).flatMap { try? WidgetSnapshot.decode($0) }
    }
}

struct ProviderStyle {
    let id: String
    let name: String
    let symbol: String
    let color: Color
    let summary: String

    static let all = [
        ProviderStyle(id: "claude", name: "Claude", symbol: "sparkle", color: .orange, summary: "Limites da assinatura Claude."),
        ProviderStyle(id: "codex", name: "Codex", symbol: "terminal", color: .teal, summary: "Limites da assinatura Codex."),
        ProviderStyle(id: "devin", name: "Devin", symbol: "cpu", color: .blue, summary: "Limites da assinatura Devin.")
    ]
}

struct ProviderColumn: View {
    let style: ProviderStyle
    let snapshot: WidgetSnapshot?
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(style.name, systemImage: style.symbol)
                .font(.headline).lineLimit(1)
            if let snapshot, let provider = snapshot.provider(style.id) {
                if provider.windows.isEmpty {
                    message(provider.error ?? "Aguardando dados…")
                } else {
                    ForEach(provider.topWindows(2)) { window in
                        WindowRow(window: window, title: shortTitle(window.title), threshold: provider.threshold, color: style.color)
                    }
                    Spacer(minLength: 0)
                    footer(provider)
                }
            } else {
                message(snapshot == nil ? "Abra o UsageBar para começar." : "Desativado no UsageBar.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Codex titles carry the bucket name ("codex · 5 horas"), which repeats the column header.
    private func shortTitle(_ title: String) -> String {
        let prefix = "\(style.id) · "
        return title.lowercased().hasPrefix(prefix) ? String(title.dropFirst(prefix.count)) : title
    }

    private func resetLabel(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).lineLimit(4)
    }

    @ViewBuilder
    private func footer(_ provider: WidgetSnapshot.Provider) -> some View {
        if provider.isFresh(at: date) {
            if let reset = provider.topWindows(2).map(\.resetsAt).min() {
                Text("Renova \(resetLabel(reset))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        } else if let observed = provider.windows.map(\.observedAt).max() {
            Text("Dados antigos · \(observed.formatted(date: .omitted, time: .shortened))")
                .font(.caption2).foregroundStyle(.orange).lineLimit(1)
        }
    }
}

struct WindowRow: View {
    let window: UsageWindow
    let title: String
    let threshold: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(window.usedPercent, specifier: "%.0f")%")
                    .font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit()
            }
            ProgressView(value: min(window.usedPercent, 100), total: 100)
                .tint(window.usedPercent >= threshold ? .red : color)
        }
        .accessibilityElement(children: .combine)
    }
}

func singleProviderConfiguration(_ style: ProviderStyle) -> some WidgetConfiguration {
    StaticConfiguration(kind: "usagebar.\(style.id)", provider: UsageProvider()) { entry in
        ProviderColumn(style: style, snapshot: entry.snapshot, date: entry.date)
            .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName(style.name)
    .description(style.summary)
    .supportedFamilies([.systemSmall])
}

struct ClaudeWidget: Widget {
    var body: some WidgetConfiguration { singleProviderConfiguration(ProviderStyle.all[0]) }
}

struct CodexWidget: Widget {
    var body: some WidgetConfiguration { singleProviderConfiguration(ProviderStyle.all[1]) }
}

struct DevinWidget: Widget {
    var body: some WidgetConfiguration { singleProviderConfiguration(ProviderStyle.all[2]) }
}

struct AllProvidersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "usagebar.all", provider: UsageProvider()) { entry in
            HStack(alignment: .top, spacing: 14) {
                ForEach(visibleStyles(entry.snapshot), id: \.id) { style in
                    ProviderColumn(style: style, snapshot: entry.snapshot, date: entry.date)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Todos os limites")
        .description("Claude, Codex e Devin lado a lado.")
        .supportedFamilies([.systemMedium])
    }

    /// Disabled providers are hidden so the enabled ones get the width; with none enabled, all show a hint.
    private func visibleStyles(_ snapshot: WidgetSnapshot?) -> [ProviderStyle] {
        let enabled = ProviderStyle.all.filter { snapshot?.provider($0.id) != nil }
        return enabled.isEmpty ? Array(ProviderStyle.all.prefix(1)) : enabled
    }
}

@main
struct UsageBarWidgets: WidgetBundle {
    var body: some Widget {
        ClaudeWidget()
        CodexWidget()
        DevinWidget()
        AllProvidersWidget()
    }
}

extension WidgetSnapshot {
    static var preview: WidgetSnapshot {
        let now = Date()
        func window(_ id: String, _ title: String, _ percent: Double, hours: Double) -> UsageWindow {
            UsageWindow(id: id, title: title, usedPercent: percent, resetsAt: now.addingTimeInterval(hours * 3600), observedAt: now)
        }
        return WidgetSnapshot(providers: [
            .init(id: "claude", threshold: 90, windows: [window("five_hour", "5 horas", 42, hours: 3), window("seven_day", "7 dias", 18, hours: 96)], error: nil),
            .init(id: "codex", threshold: 90, windows: [window("codex.primary", "5 horas", 27, hours: 2), window("codex.secondary", "7 dias", 61, hours: 120)], error: nil),
            .init(id: "devin", threshold: 90, windows: [window("daily", "Diário", 12, hours: 10), window("weekly", "Semanal", 35, hours: 72)], error: nil)
        ])
    }
}
