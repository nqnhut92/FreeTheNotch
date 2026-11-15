// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/CodexUsageProvider.swift,
// ClaudeUsageProvider.swift and Quota/{Codex,Claude}QuotaClient.swift.

import Foundation
import os

/// Fetches account quota and aggregates local logs independently, so either can survive failure of the other.
actor AIUsageService {
    typealias CredentialLoader = @Sendable (AIUsageAccount, Bool) async throws -> AIUsageCredentials
    private let session: URLSession
    private let credentials: CredentialLoader
    private let credentialSink: ClaudeCredentialSink
    private let logRoots: [AIUsageProvider: URL]
    private var renewal: Task<AIUsageCredentials, Error>?
    private var pricing = AIUsagePricing()
    private var priceTask: Task<AIUsagePricing?, Never>?
    private var pricesUpdatedAt = Date.distantPast
    private static let priceRefreshInterval: TimeInterval = 24 * 3600
    private static let pricesURL = URL(string: "https://openrouter.ai/api/v1/models")!
    private static let codexURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let claudeURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    init(
        session: URLSession = URLSession(configuration: .ephemeral), logRoots: [AIUsageProvider: URL],
        credentialSink: ClaudeCredentialSink = .none, credentials: @escaping CredentialLoader
    ) {
        self.session = session
        self.logRoots = logRoots
        self.credentialSink = credentialSink
        self.credentials = credentials
    }

    func snapshot(_ account: AIUsageAccount, allowPrompt: Bool, now: Date, calendar: Calendar) async
        -> AIUsageSnapshot
    {
        await refreshPricing(now: now)
        let provider = account.provider
        let logRoot = logRoots[provider]
        var result = AIUsageSnapshot()
        do {
            if let root = logRoot, FileManager.default.fileExists(atPath: root.path) {
                let files =
                    FileManager.default.enumerator(
                        at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                        options: [.skipsHiddenFiles])?
                    .compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" } ?? []
                result = try AIUsageLogParser.aggregate(files: files, now: now, calendar: calendar, pricing: pricing)
            }
            if !result.hasLocalLogs { result.logsMessage = "No local usage logs" }
        } catch { result.logsMessage = "Could not read local usage logs" }
        do {
            var login = try await credentials(account, allowPrompt)
            if let expiration = login.expiresAt, expiration <= now {
                login = try await renewedLogin(login, account: account, now: now)
            }
            var (data, http) = try await quotaResponse(provider, login)
            if http.statusCode == 401, provider == .claude {
                // Claude Code may have rotated the pair since it was read; read it again and retry once.
                let reread = try await credentials(account, false)
                if reread.accessToken != login.accessToken {
                    login = reread
                    (data, http) = try await quotaResponse(provider, login)
                }
            }
            result.identity = login.identity
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
            if provider == .claude && (error == .signIn || error == .expired) {
                result.quotaMessage = AIUsageError.claudeSignInInstruction
            } else {
                result.quotaMessage = error.localizedDescription
            }
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

    private func quotaResponse(
        _ provider: AIUsageProvider, _ login: AIUsageCredentials
    ) async throws -> (Data, HTTPURLResponse) {
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
        return (data, http)
    }

    /// One refresh at a time: a second caller waits for the first, since both would spend the same refresh token.
    private func renewedLogin(
        _ login: AIUsageCredentials, account: AIUsageAccount, now: Date
    ) async throws -> AIUsageCredentials {
        if let renewal { return try await renewal.value }
        let task = Task { try await self.performRenewal(login, account: account, now: now) }
        renewal = task
        defer { renewal = nil }
        return try await task.value
    }

    private func performRenewal(
        _ login: AIUsageCredentials, account: AIUsageAccount, now: Date
    ) async throws -> AIUsageCredentials {
        // Claude Code may already have rotated the pair; read it again before spending the refresh token.
        var current = login
        if let reread = try? await credentials(account, false) {
            if reread.expiresAt.map({ $0 > now }) ?? true { return reread }
            current = reread
        }
        guard account.provider == .claude, current.oauth != nil, credentialSink.canStore(current) else {
            throw AIUsageError.expired
        }
        guard let refreshed = await ClaudeTokenRefresher(session: session).refreshed(current, now: now) else {
            throw AIUsageError.expired
        }
        if !(await credentialSink.store(refreshed)) {
            Logger.modules.error("[FreeTheNotch] AI usage: refreshed Claude login could not be stored")
        }
        return refreshed
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
