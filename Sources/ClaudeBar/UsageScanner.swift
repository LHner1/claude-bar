import Foundation

/// Reads the transcripts under ~/.claude/projects incrementally and sums up token usage
/// and its API list price per hour and model. The first run reads everything, later runs only newly appended lines.
actor UsageScanner {
    private struct FileState {
        var offset: UInt64
    }

    private struct Entry {
        var hour: Date
        var model: String
        var usage: RequestUsage
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

        let request = requestUsage(usage)

        let hour = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
        let day = Calendar.current.startOfDay(for: date)
        let key = "\(message["id"] as? String ?? UUID().uuidString):\(obj["requestId"] as? String ?? "")"

        if let previous = seen[key] {
            // Same message again: only add the increase (e.g. the final output_tokens value)
            let merged = previous.usage.merged(with: request)
            guard merged != previous.usage else { return }
            let delta = TokenCounts(model: previous.model, usage: merged)
                - TokenCounts(model: previous.model, usage: previous.usage)
            snapshot.hourly[previous.hour, default: [:]][previous.model, default: TokenCounts()] += delta
            seen[key]?.usage = merged
            return
        }

        seen[key] = Entry(hour: hour, model: model, usage: request)
        snapshot.hourly[hour, default: [:]][model, default: TokenCounts()] += TokenCounts(model: model, usage: request)
        if let sessionId = obj["sessionId"] as? String {
            snapshot.sessionsByDay[day, default: []].insert(sessionId)
        }
    }

    private func requestUsage(_ usage: [String: Any]) -> RequestUsage {
        func int(_ dict: [String: Any]?, _ key: String) -> Int { (dict?[key] as? NSNumber)?.intValue ?? 0 }
        // Cache writes cost more with a 1-hour lifetime. Without the breakdown they count as 5-minute writes.
        let lifetimes = usage["cache_creation"] as? [String: Any]
        let write1h = int(lifetimes, "ephemeral_1h_input_tokens")
        let write5m = max(int(lifetimes, "ephemeral_5m_input_tokens"),
                          int(usage, "cache_creation_input_tokens") - write1h)
        return RequestUsage(input: int(usage, "input_tokens"), output: int(usage, "output_tokens"),
                            cacheWrite5m: write5m, cacheWrite1h: write1h,
                            cacheRead: int(usage, "cache_read_input_tokens"),
                            webSearches: int(usage["server_tool_use"] as? [String: Any], "web_search_requests"),
                            fast: usage["speed"] as? String == "fast",
                            usOnly: usage["inference_geo"] as? String == "us")
    }
}
