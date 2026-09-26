import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [ClaudeSession] = []
    @Published private(set) var light = TrafficLight()
    @Published private(set) var limits: Limits?
    @Published private(set) var history: [LimitSample] = []
    @Published private(set) var usage = UsageSnapshot()
    @Published private(set) var isScanning = true
    @Published private(set) var now = Date()

    /// Set by the status item controller so views can dismiss the popup.
    var closePopup: (() -> Void)?

    private let scanner = UsageScanner()
    private var timers: [Timer] = []
    private var limitsModified: Date?
    private var historyModified: Date?

    init() {
        refreshSessions()
        refreshLimits()
        refreshUsage()
        schedule(every: 1.5) { $0.refreshSessions() }
        schedule(every: 5) { $0.refreshLimits() }
        schedule(every: 30) { $0.refreshUsage() }
        schedule(every: 15) { $0.now = Date() }
    }

    private func schedule(every interval: TimeInterval, _ action: @escaping @MainActor (AppModel) -> Void) {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    // MARK: - Sessions

    func refreshSessions() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: Paths.sessions, includingPropertiesForKeys: nil)) ?? []
        var result: [ClaudeSession] = []

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let pid = (obj["pid"] as? NSNumber)?.int32Value, isClaudeProcess(pid),
                  let sessionId = obj["sessionId"] as? String
            else { continue }
            // Sessions spawned through the Agent SDK have no window and no status – skip them.
            if (obj["entrypoint"] as? String)?.hasPrefix("sdk") == true { continue }

            let cwd = obj["cwd"] as? String ?? ""
            let name = (obj["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? URL(fileURLWithPath: cwd).lastPathComponent
            let since = (obj["statusUpdatedAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
            var session = ClaudeSession(id: sessionId, pid: pid, name: name, cwd: cwd,
                                        state: SessionState(obj["status"] as? String),
                                        waitingFor: obj["waitingFor"] as? String, statusSince: since)

            // Extra info from the status line (model, context, cost)
            let extra = Paths.barSessions.appendingPathComponent("\(sessionId).json")
            if sessionId.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil,
               let data = try? Data(contentsOf: extra),
               let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                session.model = (info["model_id"] as? String).map(Fmt.modelName) ?? info["model_name"] as? String
                session.contextPct = (info["context_pct"] as? NSNumber)?.doubleValue
                session.costUSD = (info["cost_usd"] as? NSNumber)?.doubleValue
            }
            result.append(session)
        }

        result.sort { ($0.state, $0.statusSince ?? .distantPast) < ($1.state, $1.statusSince ?? .distantPast) }
        if result.map(\.signature) != sessions.map(\.signature) { sessions = result }
        let newLight = TrafficLight(result)
        if newLight != light { light = newLight }
    }

    private func isClaudeProcess(_ pid: Int32) -> Bool {
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return true }
        return String(cString: buffer).lowercased().contains("claude")
    }

    // MARK: - Limits

    func refreshLimits() {
        let modified = modificationDate(Paths.limits)
        if modified != limitsModified {
            limitsModified = modified
            limits = loadLimits()
        }
        let historyDate = modificationDate(Paths.history)
        if historyDate != historyModified {
            historyModified = historyDate
            history = loadHistory()
        }
    }

    private func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func loadLimits() -> Limits? {
        guard let data = try? Data(contentsOf: Paths.limits),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func window(_ key: String) -> LimitWindow? {
            guard let d = obj[key] as? [String: Any],
                  let pct = (d["used_percentage"] as? NSNumber)?.doubleValue,
                  let reset = (d["resets_at"] as? NSNumber)?.doubleValue else { return nil }
            return LimitWindow(usedPct: pct, resetsAt: Date(timeIntervalSince1970: reset))
        }
        let updated = (obj["updated_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? .distantPast
        return Limits(fiveHour: window("five_hour"), sevenDay: window("seven_day"), spend: window("spend_limit"),
                      updatedAt: updated)
    }

    private func loadHistory() -> [LimitSample] {
        guard let text = try? String(contentsOf: Paths.history, encoding: .utf8) else { return [] }
        let cutoff = Date().addingTimeInterval(-7 * 86400).timeIntervalSince1970
        return text.split(separator: "\n").compactMap { line in
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let t = (obj["t"] as? NSNumber)?.doubleValue, t >= cutoff else { return nil }
            return LimitSample(date: Date(timeIntervalSince1970: t),
                               fiveHour: (obj["h5"] as? NSNumber)?.doubleValue,
                               sevenDay: (obj["d7"] as? NSNumber)?.doubleValue)
        }
    }

    // MARK: - Usage

    func refreshUsage() {
        Task {
            let snapshot = await scanner.scan()
            usage = snapshot
            isScanning = false
        }
    }

    // MARK: - Derived values

    var todayTokens: Int {
        let start = Calendar.current.startOfDay(for: now)
        return usage.hourly.filter { $0.key >= start }.values.reduce(0) { sum, models in
            sum + models.values.reduce(0) { $0 + $1.total }
        }
    }

    var hasStatusLineData: Bool { limits != nil }
}

private extension ClaudeSession {
    var signature: String {
        "\(id)|\(state)|\(name)|\(waitingFor ?? "")|\(statusSince?.timeIntervalSince1970 ?? 0)|\(model ?? "")|\(contextPct ?? -1)"
    }
}
