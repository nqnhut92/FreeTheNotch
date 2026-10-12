import AppKit
import Darwin
import os

/// Moves a window into the lock-screen space. `CGShieldingWindowLevel` alone
/// is covered almost immediately on macOS 27 (the widget flashes, then is
/// gone). A SkyLight space at the Notification Center's lock-screen level
/// stays above it: the approach Atoll uses via SkyLightWindow.
@MainActor
final class SkyLightLockSpace {
    static let shared = SkyLightLockSpace()

    /// kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock.
    private static let notificationCenterAtScreenLockLevel: Int32 = 400
    /// Options for SLSSpaceAddWindowsAndRemoveFromSpaces (undocumented):
    /// the value that moves a window here out of the spaces it was in.
    private static let moveFromAllSpaces: Int32 = 7
    private static let frameworkPaths = [
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
    ]

    private let addWindow: ((NSWindow) -> Void)?

    var isAvailable: Bool { addWindow != nil }

    private init() {
        typealias MainConnection = @convention(c) () -> Int32
        typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
        typealias SpaceSetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
        typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
        typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

        guard
            let handle = Self.frameworkPaths.lazy.compactMap({ dlopen($0, RTLD_NOW) }).first,
            let mainSym = dlsym(handle, "SLSMainConnectionID"),
            let createSym = dlsym(handle, "SLSSpaceCreate"),
            let levelSym = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
            let showSym = dlsym(handle, "SLSShowSpaces"),
            let addSym = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else {
            Logger.lockScreen.error("[FreeTheNotch] SkyLight lock space unavailable")
            addWindow = nil
            return
        }

        let connection = unsafeBitCast(mainSym, to: MainConnection.self)()
        let space = unsafeBitCast(createSym, to: SpaceCreate.self)(connection, 1, 0)
        _ = unsafeBitCast(levelSym, to: SpaceSetLevel.self)(
            connection, space, Self.notificationCenterAtScreenLockLevel)
        _ = unsafeBitCast(showSym, to: ShowSpaces.self)(connection, [NSNumber(value: space)] as CFArray)
        let add = unsafeBitCast(addSym, to: AddWindows.self)
        addWindow = { window in
            guard window.windowNumber > 0 else { return }
            _ = add(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, Self.moveFromAllSpaces)
        }
        Logger.lockScreen.notice(
            "[FreeTheNotch] SkyLight lock space ready (connection=\(connection, privacy: .public) space=\(space, privacy: .public))"
        )
    }

    /// The window needs a number (order it front first) before SkyLight
    /// will adopt it.
    func adopt(_ window: NSWindow) {
        addWindow?(window)
    }
}

/// Window levels on the lock screen, all relative to the shielding level
/// macOS draws the lock screen at. They also sit in the SkyLight space,
/// where this order still holds.
enum LockScreenLevel {
    /// The lock notch.
    static let notch = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    /// The widget window, over the notch.
    static let widgets = NSWindow.Level(rawValue: notch.rawValue + 1)
    /// The artwork's click target, over the widgets.
    static let artworkClick = NSWindow.Level(rawValue: notch.rawValue + 2)
    /// The wallpaper transition's cover, under everything of ours.
    static let cover = NSWindow.Level(rawValue: notch.rawValue - 1)
    /// The cover after unlock: Atoll's level, above the wallpaper and under
    /// every window.
    static let desktopCover = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
}
