import os

/// The app's unified-log channels. Every message starts with "[FreeTheNotch]"
/// so both `subsystem == "com.freethenotch.app"` and the older
/// `eventMessage CONTAINS "[FreeTheNotch]"` predicate find it (AGENTS.md,
/// Diagnostics).
extension Logger {
    static let subsystem = "com.freethenotch.app"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let lockScreen = Logger(subsystem: subsystem, category: "LockScreen")
    static let artworkWallpaper = Logger(subsystem: subsystem, category: "ArtworkWallpaper")
    static let settings = Logger(subsystem: subsystem, category: "Settings")
    static let media = Logger(subsystem: subsystem, category: "Media")
    static let hud = Logger(subsystem: subsystem, category: "HUD")
    static let bluetooth = Logger(subsystem: subsystem, category: "Bluetooth")
    static let modules = Logger(subsystem: subsystem, category: "Modules")
}
