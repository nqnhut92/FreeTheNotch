// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/JSONLUsageParser.swift.
// Token counts, cache accounting and bounded streaming follow that parser.
// Streaming maxima follow CodeNotch (MIT): Sources/Costs/CostIndexer.swift and CostStore.swift.

import Foundation

/// Parses local Codex and Claude Code JSONL logs without retaining conversation text.
enum AIUsageLogParser {
    struct Record: Sendable {
        let timestamp: Date
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let cacheWriteTokens: Int
        let deduplicationKey: String?
        var uncachedInputTokens: Int { max(0, inputTokens - cacheReadTokens - cacheWriteTokens) }
    }

    struct Context {
        var model = "unknown"
        var sessionID: String?
        var lastTotal: Int?
        private let fractionalDate: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
        private let plainDate = ISO8601DateFormatter()

        func date(_ value: String) -> Date? {
            fractionalDate.date(from: value) ?? plainDate.date(from: value)
        }
    }

    static func parseLine(_ line: Data, context: inout Context) -> Record? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
        let payload = object["payload"] as? [String: Any]
        if object["type"] as? String == "session_meta" {
            context.sessionID = payload?["id"] as? String
            return nil
        }
        if object["type"] as? String == "turn_context" || payload?["type"] as? String == "turn_context",
            let model = payload?["model"] as? String
        {
            context.model = model
            return nil
        }
        guard let rawDate = object["timestamp"] as? String, let date = context.date(rawDate) else {
            return nil
        }
        func count(_ usage: [String: Any], _ key: String) -> Int { max(0, usage[key] as? Int ?? 0) }
        if object["type"] as? String == "event_msg", payload?["type"] as? String == "token_count",
            let info = payload?["info"] as? [String: Any], let usage = info["last_token_usage"] as? [String: Any]
        {
            let total = (info["total_token_usage"] as? [String: Any])?["total_tokens"] as? Int
            if let total, context.lastTotal == total { return nil }
            context.lastTotal = total
            let input = count(usage, "input_tokens")
            let cacheWrite = count(usage, "cache_write_input_tokens")
            let output = count(usage, "output_tokens")
            guard input + output + cacheWrite > 0 else { return nil }
            return Record(
                timestamp: date, model: context.model, inputTokens: input + cacheWrite, outputTokens: output,
                cacheReadTokens: min(input, count(usage, "cached_input_tokens")), cacheWriteTokens: cacheWrite,
                deduplicationKey: context.sessionID.flatMap { id in total.map { "codex:\(id):\($0)" } })
        }
        let message = object["message"] as? [String: Any]
        guard let usage = message?["usage"] as? [String: Any] ?? object["usage"] as? [String: Any] else { return nil }
        let write = count(usage, "cache_creation_input_tokens")
        let read = count(usage, "cache_read_input_tokens")
        let input = count(usage, "input_tokens") + write + read
        let output = count(usage, "output_tokens")
        guard input + output > 0 else { return nil }
        let messageID = message?["id"] as? String
        let requestID = object["requestId"] as? String ?? object["request_id"] as? String
        let key = requestID.map { "claude:request:\($0)" } ?? messageID.map { "claude:message:\($0)" }
        return Record(
            timestamp: date, model: message?["model"] as? String ?? object["model"] as? String ?? "unknown",
            inputTokens: input, outputTokens: output, cacheReadTokens: read, cacheWriteTokens: write,
            deduplicationKey: key)
    }

    static func aggregate(
        files: [URL], now: Date, calendar: Calendar, pricing: AIUsagePricing
    ) throws -> AIUsageSnapshot {
        var result = AIUsageSnapshot()
        var records: [String: Record] = [:]
        var unkeyed: [Record] = []
        let weekStart = now.addingTimeInterval(-7 * 86400)
        result.hasLocalLogs = !files.isEmpty
        for file in files {
            let modified = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, modified < weekStart { continue }
            var context = Context()
            try stream(file) { data in
                guard let record = parseLine(data, context: &context), record.timestamp <= now,
                    record.timestamp >= weekStart
                else { return }
                guard let key = record.deduplicationKey else {
                    unkeyed.append(record)
                    return
                }
                if let previous = records[key] {
                    records[key] = Record(
                        timestamp: max(previous.timestamp, record.timestamp), model: record.model,
                        inputTokens: max(previous.inputTokens, record.inputTokens),
                        outputTokens: max(previous.outputTokens, record.outputTokens),
                        cacheReadTokens: max(previous.cacheReadTokens, record.cacheReadTokens),
                        cacheWriteTokens: max(previous.cacheWriteTokens, record.cacheWriteTokens),
                        deduplicationKey: key)
                } else {
                    records[key] = record
                }
            }
        }
        for record in Array(records.values) + unkeyed {
            let cost = pricing.cost(record)
            func add(_ totals: inout AIUsageTotals) {
                totals.inputTokens += record.inputTokens
                totals.outputTokens += record.outputTokens
                if let cost { totals.estimatedCostUSD += cost } else { totals.hasUnpricedModel = true }
            }
            add(&result.week)
            if calendar.isDate(record.timestamp, inSameDayAs: now) { add(&result.today) }
        }
        return result
    }

    /// Caps individual records at 1 MB; reads 64 KB at a time rather than entire session files.
    private static func stream(_ file: URL, process: (Data) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let maximumRecordBytes = 1024 * 1024
        var buffer = Data()
        var discarding = false
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            buffer.append(chunk)
            while let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<end])
                buffer.removeSubrange(...end)
                if !discarding && line.count <= maximumRecordBytes { process(line) }
                discarding = false
            }
            if buffer.count > maximumRecordBytes {
                buffer.removeAll(keepingCapacity: true)
                discarding = true
            }
        }
        if !discarding && !buffer.isEmpty { process(buffer) }
    }
}
