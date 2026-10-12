import Foundation

/// Provider profile directories shared by quota accounting and session activity readers.
struct AIUsageDirectories: Sendable {
    let codex: URL
    let claude: URL

    init(home: URL, environment: [String: String]) {
        codex = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        claude =
            environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude")
    }

    var logRoots: [AIUsageProvider: URL] {
        [.codex: codex.appendingPathComponent("sessions"), .claude: claude.appendingPathComponent("projects")]
    }

    var claudeSessions: URL { claude.appendingPathComponent("sessions") }
}
