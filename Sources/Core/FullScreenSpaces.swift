// Space topology parsing mirrors Vorssaint (GPL-3.0-or-later):
// Sources/Vorssaint/Services/Switcher/SpaceWindowBridge.swift (`topology`,
// `Topology.isFullscreen`).

import Foundation

/// Which displays show a native full-screen Space, worked out from the
/// window server's managed display spaces (`CGSCopyManagedDisplaySpaces`):
/// one dictionary per display, with its Spaces and the one showing now.
enum FullScreenSpaces {
    /// `type` of a native full-screen Space (Split View included). An
    /// ordinary desktop is type 0.
    static let fullScreenSpaceType = 4
    /// Identifier of the one shared entry when "Displays have separate
    /// Spaces" is off; otherwise every entry carries its display's UUID.
    static let sharedSpaceIdentifier = "Main"

    private enum Key {
        static let displayIdentifier = "Display Identifier"
        static let spaces = "Spaces"
        static let currentSpace = "Current Space"
        static let spaceID = "id64"
        static let spaceType = "type"
    }

    /// Identifiers (display UUID strings) of the displays whose current
    /// Space is a full-screen one.
    static func displayIdentifiers(showingFullScreenIn managedDisplaySpaces: [[String: Any]]) -> Set<String> {
        var identifiers: Set<String> = []
        for display in managedDisplaySpaces {
            guard
                let identifier = display[Key.displayIdentifier] as? String,
                let current = spaceID(display[Key.currentSpace] as? [String: Any])
            else { continue }
            let spaces = display[Key.spaces] as? [[String: Any]] ?? []
            let isFullScreen = spaces.contains { space in
                spaceID(space) == current && (space[Key.spaceType] as? NSNumber)?.intValue == fullScreenSpaceType
            }
            if isFullScreen { identifiers.insert(identifier) }
        }
        return identifiers
    }

    /// Whether the display with this UUID string is covered by a full-screen
    /// Space: its own, or the shared one, where a full-screen app takes
    /// every display. Read from the reply itself rather than
    /// `NSScreen.screensHaveSeparateSpaces`, so one display's full-screen
    /// app can never hide the notch on another.
    static func isFullScreen(displayIdentifier: String?, fullScreenIdentifiers: Set<String>) -> Bool {
        if fullScreenIdentifiers.contains(sharedSpaceIdentifier) { return true }
        guard let displayIdentifier else { return false }
        return fullScreenIdentifiers.contains(displayIdentifier)
    }

    private static func spaceID(_ space: [String: Any]?) -> UInt64? {
        (space?[Key.spaceID] as? NSNumber)?.uint64Value
    }
}
