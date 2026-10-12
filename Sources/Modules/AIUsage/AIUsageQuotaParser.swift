// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/UsageProvider.swift,
// Quota/CodexQuotaClient.swift and Quota/ClaudeQuotaClient.swift.

import Foundation

/// Decodes the two providers without making network requests or reading credentials.
enum AIUsageQuotaParser {
    static func parse(_ data: Data, provider: AIUsageProvider, now: Date) throws -> AIUsageSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var result = AIUsageSnapshot()
        switch provider {
        case .codex:
            let payload = try decoder.decode(CodexResponse.self, from: data)
            result.sessionLimit = payload.rateLimit?.primaryWindow?.limit(now: now)
            result.weekLimit = payload.rateLimit?.secondaryWindow?.limit(now: now)
        case .claude:
            let payload = try decoder.decode(ClaudeResponse.self, from: data)
            result.sessionLimit = payload.fiveHour?.limit
            result.weekLimit = payload.sevenDay?.limit
        }
        if result.sessionLimit == nil && result.weekLimit == nil {
            result.quotaMessage = "Quota unavailable"
        }
        return result
    }

    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private struct CodexResponse: Decodable {
        let rateLimit: RateLimit?
        struct RateLimit: Decodable {
            let primaryWindow: Window?
            let secondaryWindow: Window?
        }
        struct Window: Decodable {
            let usedPercent: Double
            let resetAt: Double?
            let resetAfterSeconds: Double?
            func limit(now: Date) -> AIUsageLimit {
                AIUsageLimit(
                    usedPercent: usedPercent,
                    resetsAt: resetAt.map { Date(timeIntervalSince1970: $0) }
                        ?? resetAfterSeconds.map { now.addingTimeInterval($0) })
            }
        }
    }

    private struct ClaudeResponse: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
        struct Window: Decodable {
            let utilization: Double
            let resetsAt: ResetDate?
            var limit: AIUsageLimit { AIUsageLimit(usedPercent: utilization, resetsAt: resetsAt?.date) }
        }
    }

    private enum ResetDate: Decodable {
        case iso(String)
        case milliseconds(Double)
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let string = try? value.decode(String.self) {
                self = .iso(string)
            } else {
                self = .milliseconds(try value.decode(Double.self))
            }
        }
        var date: Date? {
            switch self {
            case .iso(let value): return AIUsageQuotaParser.date(value)
            case .milliseconds(let value): return Date(timeIntervalSince1970: value / 1000)
            }
        }
    }
}
