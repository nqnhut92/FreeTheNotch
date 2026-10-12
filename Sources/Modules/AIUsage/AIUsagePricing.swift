// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/ModelPricing.swift
// and ModelPricingManager.swift (cache accounting and model ID normalization).
// Public price lookup also mirrors CodeNotch (MIT): Sources/Costs/Pricing.swift.

import Foundation

/// Public per-token prices from OpenRouter's models endpoint.
struct AIUsagePricing: Sendable {
    struct Rates: Sendable {
        let input: Double
        let output: Double
        let cacheRead: Double?
        let cacheWrite: Double?
    }
    private let rates: [String: Rates]

    init(rates: [String: Rates] = [:]) { self.rates = rates }

    init(data: Data) throws {
        struct Response: Decodable {
            let data: [Model]
            struct Model: Decodable {
                let id: String
                let pricing: Pricing
            }
            struct Pricing: Decodable {
                let prompt: String
                let completion: String
                let inputCacheRead: String?
                let inputCacheWrite: String?
            }
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)
        var rates: [String: Rates] = [:]
        for model in response.data {
            guard !model.id.contains(":"), model.id.hasPrefix("openai/") || model.id.hasPrefix("anthropic/") else {
                continue
            }
            guard let input = Double(model.pricing.prompt), input.isFinite, input >= 0,
                let output = Double(model.pricing.completion), output.isFinite, output >= 0
            else { continue }
            func rate(_ raw: String?) -> Double? {
                guard let raw, let value = Double(raw), value.isFinite, value >= 0 else { return nil }
                return value
            }
            rates[Self.key(model.id)] = Rates(
                input: input, output: output, cacheRead: rate(model.pricing.inputCacheRead),
                cacheWrite: rate(model.pricing.inputCacheWrite))
        }
        self.rates = rates
    }

    func cost(_ record: AIUsageLogParser.Record) -> Double? {
        guard let rate = rates[Self.key(record.model)] else { return nil }
        // A missing cache rate keeps a conservative prompt-rate estimate.
        return Double(record.uncachedInputTokens) * rate.input + Double(record.outputTokens) * rate.output
            + Double(record.cacheReadTokens) * (rate.cacheRead ?? rate.input)
            + Double(record.cacheWriteTokens) * (rate.cacheWrite ?? rate.input)
    }

    private static func key(_ raw: String) -> String {
        let name = String(raw.lowercased().split(separator: "/").last ?? Substring(raw))
            .replacingOccurrences(of: #"-\d{8}$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: ".", with: "-")
        let words = name.split(separator: "-").map(String.init)
        let families = ["opus", "sonnet", "haiku", "fable"]
        guard words.first == "claude", let family = words.first(where: { families.contains($0) }) else {
            return name
        }
        return (["claude", family] + words.dropFirst().filter { $0 != family }).joined(separator: "-")
    }
}
