import Foundation
import Testing

struct ConferenceProviderTests {
    @Test(arguments: [
        ("https://zoom.us/j/123", ConferenceProvider.zoom),
        ("https://us02web.ZOOM.us/j/123?pwd=x", .zoom),
        ("https://teams.microsoft.com/l/meetup-join/abc", .teams),
        ("https://meet.google.com/abc-defg-hij", .meet),
        ("https://acme.webex.com/meet/nick", .webex),
        ("https://facetime.apple.com/join#v=1", .facetime),
        ("https://meet.jit.si/standup", .jitsi),
        ("https://jitsi.acme.org/standup", .jitsi),
        ("https://discord.gg/abc", .discord),
        ("https://example.com/meeting", .generic),
    ])
    func detectsTheService(_ link: String, expected: ConferenceProvider) throws {
        #expect(ConferenceProvider.detect(from: try #require(URL(string: link))) == expected)
    }

    /// A host only matches the service's domain or a subdomain of it.
    @Test(arguments: [
        "https://zoom.us.evil.com/j/1",
        "https://notzoom.us/j/1",
        "https://teams.microsoft.com.evil.com/l/meetup-join/abc",
        "https://evil.com/zoom.us",
        "https://myjitsiclone.com/room",
        "mailto:someone@zoom.us",
    ])
    func lookalikeHostsAreGeneric(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(ConferenceProvider.detect(from: url) == .generic)
        #expect(ConferenceProvider.joinURL(for: url) == url)
    }

    @Test(arguments: [
        (
            "https://teams.microsoft.com/l/meetup-join/abc?ctx=1",
            "msteams://teams.microsoft.com/l/meetup-join/abc?ctx=1"
        ),
        ("https://discord.com/channels/1/2", "discord://discord.com/channels/1/2"),
        ("https://facetime.apple.com/join#v=1&p=x", "facetime://facetime.apple.com/join#v=1&p=x"),
    ])
    func joinOpensTheApp(_ link: String, expected: String) throws {
        let url = try #require(URL(string: link))
        #expect(ConferenceProvider.joinURL(for: url).absoluteString == expected)
    }

    /// Zoom keeps its web link, as in Atoll; services without an app scheme
    /// keep theirs.
    @Test(arguments: ["https://us02web.zoom.us/j/123?pwd=x", "https://meet.google.com/abc-defg-hij"])
    func joinKeepsTheWebLink(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(ConferenceProvider.joinURL(for: url) == url)
    }
}
