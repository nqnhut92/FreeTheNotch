// Reads the profile registry written by claude-multiprofile (MIT): src/registry.js, src/code.js and src/desktop.js.
// Only the registry's file format is used; no code from that project is included.

import CryptoKit
import Foundation

/// A separate Claude login created by claude-multiprofile: a Desktop data folder, a Claude Code config folder, or both.
struct ClaudeProfile: Hashable, Sendable {
    let name: String
    let desktopDataDirectory: URL?
    let codeConfigDirectory: URL?

    private static let registryFolder = "claude-multiprofile"
    private static let registryFile = "profiles.json"
    private static let defaultKeychainService = "Claude Code-credentials"
    private static let keychainHashLength = 8

    /// The registry follows XDG_CONFIG_HOME when set, else `~/.config`, as claude-multiprofile does.
    static func registryURL(home: URL, environment: [String: String]) -> URL {
        let configHome =
            environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".config")
        return configHome.appendingPathComponent(registryFolder).appendingPathComponent(registryFile)
    }

    /// Profiles in registry order. A malformed registry or entry is skipped rather than reported:
    /// the default Claude account keeps working either way.
    static func profiles(registry data: Data) -> [ClaudeProfile] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = root["profiles"] as? [[String: Any]]
        else { return [] }
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard let name = (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty, seen.insert(name).inserted
            else { return nil }
            let desktop = directory(entry["desktop"], key: "dataDir")
            let code = directory(entry["code"], key: "configDir")
            guard desktop != nil || code != nil else { return nil }
            return ClaudeProfile(name: name, desktopDataDirectory: desktop, codeConfigDirectory: code)
        }
    }

    static func profiles(home: URL, environment: [String: String]) -> [ClaudeProfile] {
        guard let data = try? Data(contentsOf: registryURL(home: home, environment: environment)) else { return [] }
        return profiles(registry: data)
    }

    /// Claude Desktop keeps the last Settings → Usage response in its Chromium HTTP cache.
    var desktopCacheDirectory: URL? {
        desktopDataDirectory?.appendingPathComponent("Cache").appendingPathComponent("Cache_Data")
    }

    var codeLogRoot: URL? { codeConfigDirectory?.appendingPathComponent("projects") }

    /// With CLAUDE_CONFIG_DIR set, Claude Code keeps the account profile beside its config, not in `~/.claude.json`.
    var codeAccountFile: URL? { codeConfigDirectory?.appendingPathComponent(".claude.json") }

    var codeCredentialsFile: URL? { codeConfigDirectory?.appendingPathComponent(".credentials.json") }

    var codeKeychainService: String? {
        codeConfigDirectory.map { Self.keychainService(configDirectory: $0.path) }
    }

    /// Claude Code suffixes its Keychain item with a short SHA-256 of a custom CLAUDE_CONFIG_DIR,
    /// so each config folder has its own login.
    static func keychainService(configDirectory: String?) -> String {
        guard let configDirectory else { return defaultKeychainService }
        let digest = SHA256.hash(data: Data(configDirectory.precomposedStringWithCanonicalMapping.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return defaultKeychainService + "-" + hex.prefix(keychainHashLength)
    }

    private static func directory(_ value: Any?, key: String) -> URL? {
        guard let object = value as? [String: Any], let path = object[key] as? String, path.hasPrefix("/") else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
