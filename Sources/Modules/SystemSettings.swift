// Settings deep links from DuoBar (github.com/Mikeli7666/DuoBar), MIT:
// Utilities/SystemSettingsOpener.swift.

import AppKit

/// Opens a System Settings pane, trying each known URL for it (the
/// identifiers changed between macOS releases) and falling back to the app.
enum SystemSettings {
    enum Pane {
        case wifi, network, bluetooth, sound, battery, storage
        case locationServices, accessibility

        /// Most specific first.
        var urls: [String] {
            let prefix = "x-apple.systempreferences:"
            let identifiers: [String]
            switch self {
            case .wifi: identifiers = ["com.apple.wifi-settings-extension", "com.apple.Network-Settings.extension"]
            case .network: identifiers = ["com.apple.Network-Settings.extension", "com.apple.wifi-settings-extension"]
            case .bluetooth: identifiers = ["com.apple.BluetoothSettings", "com.apple.preferences.Bluetooth"]
            case .sound: identifiers = ["com.apple.Sound-Settings.extension", "com.apple.preference.sound"]
            case .battery: identifiers = ["com.apple.Battery-Settings.extension"]
            case .storage: identifiers = ["com.apple.Storage-Settings.extension"]
            case .locationServices:
                identifiers = [
                    "com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices",
                    "com.apple.preference.security?Privacy_LocationServices",
                ]
            case .accessibility: identifiers = ["com.apple.preference.security?Privacy_Accessibility"]
            }
            return identifiers.map { prefix + $0 }
        }
    }

    private static let appURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")

    static func open(_ pane: Pane) {
        for string in pane.urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(appURL)
    }
}
