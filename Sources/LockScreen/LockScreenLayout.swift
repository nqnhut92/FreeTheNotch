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

    /// Room under the widgets for the output list, which opens below the player's buttons. The window is
    /// transparent there, and fully transparent pixels let clicks through to the lock screen.
    static let outputPanelRoom: CGFloat = 260

    /// `frame` (AppKit coordinates, origin bottom-left) with `outputPanelRoom` more below it.
    static func withOutputPanelRoom(_ frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX, y: frame.minY - outputPanelRoom, width: frame.width, height: frame.height + outputPanelRoom)
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

/// Where the spinning record stands when the artwork wallpaper is up and the song comes from a record player
/// (`VinylSource`): in the place of the sharp artwork, a little lower, with the tonearm to its right. Points from the screen's
/// top-left. The constants match `TurntableView`'s 300 × 300 drawing space.
enum LockVinylLayout {
    /// The record's diameter as a fraction of the largest artwork `LockArtworkImage` draws. Smaller than the
    /// artwork's sharp part, so the record stays clear of the clock.
    static let recordFraction: CGFloat = 0.6
    private static let recordCenterInTurntable = CGPoint(x: 130, y: 150)
    private static let recordDiameterInTurntable: CGFloat = 248
    private static let turntableSide: CGFloat = 300
    /// How far below the artwork's centre the record stands, which leaves the clock above it clear.
    static let drop: CGFloat = 50

    /// Drawing points per turntable unit.
    private static func scale(forScreenHeight height: CGFloat) -> CGFloat {
        height * LockArtworkImage.maxSideFraction * recordFraction / recordDiameterInTurntable
    }

    /// The square the turntable (record and tonearm) is drawn in.
    static func turntableFrame(in screenSize: CGSize) -> CGRect {
        let scale = scale(forScreenHeight: screenSize.height)
        let center = recordFrame(in: screenSize)
        return CGRect(
            x: center.midX - recordCenterInTurntable.x * scale,
            y: center.midY - recordCenterInTurntable.y * scale,
            width: turntableSide * scale, height: turntableSide * scale)
    }

    /// The record itself, centred where the artwork is.
    static func recordFrame(in screenSize: CGSize) -> CGRect {
        let diameter = recordDiameterInTurntable * scale(forScreenHeight: screenSize.height)
        return CGRect(
            x: (screenSize.width - diameter) / 2,
            y: screenSize.height * LockArtworkImage.centerFromTop + drop - diameter / 2,
            width: diameter, height: diameter)
    }
}
