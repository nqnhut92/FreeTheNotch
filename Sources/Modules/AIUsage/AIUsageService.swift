// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/CodexUsageProvider.swift,
// ClaudeUsageProvider.swift and Quota/{Codex,Claude}QuotaClient.swift.

import Foundation
import os

/// Fetches account quota and aggregates local logs independently, so either can survive failure of the other.
actor AIUsageService {
    typealias CredentialLoader = @Sendable (AIUsageProvider, Bool) async throws -> AIUsageCredentials
    private let session: URLSession
    private let credentials: CredentialLoader
    private let desktopCache: ClaudeDesktopUsageCache?
    private let logRoots: [AIUsageProvider: URL]
    private var lastDesktopReading: AIUsageSnapshot?
    private var pricing = AIUsagePricing()
    private var priceTask: Task<AIUsagePricing?, Never>?
    private var pricesUpdatedAt = Date.distantPast
    private static let priceRefreshInterval: TimeInterval = 24 * 3600
    private static let pricesURL = URL(string: "https://openrouter.ai/api/v1/models")!
    private static let codexURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let claudeURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    init(
        session: URLSession = URLSession(configuration: .ephemeral), logRoots: [AIUsageProvider: URL],
        desktopCache: ClaudeDesktopUsageCache? = nil, credentials: @escaping CredentialLoader
    ) {
        self.session = session
        self.logRoots = logRoots
        self.credentials = credentials
        self.desktopCache = desktopCache
    }

    func snapshot(_ provider: AIUsageProvider, allowPrompt: Bool, now: Date, calendar: Calendar) async
        -> AIUsageSnapshot
    {
        await refreshPricing(now: now)
        var result = AIUsageSnapshot()
        do {
            if let root = logRoots[provider], FileManager.default.fileExists(atPath: root.path) {
                let files =
                    FileManager.default.enumerator(
                        at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                        options: [.skipsHiddenFiles])?
                    .compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" } ?? []
                result = try AIUsageLogParser.aggregate(files: files, now: now, calendar: calendar, pricing: pricing)
            }
            if !result.hasLocalLogs { result.logsMessage = "No local usage logs" }
        } catch { result.logsMessage = "Could not read local usage logs" }
        if provider == .claude, let cached = desktopCache?.read(now: now) {
            if lastDesktopReading == nil
                || (cached.quotaCapturedAt ?? .distantPast) > (lastDesktopReading?.quotaCapturedAt ?? .distantPast)
            {
                lastDesktopReading = cached
            }
        }
        if provider == .claude, let cached = lastDesktopReading {
            result.sessionLimit = cached.sessionLimit
            result.weekLimit = cached.weekLimit
            result.identity = cached.identity
            result.quotaSource = cached.quotaSource
            result.quotaCapturedAt = cached.quotaCapturedAt
            result.updatedAt = now
            return result
        }
        do {
            let login = try await credentials(provider, allowPrompt)
            result.identity = login.identity
            if let expiration = login.expiresAt, expiration <= now { throw AIUsageError.expired }
            var request = URLRequest(url: provider == .codex ? Self.codexURL : Self.claudeURL)
            request.timeoutInterval = 20
            request.setValue("Bearer \(login.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(
                provider == .claude ? "claude-code/2.1.69" : "FreeTheNotch", forHTTPHeaderField: "User-Agent")
            if provider == .codex, let accountID = login.accountID {
                request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
            }
            if provider == .claude {
                request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIUsageError.invalidResponse }
            if !(200..<300).contains(http.statusCode) {
                Logger.modules.error(
                    "[FreeTheNotch] AI usage: quota HTTP status \(http.statusCode) for \(provider.rawValue, privacy: .public)"
                )
            }
            if http.statusCode == 401 { throw AIUsageError.expired }
            if http.statusCode == 403 { throw AIUsageError.unavailable }
            guard (200..<300).contains(http.statusCode) else { throw AIUsageError.network }
            let quota = try AIUsageQuotaParser.parse(data, provider: provider, now: now)
            result.sessionLimit = quota.sessionLimit
            result.weekLimit = quota.weekLimit
            result.quotaMessage = quota.quotaMessage
        } catch let error as AIUsageError {
            result.quotaMessage =
                provider == .claude && (error == .signIn || error == .expired)
                ? "Open Claude Desktop → Settings → Usage, then refresh. Claude Code can also supply a login."
                : error.localizedDescription
            switch error {
            case .signIn, .keychainAccess, .expired: result.requiresConnection = true
            default: break
            }
        } catch is DecodingError {
            result.quotaMessage = AIUsageError.invalidResponse.localizedDescription
        } catch { result.quotaMessage = AIUsageError.network.localizedDescription }
        result.updatedAt = now
        return result
    }

    private func refreshPricing(now: Date) async {
        if let priceTask {
            if let fetched = await priceTask.value { pricing = fetched }
            return
        }
        guard now.timeIntervalSince(pricesUpdatedAt) >= Self.priceRefreshInterval else { return }
        pricesUpdatedAt = now
        let task = Task { [session] () -> AIUsagePricing? in
            do {
                var request = URLRequest(url: Self.pricesURL)
                request.timeoutInterval = 15
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
                return try AIUsagePricing(data: data)
            } catch { return nil }
        }
        priceTask = task
        if let fetched = await task.value { pricing = fetched }
        priceTask = nil
    }
}
