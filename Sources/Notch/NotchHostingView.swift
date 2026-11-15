import AppKit
import SwiftUI

/// Hosting view that lets clicks pass through the transparent parts of the
/// fixed-size window. Only the visible black shape is interactive.
///
/// The window stays 740 pt wide and tall enough for the tallest page; only
/// the SwiftUI shape morphs (resizing the window, as Atoll does, broke the
/// expand animation).
///
/// Clicks (Atoll's FirstMouseHostingView): outside the shape, hitTest
/// returns nil so the click reaches the app underneath. Inside, SwiftUI's
/// own hit-testing picks the target, so mouseDown and mouseUp both reach
/// the same view and Buttons fire. acceptsFirstMouse lets the first click
/// land without the panel being key.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// Current interactive size (the black shape), top-centered.
    var hitSize = CGSize(width: DisplayGeometry.pillWidth, height: DisplayGeometry.pillHeight)

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        shapeContains(point) ? super.hitTest(point) : nil
    }

    /// `point` arrives in the superview's (unflipped) coordinates while this
    /// view is flipped, so it is converted before the shape, anchored to the
    /// top, is tested.
    private func shapeContains(_ point: NSPoint) -> Bool {
        let local = convert(point, from: superview)
        let rect = NSRect(
            x: (bounds.width - hitSize.width) / 2,
            y: isFlipped ? 0 : bounds.height - hitSize.height,
            width: hitSize.width,
            height: hitSize.height)
        return rect.contains(local)
    }
}
