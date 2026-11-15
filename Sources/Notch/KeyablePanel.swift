import AppKit

/// Atoll-style panel: can become key AND main so text fields accept
/// typing/paste without NSApp.activate hacks. Floating panel behavior.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// AppKit's default pulls windows down so they sit under the menu bar.
    /// The notch has to occupy that band, so the frame we ask for is the frame we get.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// A window that overlaps the menu bar gets a content rect that stops
    /// below that band. The page icons are drawn in the band and then miss
    /// every click. The content view has to cover the whole frame.
    override var contentLayoutRect: NSRect {
        NSRect(origin: .zero, size: frame.size)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        super.setFrame(frameRect, display: displayFlag)
        contentView?.frame = NSRect(origin: .zero, size: frame.size)
    }
}
