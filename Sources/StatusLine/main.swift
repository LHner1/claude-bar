// claude-bar-statusline
//
// Configured as Claude Code's `statusLine` command. Reads the session JSON from stdin, stores the
// rate limits and per-session info under ~/.claude/claude-bar/ for the menu bar app, and prints a
// compact status line.
//
// If ~/.claude/claude-bar/config.json contains a `wrapped_command`, that command (the user's
// previous status line) receives the same JSON and its output is printed instead of ours.

import Foundation

let fm = FileManager.default
let baseDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/claude-bar")
let sessionsDir = baseDir.appendingPathComponent("sessions")
let limitsURL = baseDir.appendingPathComponent("limits.json")
let historyURL = baseDir.appendingPathComponent("limits-history.jsonl")
let configURL = baseDir.appendingPathComponent("config.json")
let now = Date().timeIntervalSince1970

// MARK: - Helpers

func number(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }

func dict(_ any: Any?) -> [String: Any]? { any as? [String: Any] }

func readJSON(_ url: URL) -> [String: Any] {
    (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
}

func writeJSON(_ obj: Any, to url: URL) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
    try? data.write(to: url, options: .atomic)
}

func appendLine(_ data: Data, to url: URL) {
    if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: data + Data("\n".utf8))
}

/// Keeps the history file and the session store small.
func cleanup() {
    if let size = (try? fm.attributesOfItem(atPath: historyURL.path))?[.size] as? Int, size > 512_000,
       let text = try? String(contentsOf: historyURL, encoding: .utf8) {
        let lines = text.split(separator: "\n").suffix(4000)
        try? (lines.joined(separator: "\n") + "\n").write(to: historyURL, atomically: true, encoding: .utf8)
    }
    let cutoff = Date().addingTimeInterval(-7 * 86400)
    for file in (try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        if modified < cutoff { try? fm.removeItem(at: file) }
    }
}

/// Runs the user's previous status line command with the same input and returns its exit code.
func runWrapped(_ command: String, input: Data) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    let stdin = Pipe()
    process.standardInput = stdin
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    do {
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: input)
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        return 1
    }
}

struct Window {
    var pct: Double
    var reset: Double

    init?(_ any: Any?) {
        guard let d = dict(any), let p = number(d["used_percentage"]), let r = number(d["resets_at"]) else { return nil }
        pct = p
        reset = r
    }

    init(pct: Double, reset: Double) {
        self.pct = pct
        self.reset = reset
    }

    var json: [String: Any] { ["used_percentage": pct, "resets_at": reset] }
}

/// Several sessions write concurrently, some with older data. Within one window usage only grows,
/// so the higher value wins; across different windows the later one wins.
func merge(_ new: Window?, _ old: Window?) -> Window? {
    let old = old.flatMap { $0.reset > now ? $0 : nil }
    guard let new else { return old }
    guard let old else { return new }
    if abs(new.reset - old.reset) < 300 {
        return Window(pct: max(new.pct, old.pct), reset: max(new.reset, old.reset))
    }
    return new.reset > old.reset ? new : old
}

// MARK: - Input

let input = FileHandle.standardInput.readDataToEndOfFile()
let wrappedCommand = (readJSON(configURL)["wrapped_command"] as? String).flatMap { $0.isEmpty ? nil : $0 }

guard let json = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] else {
    if let wrappedCommand { exit(runWrapped(wrappedCommand, input: input)) }
    print("Claude Code")
    exit(0)
}

try? fm.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

// MARK: - Limits

let oldLimits = readJSON(limitsURL)
var fiveHour = Window(oldLimits["five_hour"])
var sevenDay = Window(oldLimits["seven_day"])
var spend = Window(oldLimits["spend_limit"])

