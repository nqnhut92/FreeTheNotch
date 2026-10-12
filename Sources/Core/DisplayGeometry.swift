import AppKit

/// Display metrics for the notch / pill layout, following Atoll's approach:
/// the collapsed bar hugs the physical camera housing using the screen's
/// auxiliary areas (the exact regions macOS reserves beside the notch).
enum DisplayGeometry {
    static let pillWidth: CGFloat = 210
    static let pillHeight: CGFloat = 28
    /// Atoll's open island: player on the left, one calendar column on the right.
    /// 720 (Atoll 640): room for the lunar date and six page icons.
    static let expandedWidth: CGFloat = 720

    /// Extra width added to each side of the camera while music plays,
    /// so artwork and the waveform sit in the ears like a Dynamic Island.
    static let liveActivityEar: CGFloat = 62

    /// Camera housing width when macOS reports no auxiliary areas: the
    /// 14" and 16" MacBook Pro notch is about this wide.
    static let fallbackNotchWidth: CGFloat = 170
    /// Menu-bar thickness when a screen reports neither a menu bar nor a
    /// safe area (a hidden menu bar): the classic non-notch menu bar.
    static let fallbackMenuBarHeight: CGFloat = 24

    static func liveActivityWidth(notchWidth: CGFloat) -> CGFloat {
        notchWidth + liveActivityEar * 2
    }

    /// Matches the expanded battery notification: content stays below the camera band.
    private static let aiQuotaHUDExtraWidth: CGFloat = 150
    private static let aiQuotaHUDBodyHeight: CGFloat = 75

    static func aiQuotaHUDSize(notchWidth: CGFloat, notchHeight: CGFloat) -> CGSize {
        CGSize(width: max(0, notchWidth) + aiQuotaHUDExtraWidth, height: max(0, notchHeight) + aiQuotaHUDBodyHeight)
    }

    /// The Mac's own display: the notch screen, else the built-in panel.
    /// Nil when there is none (lid closed on an external display), so
    /// "Built-in only" shows nothing instead of falling back to the main
    /// display.
    static func builtInScreen(in screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first(where: hasNotch)
            ?? screens.first { screen in
                screen.displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
            }
    }

    /// Screens for Settings → General → Displays, shared by the notch and
    /// Side Notch.
    static func targetScreens(for scope: DisplayScope, in screens: [NSScreen] = NSScreen.screens) -> [NSScreen] {
        switch scope {
        case .mainOnly:
            return builtInScreen(in: screens).map { [$0] } ?? []
        case .mainDisplay:
            // screens[0] holds the menu bar; NSScreen.main follows the key window.
            return screens.first.map { [$0] } ?? []
        case .allDisplays:
            return screens
        }
    }

    /// True when the screen has a physical camera cutout. Notch displays
    /// hug the cutout; every other display gets a floating pill.
    static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    /// Exact width of the physical camera housing, derived from the
    /// auxiliary areas macOS reserves beside it.
    static func physicalNotchWidth(for screen: NSScreen) -> CGFloat {
        physicalNotchWidth(
            screenWidth: screen.frame.width,
            auxiliaryLeft: screen.auxiliaryTopLeftArea, auxiliaryRight: screen.auxiliaryTopRightArea)
    }

    static func physicalNotchWidth(screenWidth: CGFloat, auxiliaryLeft: CGRect?, auxiliaryRight: CGRect?) -> CGFloat {
        guard let auxiliaryLeft, let auxiliaryRight else { return fallbackNotchWidth }
        return screenWidth - auxiliaryLeft.width - auxiliaryRight.width
    }

    /// Menu-bar thickness on this display. The idle notch uses this exactly:
    /// an extra point made the black shape hang below the menu bar.
    /// Each screen reports its own value (notch Macs are often ~37–39pt;
    /// an external display can differ).
    static func menuBarHeight(for screen: NSScreen) -> CGFloat {
        menuBarHeight(frame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaTop: screen.safeAreaInsets.top)
    }

    static func menuBarHeight(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat) -> CGFloat {
        let measured = frame.maxY - visibleFrame.maxY
        if measured > 1 { return measured }
        if safeAreaTop > 0 { return safeAreaTop }
        return fallbackMenuBarHeight
    }

    /// Height of the menu-bar band the black shape must fill.
    /// Atoll's .matchRealNotchSize: on notch displays use the physical cutout
    /// height (safeAreaInsets.top), not the menu bar height — the menu bar can
    /// be 1px taller than the camera housing.
    static func notchHeight(for screen: NSScreen) -> CGFloat {
        if screen.safeAreaInsets.top > 0 {
            return screen.safeAreaInsets.top
        }
        return menuBarHeight(for: screen)
    }

    /// Collapsed bar size: a notch-hugging pill on notched displays,
    /// a centered floating pill everywhere else.
    static func collapsedSize(for screen: NSScreen) -> CGSize {
        if hasNotch(screen) {
            return CGSize(width: physicalNotchWidth(for: screen), height: notchHeight(for: screen))
        }
        return CGSize(width: pillWidth, height: menuBarHeight(for: screen))
    }
}

extension NSScreen {
    /// The Core Graphics display ID behind this screen.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
