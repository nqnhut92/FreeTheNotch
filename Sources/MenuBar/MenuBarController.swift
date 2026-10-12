import AppKit
import Combine
import SwiftUI

/// The menu bar cup: left click opens the full panel when Side Notch is off;
/// right click opens quick actions.
@MainActor
final class MenuBarController {
    private weak var services: AppDelegate?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var rightClickMonitor: Any?

    init(services: AppDelegate) {
        self.services = services
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = MenuBarIcon.image
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(openPanel)
        // Orange icon while keep-awake is active.
        services.keepAwake.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                self?.statusItem?.button?.image = active ? MenuBarIcon.orangeImage : MenuBarIcon.image
            }
            .store(in: &cancellables)
        // Right-click: quick menu with Keep Awake + Cleaning Mode.
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, let button = self.statusItem?.button,
                let window = button.window
            else { return event }
            let loc = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            if button.frame.contains(loc) {
                self.showContextMenu()
                return nil
            }
            return event
        }
    }

    deinit {
        if let rightClickMonitor { NSEvent.removeMonitor(rightClickMonitor) }
    }

    @objc private func openPanel() {
        guard let button = statusItem?.button else { return }
        services?.toggleMenuBarPanel(from: button)
    }

    /// Right-click context menu: Keep Awake durations + Cleaning Mode.
    private func showContextMenu() {
        guard let services else { return }
        let menu = NSMenu()
        let keepAwake = services.keepAwake
        let cleaning = services.cleaning

        if keepAwake.isActive {
            let stop = NSMenuItem(title: "Stop Keep Awake", action: #selector(stopKeepAwake), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        } else {
            for (minutes, label) in [
                (30, "Keep Awake \u{2014} 30 min"), (60, "Keep Awake \u{2014} 1 hour"),
                (0, "Keep Awake \u{2014} Until stopped"),
            ] {
                let item = NSMenuItem(title: label, action: #selector(startKeepAwake(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = minutes
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let cleaningItem = NSMenuItem(
            title: cleaning.isActive ? "Stop Cleaning Mode" : "Start Cleaning Mode",
            action: #selector(toggleCleaningMode),
            keyEquivalent: ""
        )
        cleaningItem.target = self
        menu.addItem(cleaningItem)
        menu.addItem(.separator())
        let duoItem = NSMenuItem(title: "Show Side Notch", action: #selector(toggleSideNotch), keyEquivalent: "")
        duoItem.target = self
        duoItem.state = services.settings.sideNotchEnabled ? .on : .off
        menu.addItem(duoItem)
        let captureItem = NSMenuItem(
            title: "Hide from Screen Sharing", action: #selector(toggleHideFromCapture), keyEquivalent: "")
        captureItem.target = self
        captureItem.state = services.settings.hideFromScreenCapture ? .on : .off
        menu.addItem(captureItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quitItem = NSMenuItem(title: "Quit FreeTheNotch", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // Vorssaint's way: attach the menu to the status item for one click so
        // macOS presents it as a real status-bar menu (system appearance,
        // highlighted button). `popUp(in: button)` would inherit the menu
        // bar's dark vibrant appearance, even in light mode.
        guard let statusItem else { return }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { statusItem.menu = nil }
    }

    @objc private func startKeepAwake(_ sender: NSMenuItem) {
        if let minutes = sender.representedObject as? Int {
            services?.keepAwake.start(minutes: minutes)
        }
    }

    @objc private func stopKeepAwake() {
        services?.keepAwake.stop()
    }

    @objc private func toggleCleaningMode() {
        guard let cleaning = services?.cleaning else { return }
        if cleaning.isActive {
            cleaning.stop()
        } else {
            cleaning.start(lockTrackpad: services?.settings.cleaningLockTrackpad ?? true)
        }
    }

    @objc private func toggleSideNotch() {
        guard let settings = services?.settings else { return }
        settings.sideNotchEnabled.toggle()
    }

    /// Same setting as Settings → General → Privacy.
    @objc private func toggleHideFromCapture() {
        guard let settings = services?.settings else { return }
        settings.hideFromScreenCapture.toggle()
    }

    @objc private func openSettings() {
        services?.showSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Outside clicks

/// Calls `onOutside` for any mouse-down outside a floating UI. A global
/// monitor sees clicks in other apps; a local monitor sees clicks in this
/// app's other windows (notch, Side Notch), which the global one misses.
/// Used by the Side Notch popovers.
final class OutsideClickMonitor {
    private var global: Any?
    private var local: Any?

    /// `isInside(screenPoint, window)`: `window` is nil for clicks in other apps.
    func start(isInside: @escaping (NSPoint, NSWindow?) -> Bool, onOutside: @escaping () -> Void) {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { _ in
            if !isInside(NSEvent.mouseLocation, nil) { onOutside() }
        }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            if !isInside(NSEvent.mouseLocation, event.window) { onOutside() }
            return event
        }
    }

    func stop() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil
        local = nil
    }
}
