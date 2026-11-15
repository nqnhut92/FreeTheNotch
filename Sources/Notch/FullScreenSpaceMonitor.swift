// Per-display full-screen detection follows Atoll (GPL-3.0-or-later):
// DynamicIsland/observers/FullscreenMediaDetection.swift (re-check on Space
// and screen changes, after a short delay). The Space query mirrors Vorssaint
// (GPL-3.0-or-later): Sources/Vorssaint/Services/Switcher/SpaceWindowBridge.swift.

import AppKit
import Combine
import os

/// Publishes the displays that currently show a native full-screen Space, so
/// the notch and the Side Notch can leave those displays alone.
@MainActor
final class FullScreenSpaceMonitor: ObservableObject {
    @Published private(set) var fullScreenDisplays: Set<CGDirectDisplayID> = []

    /// The window server can still report the old Space when the
    /// notification arrives; Atoll re-checks after this long.
    private static let settleDelay: Duration = .milliseconds(500)
    /// `RTLD_DEFAULT`, which Swift does not import.
    private static let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)

    /// Nil when the private symbols are gone: nothing is ever full screen.
    private let copyManagedDisplaySpaces: (() -> [[String: Any]]?)?
    private var observers: [AnyCancellable] = []
    private var settleTask: Task<Void, Never>?

    init() {
        typealias MainConnection = @convention(c) () -> Int32
        typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

        if let mainSymbol = dlsym(Self.defaultHandle, "CGSMainConnectionID"),
            let copySymbol = dlsym(Self.defaultHandle, "CGSCopyManagedDisplaySpaces")
        {
            let connection = unsafeBitCast(mainSymbol, to: MainConnection.self)()
            let copy = unsafeBitCast(copySymbol, to: CopyManagedDisplaySpaces.self)
            copyManagedDisplaySpaces = { copy(connection)?.takeRetainedValue() as? [[String: Any]] }
        } else {
            Logger.app.error("[FreeTheNotch] Space query unavailable: full-screen displays are not detected")
            copyManagedDisplaySpaces = nil
        }

        observers = [
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification),
        ].map { publisher in
            publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.spacesChanged() }
        }
        refresh()
    }

    private func spacesChanged() {
        refresh()
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func refresh() {
        let identifiers = FullScreenSpaces.displayIdentifiers(showingFullScreenIn: copyManagedDisplaySpaces?() ?? [])
        let displays = Set(
            NSScreen.screens.compactMap { screen -> CGDirectDisplayID? in
                guard let displayID = screen.displayID else { return nil }
                let isFullScreen = FullScreenSpaces.isFullScreen(
                    displayIdentifier: Self.identifier(of: displayID), fullScreenIdentifiers: identifiers)
                return isFullScreen ? displayID : nil
            })
        guard displays != fullScreenDisplays else { return }
        fullScreenDisplays = displays
        Logger.app.notice("[FreeTheNotch] Full-screen displays: \(displays.count, privacy: .public)")
    }

    /// The display's UUID string, which is how the window server names it.
    private static func identifier(of displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
