import AppKit

/// The menu bar icon: the cup symbol as a template image, so it follows the
/// menu bar's light or dark appearance.
enum MenuBarIcon {
    static let image: NSImage? = NSImage(
        systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "FreeTheNotch"
    )?
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))

    /// Orange, non-template, while keep-awake is active. Same orange as the
    /// macOS microphone-in-use indicator.
    static let orangeImage: NSImage? = image.map { symbol in
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.systemOrange.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}
