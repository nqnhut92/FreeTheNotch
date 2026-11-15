import Foundation
import Testing

struct AIUsageTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func codexQuotaKeepsTheResetAndTreatsUsageAsUsedPercent() throws {
        let data = Data(
            #"{"rate_limit":{"primary_window":{"used_percent":25,"reset_at":1700003600},"secondary_window":{"used_percent":80,"reset_after_seconds":7200}}}"#
                .utf8)
        let snapshot = try AIUsageQuotaParser.parse(data, provider: .codex, now: now)
        #expect(snapshot.sessionLimit?.fraction == 0.25)
        #expect(snapshot.sessionLimit?.resetsAt == now.addingTimeInterval(3600))
        #expect(snapshot.weekLimit?.resetsAt == now.addingTimeInterval(7200))
    }

    @Test(arguments: ["2023-11-14T22:13:20.123Z", "2023-11-14T22:13:20Z"])
    func claudeAcceptsBothISOResetFormats(_ date: String) throws {
        let data = Data("{\"five_hour\":{\"utilization\":40,\"resets_at\":\"\(date)\"},\"seven_day\":null}".utf8)
        let snapshot = try AIUsageQuotaParser.parse(data, provider: .claude, now: now)
        #expect(snapshot.sessionLimit?.fraction == 0.4)
        let reset = try #require(snapshot.sessionLimit?.resetsAt)
        #expect(abs(reset.timeIntervalSince(now)) < 0.124)
        #expect(snapshot.weekLimit == nil)
    }

    @Test func missingQuotaIsUnavailableRatherThanZero() throws {
        let snapshot = try AIUsageQuotaParser.parse(Data("{}".utf8), provider: .codex, now: now)
        #expect(snapshot.sessionLimit == nil)
        #expect(snapshot.quotaMessage != nil)
    }

    @Test(arguments: [(-5.0, 0.0), (120.0, 1.0), (38.0, 0.38)])
    func quotaFractionsStayInsideTheGauge(_ used: Double, expected: Double) {
        #expect(AIUsageLimit(usedPercent: used, resetsAt: nil).fraction == expected)
    }

    @Test func codexCacheHitsAreAlreadyInsideInputAndRepeatedTotalsAreIgnored() throws {
        var context = AIUsageLogParser.Context()
        _ = AIUsageLogParser.parseLine(
            Data(#"{"type":"turn_context","payload":{"model":"gpt-test"}}"#.utf8), context: &context)
        let data = Data(
            #"{"timestamp":"2023-11-14T22:13:20Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":20},"total_token_usage":{"total_tokens":120}}}}"#
                .utf8)
        let record = try #require(AIUsageLogParser.parseLine(data, context: &context))
        #expect(record.model == "gpt-test")
        #expect(record.inputTokens == 100)
        #expect(record.uncachedInputTokens == 40)
        #expect(record.outputTokens == 20)
        #expect(AIUsageLogParser.parseLine(data, context: &context) == nil)
    }

    @Test func claudeCachesAreSeparateAndDatesFollowTheInjectedCalendar() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("test.jsonl")
        // 22:13 UTC is 05:13 on the next day in Vietnam. This record belongs to Today.
        let line =
            #"{"timestamp":"2023-11-14T22:13:20Z","requestId":"request","message":{"id":"message","model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":40,"cache_read_input_tokens":60,"cache_creation_input_tokens":10,"output_tokens":20}}}"#
        // Copied messages in overlapping logs must count once, even without a final newline.
        try Data((line + "\n" + line).utf8).write(to: file)
        let price = Data(
            #"{"data":[{"id":"anthropic/claude-sonnet-4.5","pricing":{"prompt":"0.000003","completion":"0.000015","input_cache_read":"0.0000003","input_cache_write":"0.00000375"}}]}"#
                .utf8)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600) ?? .gmt
        let snapshot = try AIUsageLogParser.aggregate(
            files: [file], now: now.addingTimeInterval(3600), calendar: calendar, pricing: AIUsagePricing(data: price))
        #expect(snapshot.today.inputTokens == 110)
        #expect(snapshot.today.outputTokens == 20)
        // 40 × 3e-6 + 60 × 0.3e-6 + 10 × 3.75e-6 + 20 × 15e-6 = 0.0004755.
        #expect(abs(snapshot.today.estimatedCostUSD - 0.0004755) < 1e-12)
        #expect(!snapshot.today.hasUnpricedModel)
        #expect(snapshot.week == snapshot.today)
    }

    @Test func rollingWeekExcludesOldAndFutureRecordsAndUsesTheInjectedDay() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("windows.jsonl")
        let reference = now.addingTimeInterval(3 * 3600)  // Nov 15, 01:13 UTC.
        let dates = [
            reference.addingTimeInterval(-7 * 86400 - 1),
            reference.addingTimeInterval(-7 * 86400), now, reference.addingTimeInterval(1),
        ]
        let lines = dates.map { date in
            "{\"timestamp\":\"\(date.formatted(.iso8601))\",\"usage\":{\"input_tokens\":10,\"output_tokens\":20},\"model\":\"unknown\"}"
        }
        try Data(lines.joined(separator: "\n").utf8).write(to: file)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let snapshot = try AIUsageLogParser.aggregate(
            files: [file], now: reference, calendar: calendar, pricing: AIUsagePricing())
        // Exactly seven days ago and yesterday UTC remain; old and future records do not.
        #expect(snapshot.week.totalTokens == 60)
        #expect(snapshot.today.totalTokens == 0)
    }

    @Test func oversizedLinesAreSkippedWithoutLosingTheFollowingRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("oversized.jsonl")
        let valid = #"{"timestamp":"2023-11-14T22:13:20Z","usage":{"input_tokens":2,"output_tokens":3}}"#
        try Data((String(repeating: "x", count: 1024 * 1024 + 10) + "\n" + valid).utf8).write(to: file)
        let snapshot = try AIUsageLogParser.aggregate(
            files: [file], now: now, calendar: .current, pricing: AIUsagePricing())
        #expect(snapshot.today.totalTokens == 5)
    }

    @Test func streamedClaudeRequestsKeepTheLargestOutputEvenAcrossFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.jsonl")
        let second = directory.appendingPathComponent("second.jsonl")
        let partial =
            #"{"timestamp":"2023-11-14T22:13:20Z","requestId":"same","message":{"id":"one","model":"test","usage":{"input_tokens":10,"output_tokens":3}}}"#
        let final =
            #"{"timestamp":"2023-11-14T22:13:21Z","requestId":"same","message":{"id":"two","model":"test","usage":{"input_tokens":10,"output_tokens":20}}}"#
        try Data(partial.utf8).write(to: first)
        try Data(final.utf8).write(to: second)
        for files in [[first, second], [second, first]] {
            let snapshot = try AIUsageLogParser.aggregate(
                files: files, now: now.addingTimeInterval(60), calendar: .current, pricing: AIUsagePricing())
            #expect(snapshot.today.inputTokens == 10)
            #expect(snapshot.today.outputTokens == 20)
            #expect(snapshot.today.hasUnpricedModel)
        }
    }

    @Test(arguments: AIUsageProvider.allCases)
    func quotaRequestsUseOnlyTheirOwnProviderCredentials(_ provider: AIUsageProvider) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIUsageFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = AIUsageService(session: session, logRoots: [:]) { _, _ in
            AIUsageCredentials(accessToken: "fixture", accountID: "test-account", expiresAt: nil)
        }
        let snapshot = await service.snapshot(
            AIUsageAccount(provider: provider), allowPrompt: false, now: now, calendar: .current)
        #expect(snapshot.sessionLimit?.usedPercent == 25)
        #expect(snapshot.quotaMessage == nil)
        #expect(!snapshot.hasLocalLogs)
    }

    @Test func expiredCredentialsDoNotRequestQuotaAndDoNotSuppressLocalTotals() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(
            #"{"timestamp":"2023-11-14T22:13:20Z","model":"unknown","usage":{"input_tokens":10,"output_tokens":20}}"#
                .utf8
        )
        .write(to: directory.appendingPathComponent("usage.jsonl"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIUsageFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let expired = now.addingTimeInterval(-1)
        let service = AIUsageService(session: session, logRoots: [.claude: directory]) { _, _ in
            AIUsageCredentials(accessToken: "must-not-be-sent", accountID: nil, expiresAt: expired)
        }
        let snapshot = await service.snapshot(
            AIUsageAccount(provider: .claude), allowPrompt: false, now: now, calendar: .current)
        #expect(snapshot.today.totalTokens == 30)
        #expect(snapshot.requiresConnection)
        #expect(snapshot.sessionLimit == nil)
    }

    @Test func unknownModelsHaveTokensButNoInventedPrice() throws {
        var context = AIUsageLogParser.Context()
        let data = Data(
            #"{"timestamp":"2023-11-14T22:13:20Z","usage":{"input_tokens":5,"output_tokens":7},"model":"unknown"}"#.utf8
        )
        let record = try #require(AIUsageLogParser.parseLine(data, context: &context))
        #expect(record.inputTokens + record.outputTokens == 12)
        #expect(AIUsagePricing().cost(record) == nil)
    }

    @Test func malformedAndConversationRecordsAreIgnored() {
        var context = AIUsageLogParser.Context()
        #expect(AIUsageLogParser.parseLine(Data("broken".utf8), context: &context) == nil)
        #expect(
            AIUsageLogParser.parseLine(
                Data(#"{"type":"response_item","payload":{"text":"private"}}"#.utf8), context: &context) == nil)
    }

    @Test func accountLabelsAreDecodedWithoutAuthenticatingClaims() {
        let payload = Data(#"{"email":"test@example.com","name":"Test"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(
                of: "/", with: "_")
        #expect(
            AIUsageCredentials.codexIdentity("header." + payload + ".signature")?.label == "Test · test@example.com")
        #expect(AIUsageCredentials.codexIdentity("invalid") == nil)
        let profile = Data(#"{"oauthAccount":{"emailAddress":"test@example.com","displayName":"Test"}}"#.utf8)
        #expect(AIUsageCredentials.claudeIdentity(profile)?.label == "Test · test@example.com")
        #expect(AIUsageCredentials.claudeIdentity(Data(#"{"oauthAccount":{}}"#.utf8)) == nil)
    }

    @Test func newestClaudeCredentialIsTheFreshestItemOfItsService() {
        let old = AIUsageCredentials.KeychainItem(
            service: "Claude Code-credentials", account: "old", modifiedAt: now)
        let fresh = AIUsageCredentials.KeychainItem(
            service: "Claude Code-credentials", account: "fresh", modifiedAt: now.addingTimeInterval(1))
        let unrelated = AIUsageCredentials.KeychainItem(
            service: "other", account: "same", modifiedAt: now.addingTimeInterval(2))
        #expect(
            AIUsageCredentials.claudeItem([fresh, old, unrelated], service: "Claude Code-credentials") == fresh)
    }

    @Test func claudeLoginPrefersItsOwnKeychainItemThenTheFreshestClaudeCodeItem() {
        func item(_ service: String, _ offset: TimeInterval) -> AIUsageCredentials.KeychainItem {
            AIUsageCredentials.KeychainItem(
                service: service, account: "same", modifiedAt: now.addingTimeInterval(offset))
        }
        let defaultItem = item("Claude Code-credentials", 0)
        let newerShellItem = item("Claude Code-credentials-aaaaaaaa", 5)
        let olderShellItem = item("Claude Code-credentials-bbbbbbbb", 3)
        let unrelated = item("other", 9)
        // Its own item wins even when another Claude Code login is newer.
        #expect(
            AIUsageCredentials.claudeItem(
                [defaultItem, newerShellItem, unrelated], service: "Claude Code-credentials") == defaultItem)
        // Without its own item it takes the freshest Claude Code item, never an unrelated one.
        #expect(
            AIUsageCredentials.claudeItem(
                [olderShellItem, newerShellItem, unrelated], service: "Claude Code-credentials") == newerShellItem)
        #expect(AIUsageCredentials.claudeItem([unrelated], service: "Claude Code-credentials") == nil)
    }

    /// Expected suffixes are `printf '%s' <path> | shasum -a 256 | cut -c1-8`.
    @Test func keychainServiceHashesACustomConfigFolder() {
        #expect(AIUsageCredentials.keychainService(configDirectory: nil) == "Claude Code-credentials")
        #expect(
            AIUsageCredentials.keychainService(configDirectory: "/fixture/home/.claude-work")
                == "Claude Code-credentials-b49809ea")
        #expect(
            AIUsageCredentials.keychainService(configDirectory: "/fixture/Cafe\u{301}")
                == "Claude Code-credentials-35b0ebec")
    }

    @Test func accountsAreTheDefaultLoginsInProviderOrder() {
        #expect(AIUsageAccount.all.map(\.title) == ["Codex", "Claude"])
        #expect(Set(AIUsageAccount.all.map(\.id)).count == AIUsageAccount.all.count)
    }

    /// 2026-10-20 is a Tuesday; offsets are seconds from its UTC midnight.
    private static let resetCases: [(locale: String, offset: Int, expected: String)] = [
        ("en_GB", 52_740, "14:39"),
        ("en_GB", 568_740, "Mon 13:59"),
        ("en_GB", 722_520, "28 Oct at 08:42"),
        ("en_GB", -54_000, "19 Oct at 09:00"),
        ("vi_VN", 52_740, "14:39"),
        ("vi_VN", 722_520, "08:42 28 thg 10"),
    ]

    @Test(arguments: resetCases)
    func resetTimeShowsOnlyAsMuchDateAsItNeeds(_ example: (locale: String, offset: Int, expected: String)) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let midnight = Date(timeIntervalSince1970: 1_792_454_400)
        #expect(
            AIUsageResetFormat.text(
                midnight.addingTimeInterval(TimeInterval(example.offset)), now: midnight.addingTimeInterval(3600),
                calendar: calendar, locale: Locale(identifier: example.locale)) == example.expected)
    }

    @Test func securityOutputAcceptsPlainOrHexJSONButRejectsMalformedBytes() {
        #expect(AIUsageCredentials.keychainData(Data("{\"test\":1}\n".utf8)) == Data("{\"test\":1}".utf8))
        #expect(AIUsageCredentials.keychainData(Data("7b7d\n".utf8)) == Data("{}".utf8))
        #expect(AIUsageCredentials.keychainData(Data("é".utf8)) == nil)
        #expect(AIUsageCredentials.keychainData(Data("abc".utf8)) == nil)
    }

    @Test func credentialsParseOnlyTheRequiredProviderFields() throws {
        let codex = try AIUsageCredentials.parse(
            Data(#"{"tokens":{"access_token":"test","account_id":"account"}}"#.utf8), provider: .codex)
        #expect(codex.accountID == "account")
        let claude = try AIUsageCredentials.parse(
            Data(#"{"claudeAiOauth":{"accessToken":"test","refreshToken":"renew","expiresAt":1700003600000}}"#.utf8),
            provider: .claude)
        #expect(claude.expiresAt == now.addingTimeInterval(3600))
        #expect(claude.oauth?.refreshToken == "renew")
        let withoutRefresh = try AIUsageCredentials.parse(
            Data(#"{"claudeAiOauth":{"accessToken":"test","refreshToken":""}}"#.utf8), provider: .claude)
        #expect(withoutRefresh.oauth == nil)
        #expect(throws: (any Error).self) {
            try AIUsageCredentials.parse(Data(#"{"tokens":{"access_token":""}}"#.utf8), provider: .codex)
        }
    }
}

/// Stateless request fixtures; every request is intercepted and no real network is available.
private final class AIUsageFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let body: String
        switch url.host {
        case "openrouter.ai":
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            body = #"{"data":[]}"#
        case "chatgpt.com":
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
            #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "test-account")
            body = #"{"rate_limit":{"primary_window":{"used_percent":25}}}"#
        case "api.anthropic.com":
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
            #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
            body = #"{"five_hour":{"utilization":25,"resets_at":null}}"#
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Collects which logins the service asks for, across its actor boundary.
