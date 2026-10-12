import CoreGraphics

/// Where the lock-screen windows go, as plain geometry: LockScreenManager,
/// the Settings preview and the tests all use it, so the widgets sit in
/// the same place everywhere. Sizes are in points, measured from the
/// screen's top-left unless a function says otherwise.
enum LockScreenLayout {
    /// Widget window width. The height is what the screen leaves between
    /// the clock and the login area (`widgetFrame(in:)`).
    static let widgetWidth: CGFloat = 460
    /// The widget window never gets shorter than this; rings, event,
    /// reminders, timer and the player need about 450 pt when all show.
    static let minimumWidgetHeight: CGFloat = 220
    /// Kept free at the bottom for macOS's user picture, name and password
    /// field. On a 14" MacBook Pro the picture starts ~295 pt above the
    /// bottom edge.
    static let loginAreaHeight: CGFloat = 320
    /// Atoll parks the widgets just under the clock: about a third of the
    /// way down, and never higher than `belowClockMinimum`.
    static let belowClockFraction: CGFloat = 0.30
    static let belowClockMinimum: CGFloat = 340
    /// Gap between the largest artwork LockArtworkImage draws and the
    /// artwork controls under it.
    static let artworkControlsGap: CGFloat = 20
    /// Room the artwork controls (LockScreenArtworkControls) take, so they
    /// never leave the widget window.
    static let artworkControlsHeight: CGFloat = 116

    /// The widget window: under the clock, down to the login area.
    /// Transparent where nothing is drawn. A 1512 × 982 pt screen (14")
    /// gets x 526, top 340, height 322.
    static func widgetFrame(in screenSize: CGSize) -> CGRect {
        let fromTop = max(belowClockMinimum, screenSize.height * belowClockFraction)
        let top = min(fromTop, screenSize.height - loginAreaHeight - minimumWidgetHeight)
        let height = max(minimumWidgetHeight, screenSize.height - loginAreaHeight - top)
        return CGRect(x: (screenSize.width - widgetWidth) / 2, y: top, width: widgetWidth, height: height)
    }

    /// Top of LockScreenArtworkControls in artwork mode: just under the
    /// largest artwork LockArtworkImage draws, but never so low that the
    /// controls leave the widget window.
    static func artworkControlsTop(in screenSize: CGSize) -> CGFloat {
        let artworkBottom = screenSize.height * (LockArtworkImage.centerFromTop + LockArtworkImage.maxSideFraction / 2)
        return min(artworkBottom + artworkControlsGap, widgetFrame(in: screenSize).maxY - artworkControlsHeight)
    }

    /// The widget window on a screen at `screenFrame`, in AppKit
    /// coordinates (origin bottom-left), and the artwork controls' offset
    /// from the window's top.
    static func widgetPlacement(onScreenFrame screenFrame: CGRect) -> (frame: CGRect, controlsOffset: CGFloat) {
        let local = widgetFrame(in: screenFrame.size)
        let frame = CGRect(
            x: screenFrame.minX + local.minX,
            y: screenFrame.maxY - local.maxY,
            width: local.width, height: local.height)
        return (frame, artworkControlsTop(in: screenFrame.size) - local.minY)
    }
}

/// The lock notch: the closed island stretched by a padlock ear on each
/// side (Atoll's LockScreenLiveActivityOverlay).
enum LockNotchLayout {
    /// The padlock ear is the notch height less this.
    static let indicatorInset: CGFloat = 12
    /// Atoll's cornerRadiusInsets.closed.bottom: padding each side, and the
    /// bottom corner radius.
    static let horizontalPadding: CGFloat = 14

    static func indicatorSize(notchHeight: CGFloat) -> CGFloat {
        max(0, notchHeight - indicatorInset)
    }

    /// Rounds up to whole points. `safeAreaInsets.top` is fractional (33.5 pt
    /// on 14"): AppKit rounds the window frame but SwiftUI lays out at the
    /// fractional size, leaving a hairline of wallpaper (Atoll's
    /// snappedNotchSize).
    static func snapped(_ size: CGSize) -> CGSize {
        CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    static func windowSize(notchSize: CGSize) -> CGSize {
        let indicator = indicatorSize(notchHeight: notchSize.height)
        return CGSize(width: notchSize.width + indicator * 2 + horizontalPadding * 2, height: notchSize.height)
    }

    /// Centred on the screen's top edge, in AppKit coordinates.
    static func windowFrame(size: CGSize, onScreenFrame screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height,
            width: size.width, height: size.height)
    }
}
