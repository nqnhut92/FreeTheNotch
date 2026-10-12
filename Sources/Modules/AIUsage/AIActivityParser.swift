// Adapted from CodeNotch (MIT): Sources/Sessions/CodexActivityMonitor.swift,
// ClaudeSessionRecord.swift and ClaudeTranscript.swift. See THIRD_PARTY_NOTICES.md.

import Foundation

/// Parses lifecycle records without retaining prompts, messages, or tool arguments.
enum AIActivityParser {
    struct Turn: Equatable, Sendable {
        let state: AIActivity.State
        let timestamp: Date?
    }

    static func codex(_ data: Data) -> Turn? {
        for line in data.split(separator: 10).reversed() {
            guard let record = object(Data(line)), record["type"] as? String == "event_msg",
                let payload = record["payload"] as? [String: Any]
            else { continue }
            let state: AIActivity.State
            switch payload["type"] as? String {
            case "task_started": state = .working
            case "task_complete": state = .completed
            case "turn_aborted": state = .stopped
            default: continue
            }
            return Turn(state: state, timestamp: (record["timestamp"] as? String).flatMap(AIUsageQuotaParser.date))
        }
        return nil
    }

    static func claude(_ data: Data) -> Turn? {
        for line in data.split(separator: 10).reversed() {
            guard let record = object(Data(line)), record["isSidechain"] as? Bool != true,
                let message = record["message"] as? [String: Any]
            else { continue }
            let state: AIActivity.State
            switch record["type"] as? String {
            case "user":
                let prefix = "[Request interrupted by user"
                let text = message["content"] as? String
                let blocks = message["content"] as? [[String: Any]]
                if text?.hasPrefix(prefix) == true
                    || blocks?.contains(where: { ($0["text"] as? String)?.hasPrefix(prefix) == true }) == true
                {
                    state = .stopped
                } else {
                    state = .working
                }
            case "assistant":
                switch message["stop_reason"] as? String {
                case "tool_use": state = .working
                case "end_turn", "stop_sequence", "max_tokens": state = .completed
                default: continue
                }
            default: continue
            }
            return Turn(state: state, timestamp: (record["timestamp"] as? String).flatMap(AIUsageQuotaParser.date))
        }
        return nil
    }

    static func claudeRegistry(_ data: Data, fallback: Date) -> (pid: Int32, started: Date?, activity: AIActivity)? {
        guard let record = object(data), let number = record["pid"] as? NSNumber,
            number.int64Value > 0, number.int64Value <= Int32.max
        else { return nil }
        let state: AIActivity.State
        switch (record["tempo"] as? String, record["status"] as? String) {
        case ("blocked", _), (_, "waiting"): state = .waiting
        case ("active", _), (_, "busy"): state = .working
        case ("idle", _), (_, "idle"): state = .idle
        default: return nil
        }
        let changed = (record["statusUpdatedAt"] as? Double) ?? (record["updatedAt"] as? Double)
        let started = (record["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        let id = (record["sessionId"] as? String) ?? number.stringValue
        return (
            number.int32Value, started,
            AIActivity(
                id: "claude." + id, provider: .claude, state: state,
                changedAt: changed.map { Date(timeIntervalSince1970: $0 / 1000) } ?? started ?? fallback)
        )
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