if let rateLimits = dict(json["rate_limits"]) {
    let oldFive = fiveHour, oldSeven = sevenDay
    fiveHour = merge(Window(rateLimits["five_hour"]), fiveHour)
    sevenDay = merge(Window(rateLimits["seven_day"]), sevenDay)
    spend = merge(Window(rateLimits["spend_limit"]), spend)

    var out: [String: Any] = ["updated_at": now]
    if let fiveHour { out["five_hour"] = fiveHour.json }
    if let sevenDay { out["seven_day"] = sevenDay.json }
    if let spend { out["spend_limit"] = spend.json }

    // History: one sample on change, or at least every 10 minutes
    let lastHistory = number(oldLimits["history_at"]) ?? 0
    let changed = fiveHour?.pct != oldFive?.pct || sevenDay?.pct != oldSeven?.pct
    if changed || now - lastHistory > 600 {
        var sample: [String: Any] = ["t": now]
        if let fiveHour { sample["h5"] = fiveHour.pct }
        if let sevenDay { sample["d7"] = sevenDay.pct }
        if let data = try? JSONSerialization.data(withJSONObject: sample, options: [.sortedKeys]) {
            appendLine(data, to: historyURL)
        }
        out["history_at"] = now
        cleanup()
    } else {
        out["history_at"] = lastHistory
    }
    writeJSON(out, to: limitsURL)
}

// MARK: - Session

let sessionId = json["session_id"] as? String
let model = dict(json["model"])
let cost = dict(json["cost"])
let context = dict(json["context_window"])
let cwd = (dict(json["workspace"])?["current_dir"] as? String) ?? (json["cwd"] as? String) ?? ""

if let sessionId, !sessionId.isEmpty, !sessionId.contains("/") {
    var session: [String: Any] = ["session_id": sessionId, "cwd": cwd, "updated_at": now]
    session["model_id"] = model?["id"]
    session["model_name"] = model?["display_name"]
    session["cost_usd"] = cost?["total_cost_usd"]
    session["lines_added"] = cost?["total_lines_added"]
    session["lines_removed"] = cost?["total_lines_removed"]
    session["context_pct"] = context?["used_percentage"]
    session["context_size"] = context?["context_window_size"]
    writeJSON(session.compactMapValues { $0 is NSNull ? nil : $0 }, to: sessionsDir.appendingPathComponent("\(sessionId).json"))
}

// MARK: - Output

if let wrappedCommand { exit(runWrapped(wrappedCommand, input: input)) }

let dim = "\u{1B}[2m", reset = "\u{1B}[0m", bold = "\u{1B}[1m"

func colored(_ pct: Double) -> String {
    let code = pct >= 85 ? "31" : pct >= 60 ? "33" : "32"
    return "\u{1B}[\(code)m\(Int(pct.rounded()))%\(reset)"
}

func gitBranch(from path: String) -> String? {
    var dir = URL(fileURLWithPath: path)
    for _ in 0..<12 {
        let git = dir.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: git.path, isDirectory: &isDir) {
            var headURL = git.appendingPathComponent("HEAD")
            if !isDir.boolValue, let text = try? String(contentsOf: git, encoding: .utf8),
               let range = text.range(of: "gitdir: ") {
                // Worktree: .git is a file pointing to the real git dir
                let target = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                headURL = URL(fileURLWithPath: target, relativeTo: dir).appendingPathComponent("HEAD")
            }
            guard let head = try? String(contentsOf: headURL, encoding: .utf8) else { return nil }
            let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("ref: refs/heads/") { return String(trimmed.dropFirst("ref: refs/heads/".count)) }
            return String(trimmed.prefix(7))
        }
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { break }
        dir = parent
    }
    return nil
}

func countdown(to epoch: Double) -> String {
    let secs = max(0, Int(epoch - now))
    let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
    if d > 0 { return "\(d)d\(h)h" }
    if h > 0 { return "\(h)h\(String(format: "%02d", m))m" }
    return "\(m)m"
}

var parts: [String] = []
parts.append("\(bold)\(model?["display_name"] as? String ?? "Claude")\(reset)")
var location = URL(fileURLWithPath: cwd).lastPathComponent
if let branch = gitBranch(from: cwd) { location += " \(dim)⎇\(reset) \(branch)" }
if !cwd.isEmpty { parts.append(location) }
if let ctx = number(context?["used_percentage"]) { parts.append("ctx \(colored(ctx))") }
if let fiveHour { parts.append("5h \(colored(fiveHour.pct)) \(dim)↻\(countdown(to: fiveHour.reset))\(reset)") }
if let sevenDay { parts.append("7d \(colored(sevenDay.pct))") }
if let spend { parts.append("spend \(colored(spend.pct))") }

print(parts.joined(separator: " \(dim)·\(reset) "))
