// Adapted from Atoll (GPL-3.0-or-later): managers/LLMUsage/Quota/KeychainReader.swift (ClaudeKeychainStore).

import Foundation
import Security

/// Writes a refreshed Claude Code credential back to its Keychain item.
///
/// Claude Code uses Apple's `security` tool, so the write goes through the same tool: updating a file-based Keychain
/// secret resets its partition ACL to the writer's identity, and a native write would make Claude Code ask for
/// access again at its next read.
enum ClaudeKeychainStore {
    /// SecurityTool's interactive command buffer is 4096 bytes including its terminator. An oversized command is
    /// refused rather than silently truncating a credential.
    static let maximumCommandBytes = 4095
    private static let timeout: TimeInterval = 15

    /// Nil on success, else a failure status. Updates only an item that still exists, so a credential removed by
    /// a sign-out is not recreated by a stale refresh.
    static func update(service: String, account: String?, secret: String) -> OSStatus? {
        guard let account, let command = updateCommand(service: service, account: account, secret: secret) else {
            return errSecParam
        }
        let lookup = Subprocess.run(
            "/usr/bin/security", arguments: ["find-generic-password", "-s", service, "-a", account], timeout: timeout)
        guard lookup?.succeeded == true else { return errSecItemNotFound }
        let write = Subprocess.run("/usr/bin/security", arguments: ["-i"], input: command, timeout: timeout)
        return write?.succeeded == true ? nil : errSecIO
    }

    /// The command goes through standard input, never a shell or the process argument list. Quotes and backslashes
    /// use SecurityTool's own quoting. Nil when a value cannot be quoted or the command is too long.
    static func updateCommand(service: String, account: String?, secret: String) -> Data? {
        guard let account, let serviceArgument = quoted(service), let accountArgument = quoted(account),
            let secretArgument = quoted(secret)
        else { return nil }
        let data = Data(
            "add-generic-password -U -s \(serviceArgument) -a \(accountArgument) -w \(secretArgument)\n".utf8)
        return data.count <= maximumCommandBytes ? data : nil
    }

    private static func quoted(_ value: String) -> String? {
        guard !value.contains("\0"), !value.contains("\n"), !value.contains("\r") else { return nil }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }
}
