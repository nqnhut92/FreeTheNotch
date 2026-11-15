import Foundation
import Testing

/// FullScreenSpaces against dictionaries shaped like the window server's
/// `CGSCopyManagedDisplaySpaces` reply: desktops are type 0, native
/// full-screen Spaces type 4.
struct FullScreenSpacesTests {
    private static let builtIn = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
    private static let external = "9E2C4B1F-6A7D-4C55-8F10-2B3A4C5D6E7F"

    private static func space(_ id: UInt64, type: Int) -> [String: Any] {
        ["id64": NSNumber(value: id), "ManagedSpaceID": NSNumber(value: id), "type": NSNumber(value: type)]
    }

    private static func display(_ identifier: String, spaces: [[String: Any]], current: UInt64) -> [String: Any] {
        [
            "Display Identifier": identifier,
            "Spaces": spaces,
            "Current Space": ["id64": NSNumber(value: current)],
        ]
    }

    @Test func onlyTheDisplayShowingAFullScreenSpaceIsReported() {
        let spaces = [
            Self.display(Self.builtIn, spaces: [Self.space(1, type: 0), Self.space(7, type: 4)], current: 1),
            Self.display(Self.external, spaces: [Self.space(3, type: 0), Self.space(9, type: 4)], current: 9),
        ]
        #expect(FullScreenSpaces.displayIdentifiers(showingFullScreenIn: spaces) == [Self.external])
    }

    @Test func aFullScreenSpaceThatIsNotShowingDoesNotCount() {
        let spaces = [
            Self.display(Self.builtIn, spaces: [Self.space(1, type: 0), Self.space(7, type: 4)], current: 1)
        ]
        #expect(FullScreenSpaces.displayIdentifiers(showingFullScreenIn: spaces).isEmpty)
    }

    @Test func everyDisplayInFullScreenIsReported() {
        let spaces = [
            Self.display(Self.builtIn, spaces: [Self.space(7, type: 4)], current: 7),
            Self.display(Self.external, spaces: [Self.space(3, type: 0), Self.space(9, type: 4)], current: 9),
        ]
        #expect(FullScreenSpaces.displayIdentifiers(showingFullScreenIn: spaces) == [Self.builtIn, Self.external])
    }

    @Test func malformedEntriesAreSkipped() {
        let spaces: [[String: Any]] = [
            [:],
            ["Display Identifier": Self.builtIn, "Spaces": [Self.space(7, type: 4)]],
            ["Spaces": [Self.space(7, type: 4)], "Current Space": ["id64": NSNumber(value: 7)]],
            ["Display Identifier": Self.external, "Spaces": "none", "Current Space": ["id64": NSNumber(value: 9)]],
        ]
        #expect(FullScreenSpaces.displayIdentifiers(showingFullScreenIn: spaces).isEmpty)
    }

    @Test(
        arguments: [
            // identifier, full-screen identifiers, expected
            (builtIn, [external], false),
            (external, [external], true),
            (builtIn, [builtIn, external], true),
            (builtIn, [], false),
            // "Displays have separate Spaces" off: one shared Space, listed as
            // "Main", and a full-screen app takes every display.
            (builtIn, ["Main"], true),
            (external, ["Main"], true),
        ] as [(String, Set<String>, Bool)])
    func aDisplayIsFullScreenWhenItsOwnSpaceOrTheSharedSpaceIs(
        identifier: String, fullScreen: Set<String>, expected: Bool
    ) {
        #expect(
            FullScreenSpaces.isFullScreen(displayIdentifier: identifier, fullScreenIdentifiers: fullScreen)
                == expected)
    }

    @Test func aDisplayWithoutAnIdentifierIsNotFullScreenOnItsOwn() {
        #expect(!FullScreenSpaces.isFullScreen(displayIdentifier: nil, fullScreenIdentifiers: [Self.external]))
    }

    @Test func theSharedSpaceIsReportedUnderItsOwnIdentifier() {
        let spaces = [Self.display("Main", spaces: [Self.space(1, type: 0), Self.space(5, type: 4)], current: 5)]
        #expect(FullScreenSpaces.displayIdentifiers(showingFullScreenIn: spaces) == ["Main"])
    }
}
