import Foundation

/// Reads the transcripts under ~/.claude/projects incrementally and sums up token usage
/// per hour and model. The first run reads everything, later runs only newly appended lines.
actor UsageScanner {
    private struct FileState {
        var offset: UInt64
    }

    private struct Entry {
        var hour: Date
        var model: String
        var counts: TokenCounts
    }

    private var files: [String: FileState] = [:]
    /// Claude Code often writes one message across several lines with the same ID – count it once.
    private var seen: [String: Entry] = [:]
    private var snapshot = UsageSnapshot()

    private let usageMarker = Data("\"usage\"".utf8)
    private let assistantMarker = Data("\"assistant\"".utf8)
    private let newline = UInt8(ascii: "\n")

    private let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let iso = ISO8601DateFormatter()

    func scan() -> UsageSnapshot {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: Paths.projects, includingPropertiesForKeys: [.fileSizeKey],
                                             options: [.skipsHiddenFiles]) else { return snapshot }
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let size = UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            var state = files[url.path] ?? FileState(offset: 0)
            if size < state.offset { state.offset = 0 }  // file was rewritten – `seen` filters duplicates
            guard size > state.offset else { continue }
            state.offset = read(url, from: state.offset)
            files[url.path] = state
        }
        snapshot.scannedAt = Date()
        return snapshot
    }

    /// Reads from `offset` up to the last complete line and returns the new offset.
    private func read(_ url: URL, from offset: UInt64) -> UInt64 {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return offset }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd(), !data.isEmpty,
              let lastNewline = data.lastIndex(of: newline) else { return offset }

        let complete = data[data.startIndex...lastNewline]
        for line in complete.split(separator: newline, omittingEmptySubsequences: true) {
            guard line.range(of: usageMarker) != nil, line.range(of: assistantMarker) != nil else { continue }
            process(Data(line))
        }
        return offset + UInt64(complete.count)
    }

    private func process(_ line: Data) {
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String, model != "<synthetic>",
              let timestamp = obj["timestamp"] as? String,
              let date = isoFractional.date(from: timestamp) ?? iso.date(from: timestamp)
        else { return }

        func int(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        let counts = TokenCounts(input: int("input_tokens"), output: int("output_tokens"),
                                 cacheWrite: int("cache_creation_input_tokens"),
                                 cacheRead: int("cache_read_input_tokens"), messages: 1)

        let hour = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
        let day = Calendar.current.startOfDay(for: date)
        let key = "\(message["id"] as? String ?? UUID().uuidString):\(obj["requestId"] as? String ?? "")"

        if let previous = seen[key] {
            // Same message again: only add the increase (e.g. the final output_tokens value)
            let delta = TokenCounts(input: max(0, counts.input - previous.counts.input),
                                    output: max(0, counts.output - previous.counts.output),
                                    cacheWrite: max(0, counts.cacheWrite - previous.counts.cacheWrite),
                                    cacheRead: max(0, counts.cacheRead - previous.counts.cacheRead))
            guard delta.total > 0 else { return }
            snapshot.hourly[previous.hour, default: [:]][previous.model, default: TokenCounts()] += delta
            seen[key]?.counts += delta
            return
        }

        seen[key] = Entry(hour: hour, model: model, counts: counts)
        snapshot.hourly[hour, default: [:]][model, default: TokenCounts()] += counts
        if let sessionId = obj["sessionId"] as? String {
            snapshot.sessionsByDay[day, default: []].insert(sessionId)
        }
    }
}
