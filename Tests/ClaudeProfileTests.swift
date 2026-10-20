import Foundation
import Testing

struct ClaudeProfileTests {
    private static let home = URL(fileURLWithPath: "/fixture/home")

    @Test func registryFollowsXDGConfigHomeElseDotConfig() {
        #expect(
            ClaudeProfile.registryURL(home: Self.home, environment: [:]).path
                == "/fixture/home/.config/claude-multiprofile/profiles.json")
        #expect(
            ClaudeProfile.registryURL(home: Self.home, environment: ["XDG_CONFIG_HOME": "/fixture/xdg"]).path
                == "/fixture/xdg/claude-multiprofile/profiles.json")
        #expect(
            ClaudeProfile.registryURL(home: Self.home, environment: ["XDG_CONFIG_HOME": ""]).path
                == "/fixture/home/.config/claude-multiprofile/profiles.json")
    }

    @Test func registryKeepsEveryNamedProfileWithAFolderInOrder() throws {
        let registry = Data(
            #"""
            {"version":1,"profiles":[
              {"name":"desk","type":"desktop","desktop":{"dataDir":"/fixture/Desk"},"code":null},
              {"name":"term","type":"code","desktop":null,"code":{"configDir":"/fixture/home/.claude-term"}},
              {"name":"both","desktop":{"dataDir":"/fixture/Both"},"code":{"configDir":"/fixture/both-code"}},
              {"name":"desk","desktop":{"dataDir":"/fixture/Duplicate"}},
              {"name":"","desktop":{"dataDir":"/fixture/Unnamed"}},
              {"name":"relative","desktop":{"dataDir":"Relative"}},
              {"name":"empty","desktop":null,"code":null}
            ]}
            """#.utf8)
        let profiles = ClaudeProfile.profiles(registry: registry)
        #expect(profiles.map(\.name) == ["desk", "term", "both"])
        let desk = try #require(profiles.first)
        #expect(desk.desktopCacheDirectory?.path == "/fixture/Desk/Cache/Cache_Data")
        #expect(desk.codeConfigDirectory == nil)
        #expect(desk.codeLogRoot == nil)
        #expect(desk.codeKeychainService == nil)
        let term = profiles[1]
        #expect(term.desktopCacheDirectory == nil)
        #expect(term.codeLogRoot?.path == "/fixture/home/.claude-term/projects")
        #expect(term.codeAccountFile?.path == "/fixture/home/.claude-term/.claude.json")
        #expect(term.codeCredentialsFile?.path == "/fixture/home/.claude-term/.credentials.json")
    }

    @Test(arguments: [Data("not json".utf8), Data(#"{"profiles":{}}"#.utf8), Data(#"{"version":1}"#.utf8)])
    func malformedRegistryHasNoProfiles(_ data: Data) {
        #expect(ClaudeProfile.profiles(registry: data).isEmpty)
    }

    @Test func missingRegistryHasNoProfiles() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(ClaudeProfile.profiles(home: home, environment: [:]).isEmpty)
    }

    @Test func registryIsReadFromDisk() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let url = ClaudeProfile.registryURL(home: home, environment: [:])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"profiles":[{"name":"disk","code":{"configDir":"/fixture/disk"}}]}"#.utf8).write(to: url)
        #expect(ClaudeProfile.profiles(home: home, environment: [:]).map(\.name) == ["disk"])
    }

    /// Expected suffixes are `printf '%s' <path> | shasum -a 256 | cut -c1-8`.
    @Test func keychainServiceHashesACustomConfigFolder() {
        #expect(ClaudeProfile.keychainService(configDirectory: nil) == "Claude Code-credentials")
        #expect(
            ClaudeProfile.keychainService(configDirectory: "/fixture/home/.claude-work")
                == "Claude Code-credentials-b49809ea")
        #expect(
            ClaudeProfile.keychainService(configDirectory: "/fixture/Cafe\u{301}") == "Claude Code-credentials-35b0ebec"
        )
    }

    @Test func accountsListDefaultLoginsBeforeProfiles() {
        let profile = ClaudeProfile(
            name: "fixture", desktopDataDirectory: URL(fileURLWithPath: "/fixture/desktop"), codeConfigDirectory: nil)
        let accounts = AIUsageAccount.all(profiles: [profile])
        #expect(accounts.map(\.title) == ["Codex", "Claude", "Claude · fixture"])
        #expect(Set(accounts.map(\.id)).count == accounts.count)
    }
}
