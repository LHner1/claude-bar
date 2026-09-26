import Charts
import ServiceManagement
import SwiftUI

struct PopupView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model)
            PanelDivider()
            LimitsSection(model: model)
            PanelDivider().padding(.top, 10)
            SessionsSection(model: model)
            PanelDivider().padding(.top, 10)
            UsageSection(model: model)
            FooterView(model: model)
        }
        .frame(width: 300)
    }
}

// MARK: - Header

private struct HeaderView: View {
    @ObservedObject var model: AppModel
    @AppStorage(Setting.showFiveHour) private var showFiveHour = true
    @AppStorage(Setting.showSevenDay) private var showSevenDay = true
    @AppStorage(Setting.showTodayTokens) private var showTodayTokens = false
    @AppStorage(Setting.lightPerSession) private var lightPerSession = true

    var body: some View {
        HStack(spacing: 10) {
            TrafficLightView(light: model.light, lampSize: 7, spacing: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude Code")
                    .font(.system(size: 13, weight: .semibold))
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Section("Show in Menu Bar") {
                    Toggle("One Traffic Light per Session", isOn: $lightPerSession)
                    Toggle("5-Hour Limit", isOn: $showFiveHour)
                    Toggle("Weekly Limit", isOn: $showSevenDay)
                    Toggle("Tokens Today", isOn: $showTodayTokens)
                }
                Divider()
                Toggle("Launch at Login", isOn: launchAtLogin)
                Button("Open Claude Folder") {
                    NSWorkspace.shared.open(Paths.claude)
                }
                Divider()
                Button("Quit ClaudeBar") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var summary: String {
        let sessions = model.sessions
        guard !sessions.isEmpty else { return "No active session" }
        var parts: [String] = []
        let waiting = sessions.filter { $0.state == .waiting }.count
        let idle = sessions.filter { $0.state == .idle }.count
        let busy = sessions.filter { $0.state.isWorking }.count
        if waiting > 0 { parts.append("\(waiting) need\(waiting == 1 ? "s" : "") you") }
        if idle > 0 { parts.append("\(idle) ready") }
        if busy > 0 { parts.append("\(busy) working") }
        return parts.joined(separator: " · ")
    }

    private var launchAtLogin: Binding<Bool> {
        Binding {
            SMAppService.mainApp.status == .enabled
        } set: { enabled in
            try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }
}

// MARK: - Limits

private struct LimitsSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Limits")
            HStack(spacing: 0) {
                LimitGauge(title: "5 Hours", window: model.limits?.fiveHour, now: model.now)
                LimitGauge(title: "Week", window: model.limits?.sevenDay, now: model.now)
                if let spend = model.limits?.spend {
                    LimitGauge(title: "Spend", window: spend, now: model.now)
                }
            }
            .padding(.top, 4)

            if model.limits == nil {
                Text("No limit data yet. It arrives through the status line as soon as a Claude Code session gets a response.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            } else {
                HistoryChart(samples: model.history, now: model.now)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
            }
        }
    }
}

private struct HistoryChart: View {
    let samples: [LimitSample]
    let now: Date

    private var recent: [LimitSample] {
        samples.filter { $0.date > now.addingTimeInterval(-24 * 3600) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Last 24 hours")
                    .foregroundStyle(.secondary)
                Spacer()
                legend("5h", Color.accentColor)
                legend("Week", Color.secondary)
            }
            .font(.system(size: 10))

            if recent.count < 2 {
                Text("Collecting data points …")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            } else {
                Chart {
                    ForEach(recent) { sample in
                        if let h5 = sample.fiveHour {
                            AreaMark(x: .value("Time", sample.date), y: .value("5h", h5), series: .value("Series", "5h"))
                                .foregroundStyle(LinearGradient(colors: [.accentColor.opacity(0.35), .accentColor.opacity(0.02)],
                                                                startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.stepEnd)
                            LineMark(x: .value("Time", sample.date), y: .value("5h", h5), series: .value("Series", "5h"))
                                .foregroundStyle(Color.accentColor)
                                .lineStyle(StrokeStyle(lineWidth: 1.2))
                                .interpolationMethod(.stepEnd)
                        }
                        if let d7 = sample.sevenDay {
                            LineMark(x: .value("Time", sample.date), y: .value("Week", d7), series: .value("Series", "7d"))
                                .foregroundStyle(.secondary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                .interpolationMethod(.stepEnd)
                        }
                    }
                }
                .chartXScale(domain: now.addingTimeInterval(-24 * 3600)...now)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine().foregroundStyle(.primary.opacity(0.08))
                        AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.system(size: 8)) }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisGridLine().foregroundStyle(.primary.opacity(0.08))
                        AxisValueLabel(format: .dateTime.hour()).font(.system(size: 8))
                    }
                }
                .frame(height: 60)
            }
        }
    }

    private func legend(_ title: String, _ color: some ShapeStyle) -> some View {
        HStack(spacing: 3) {
            Capsule().fill(color).frame(width: 8, height: 2)
            Text(title).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sessions

private struct SessionsSection: View {
    @ObservedObject var model: AppModel
    private let maxShown = 6

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Sessions")
            if model.sessions.isEmpty {
                Text("No Claude Code session running")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(height: 28)
            } else {
                VStack(spacing: 2) {
                    ForEach(model.sessions.prefix(maxShown)) { session in
                        SessionRow(session: session, now: model.now) {
                            model.closePopup?()
                            if !WindowFocuser.focus(session) {
                                WindowFocuser.revealFolder(session.cwd)
                            }
                        }
                    }
                    if model.sessions.count > maxShown {
                        Text("+ \(model.sessions.count - maxShown) more")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }
}

private struct SessionRow: View {
    let session: ClaudeSession
    let now: Date
    let open: () -> Void
    // ObservableObject instead of @State: @State is a macro in newer SDKs and the macro plugin
    // is missing from the Command Line Tools, so this keeps the app buildable without Xcode.
    @StateObject private var hover = HoverState()

    var body: some View {
        HStack(spacing: 8) {
            TrafficLightView(light: TrafficLight(session.state), lampSize: 4.5, spacing: 1.5)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(details)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(stateText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(session.state == .unknown ? Color.secondary : session.state.color)
                    .lineLimit(1)
                if let since = session.statusSince {
                    Text("for \(Fmt.duration(now.timeIntervalSince(since)))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(hover.isHovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hover.isHovering = $0 }
        .help("Show window · \(session.cwd)")
        .onTapGesture(perform: open)
        .contextMenu {
            Button("Show Window", action: open)
            Button("Open Folder") { WindowFocuser.revealFolder(session.cwd) }
            Button("Copy Session ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.id, forType: .string)
            }
        }
    }

    private var stateText: String {
        if session.state == .waiting, let reason = session.waitingFor { return reason }
        return session.state.label
    }

    private var details: String {
        var parts: [String] = []
        if session.name != session.folder, !session.folder.isEmpty { parts.append(session.folder) }
        if let model = session.model { parts.append(model) }
        if let ctx = session.contextPct { parts.append("context \(Int(ctx.rounded()))%") }
        return parts.isEmpty ? "PID \(session.pid)" : parts.joined(separator: " · ")
    }
}

private final class HoverState: ObservableObject {
    @Published var isHovering = false
}

// MARK: - Usage

private enum UsageRange: String, CaseIterable, Identifiable {
    case today = "Today", week = "7 Days", month = "30 Days"
    var id: Self { self }
}

private struct UsageBar: Identifiable {
    let date: Date
    let model: String
    let tokens: Int
    var id: String { "\(date.timeIntervalSince1970)-\(model)" }
}

private struct UsageSection: View {
    @ObservedObject var model: AppModel
    @AppStorage("usageRange") private var range: UsageRange = .today

    var body: some View {
        let stats = computeStats()
        VStack(spacing: 0) {
            SectionHeader(title: "Usage")
            Picker("", selection: $range) {
                ForEach(UsageRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if model.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .frame(height: 90)
            } else {
                UsageChart(bars: stats.bars, unit: range == .today ? .hour : .day, domain: stats.domain,
                           models: stats.models.map(\.name), colors: stats.colors)
                    .frame(height: 90)
                    .padding(.horizontal, 12)
            }

            VStack(spacing: 2) {
                DetailRow(label: "Total tokens", value: Fmt.tokens(stats.totals.total))
                DetailRow(label: "Input", value: Fmt.tokens(stats.totals.input))
                DetailRow(label: "Output", value: Fmt.tokens(stats.totals.output))
                DetailRow(label: "Cache write", value: Fmt.tokens(stats.totals.cacheWrite))
                DetailRow(label: "Cache read", value: Fmt.tokens(stats.totals.cacheRead))
                DetailRow(label: "Responses", value: "\(stats.totals.messages)")
                DetailRow(label: "Sessions", value: "\(stats.sessions)")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            if !stats.models.isEmpty {
                SectionHeader(title: "Models")
                VStack(spacing: 2) {
                    ForEach(stats.models, id: \.name) { entry in
                        DetailRow(label: entry.name, value: share(entry.tokens, of: stats.totals.total),
                                  color: stats.colors[entry.name])
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private func share(_ part: Int, of total: Int) -> String {
        guard total > 0 else { return "–" }
        let pct = Double(part) / Double(total) * 100
        return "\(Fmt.tokens(part))  \(pct < 1 ? "<1" : "\(Int(pct.rounded()))")%"
    }

    private struct Stats {
        var bars: [UsageBar] = []
        var totals = TokenCounts()
        var sessions = 0
        var models: [(name: String, tokens: Int)] = []
        var colors: [String: Color] = [:]
        var domain: ClosedRange<Date>
    }

    private func computeStats() -> Stats {
        let cal = Calendar.current
        let today = cal.startOfDay(for: model.now)
        let end = cal.date(byAdding: .day, value: 1, to: today)!
        let start: Date
        switch range {
        case .today: start = today
        case .week: start = cal.date(byAdding: .day, value: -6, to: today)!
        case .month: start = cal.date(byAdding: .day, value: -29, to: today)!
        }

        var stats = Stats(domain: start...end)
        var perBucket: [Date: [String: Int]] = [:]
        var perModel: [String: Int] = [:]

        for (hour, models) in model.usage.hourly where hour >= start && hour < end {
            let bucket = range == .today ? hour : cal.startOfDay(for: hour)
            for (modelId, counts) in models {
                let name = Fmt.modelName(modelId)
                stats.totals += counts
                perBucket[bucket, default: [:]][name, default: 0] += counts.total
                perModel[name, default: 0] += counts.total
            }
        }

        stats.bars = perBucket.flatMap { date, models in
            models.map { UsageBar(date: date, model: $0.key, tokens: $0.value) }
        }
        stats.models = perModel.sorted { $0.value > $1.value }.map { (name: $0.key, tokens: $0.value) }
        stats.colors = Fmt.modelColors(stats.models.map(\.name))
        stats.sessions = model.usage.sessionsByDay
            .filter { $0.key >= start && $0.key < end }
            .values.reduce(into: Set<String>()) { $0.formUnion($1) }.count
        return stats
    }
}

private struct UsageChart: View {
    let bars: [UsageBar]
    let unit: Calendar.Component
    let domain: ClosedRange<Date>
    let models: [String]
    let colors: [String: Color]

    var body: some View {
        Chart(bars) { bar in
            BarMark(x: .value("Time", bar.date, unit: unit), y: .value("Tokens", bar.tokens))
                .foregroundStyle(by: .value("Model", bar.model))
                .cornerRadius(1.5)
        }
        .chartForegroundStyleScale(domain: models, range: models.map { colors[$0] ?? .gray })
        .chartLegend(.hidden)
        .chartXScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.primary.opacity(0.08))
                AxisValueLabel {
                    Text(Fmt.tokensShort(value.as(Int.self) ?? 0)).font(.system(size: 8))
                }
            }
        }
        .chartXAxis {
            if unit == .hour {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour()).font(.system(size: 8))
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: domainDays > 7 ? 7 : 1)) { _ in
                    AxisValueLabel(format: domainDays > 7 ? .dateTime.day().month(.defaultDigits) : .dateTime.weekday(.narrow))
                        .font(.system(size: 8))
                }
            }
        }
        .overlay {
            if bars.isEmpty {
                Text("No usage in this period")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var domainDays: Int {
        Int(domain.upperBound.timeIntervalSince(domain.lowerBound) / 86400)
    }
}

// MARK: - Footer

private struct FooterView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack {
            if let limits = model.limits {
                Text("Limits: \(Fmt.relative(limits.updatedAt, now: model.now))")
            } else {
                Text("Status line not active yet")
            }
            Spacer()
            if let scanned = model.usage.scannedAt {
                Text("Usage: \(scanned.formatted(date: .omitted, time: .shortened))")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}
