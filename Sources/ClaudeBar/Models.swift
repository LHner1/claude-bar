import Foundation
import SwiftUI

enum Paths {
    static let claude = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    static let sessions = claude.appendingPathComponent("sessions")
    static let projects = claude.appendingPathComponent("projects")
    static let bar = claude.appendingPathComponent("claude-bar")
    static let limits = bar.appendingPathComponent("limits.json")
    static let history = bar.appendingPathComponent("limits-history.jsonl")
    static let barSessions = bar.appendingPathComponent("sessions")
}

// MARK: - Sessions

enum SessionState: Int, Comparable {
    case waiting = 0, idle, busy, unknown

    init(_ raw: String?) {
        switch raw {
        case "waiting": self = .waiting
        case "idle": self = .idle
        case "busy": self = .busy
        default: self = .unknown
        }
    }

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var color: Color {
        switch self {
        case .waiting: .red
        case .idle: .green
        case .busy: .orange
        case .unknown: .gray
        }
    }

    var label: String {
        switch self {
        case .waiting: "needs you"
        case .idle: "ready"
        case .busy: "working"
        case .unknown: "unknown"
        }
    }
}

struct ClaudeSession: Identifiable {
    let id: String
    let pid: Int32
    let name: String
    let cwd: String
    let state: SessionState
    let waitingFor: String?
    let statusSince: Date?
    var model: String?
    var contextPct: Double?
    var costUSD: Double?

    var folder: String { URL(fileURLWithPath: cwd).lastPathComponent }
}

/// Traffic light summary: each lamp is lit as soon as at least one session is in that state.
struct TrafficLight: Equatable {
    var red = false     // a session needs you (permission prompt, question …)
    var yellow = false  // a session is working
    var green = false   // a session is ready for input

    init(_ sessions: [ClaudeSession]) {
        red = sessions.contains { $0.state == .waiting }
        yellow = sessions.contains { $0.state == .busy }
        green = sessions.contains { $0.state == .idle }
    }

    init() {}

    var isOff: Bool { !red && !yellow && !green }
}

// MARK: - Limits

struct LimitWindow: Equatable {
    var usedPct: Double
    var resetsAt: Date

    /// After the reset the window is empty until a session reports fresh data.
    func effectivePct(at now: Date) -> Double { resetsAt > now ? usedPct : 0 }
}

struct Limits: Equatable {
    var fiveHour: LimitWindow?
    var sevenDay: LimitWindow?
    var spend: LimitWindow?
    var updatedAt: Date
}

struct LimitSample: Identifiable {
    let date: Date
    let fiveHour: Double?
    let sevenDay: Double?
    var id: Date { date }
}

// MARK: - Usage

struct TokenCounts: Equatable {
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0
    var messages = 0

    var total: Int { input + output + cacheWrite + cacheRead }

    static func + (a: Self, b: Self) -> Self {
        TokenCounts(input: a.input + b.input, output: a.output + b.output, cacheWrite: a.cacheWrite + b.cacheWrite,
                    cacheRead: a.cacheRead + b.cacheRead, messages: a.messages + b.messages)
    }

    static func += (a: inout Self, b: Self) { a = a + b }
}

struct UsageSnapshot {
    /// Hourly buckets per model
    var hourly: [Date: [String: TokenCounts]] = [:]
    /// Session IDs per day
    var sessionsByDay: [Date: Set<String>] = [:]
    var scannedAt: Date?
}

// MARK: - Formatting

enum Fmt {
    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        switch d {
        case 1_000_000_000...: return String(format: "%.2fB", d / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", d / 1_000_000)
        case 10_000...: return String(format: "%.0fK", d / 1_000)
        case 1_000...: return String(format: "%.1fK", d / 1_000)
        default: return "\(n)"
        }
    }

    /// Compact form for the menu bar: 1.2M, 850K
    static func tokensShort(_ n: Int) -> String {
        let d = Double(n)
        switch d {
        case 1_000_000_000...: return String(format: "%.1fB", d / 1_000_000_000)
        case 10_000_000...: return String(format: "%.0fM", d / 1_000_000)
        case 1_000_000...: return String(format: "%.1fM", d / 1_000_000)
        case 1_000...: return String(format: "%.0fK", d / 1_000)
        default: return "\(n)"
        }
    }

    static func duration(_ interval: TimeInterval) -> String {
        let secs = max(0, Int(interval))
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }

    static func relative(_ date: Date, now: Date) -> String {
        let secs = now.timeIntervalSince(date)
        return secs < 60 ? "just now" : "\(duration(secs)) ago"
    }

    static func resetTime(_ date: Date, now: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow \(time)"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    static func percentColor(_ pct: Double) -> Color {
        pct >= 85 ? .red : pct >= 60 ? .orange : .green
    }

    /// claude-opus-5-5 → Opus 5.5, claude-haiku-4-5-20251001 → Haiku 4.5, claude-3-5-sonnet-20241022 → Sonnet 3.5
    static func modelName(_ id: String) -> String {
        var parts = id.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        if let last = parts.last, last.count == 8, Int(last) != nil { parts.removeLast() }
        guard let familyIndex = parts.firstIndex(where: { Int($0) == nil }) else { return id }
        let family = parts.remove(at: familyIndex).capitalized
        let version = parts.filter { Int($0) != nil }.joined(separator: ".")
        return version.isEmpty ? family : "\(family) \(version)"
    }

    static func modelColor(_ name: String) -> Color {
        let lower = name.lowercased()
        if lower.hasPrefix("opus") { return Color(red: 0.85, green: 0.47, blue: 0.34) }
        if lower.hasPrefix("sonnet") { return .blue }
        if lower.hasPrefix("haiku") { return .teal }
        if lower.hasPrefix("fable") { return .purple }
        return .gray
    }

    /// Colors for a list of models: newest version of each family in full color, older ones lighter.
    static func modelColors(_ names: [String]) -> [String: Color] {
        func version(_ name: String) -> [Int] {
            name.split(separator: " ").last?.split(separator: ".").compactMap { Int($0) } ?? []
        }
        func family(_ name: String) -> String { String(name.split(separator: " ").first ?? "") }
        var result: [String: Color] = [:]
        for (_, members) in Dictionary(grouping: names, by: family) {
            let sorted = members.sorted { version($0).lexicographicallyPrecedes(version($1)) }.reversed()
            for (index, name) in sorted.enumerated() {
                result[name] = modelColor(name).opacity(max(0.35, 1 - Double(index) * 0.35))
            }
        }
        return result
    }
}
