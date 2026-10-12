import AppKit
import SwiftUI
import os

// MARK: - Entry point

@main
struct FreeTheNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // SwiftUI needs a scene, but Settings is AppDelegate's own window:
        // the app menu's Settings item (⌘,) opens that one, so there is
        // never a second, unmanaged settings window.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings\u{2026}") { appDelegate.showSettings() }
                    .keyboardShortcut(",")
            }
        }
    }
}

// MARK: - App delegate: owns every long-lived controller

/// The app is an LSUIElement agent (no Dock icon). All UI lives in floating
/// panels owned here: the notch windows, the menu-bar monitor, lock-screen
/// widgets, and the feature modules.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// SwiftUI's app lifecycle does not put this object in `NSApp.delegate`,
    /// so the gear button cannot cast its way here.
    static weak var shared: AppDelegate?

    let settings = SettingsStore()
    let media = MediaRemoteAdapter()
    let clipboard = ClipboardManager()
    let bluetooth = BluetoothMonitor()
    let keepAwake = KeepAwakeController()
    let cleaning = CleaningModeController()
    let smoothScroll = SmoothScrollService()
    let calendar = CalendarStore()
    let system = SystemMonitor()
    let timerStore = TimerStore()
    let hud = HUDController()
    let batteryHUD = BatteryHUDController()
    let disks = DiskMonitor()
    let processes = ProcessMonitor()
    let capsLock = CapsLockManager.shared
    let speedTest = SpeedTest()
    lazy var aiUsage = AIUsageMonitor(settings: settings)
    lazy var aiActivities = AIActivityMonitor(settings: settings)

    private var notchController: NotchWindowController?
    func toggleMenuBarPanel(from anchor: NSView) {
        sideNotch?.toggleMenuBarPanel(from: anchor)
    }

    private var menuBarController: MenuBarController?
    private var sideNotch: SideNotchWindowController?
    private var lockScreenManager: LockScreenManager?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)
        // A lock-screen artwork wallpaper left by a crash or force quit.
        LockArtworkWallpaper.shared.recoverAfterCrash()
        #if DEBUG
            MainThreadWatchdog.shared.start()
        #endif

        notchController = NotchWindowController(services: self)
        menuBarController = MenuBarController(services: self)
        sideNotch = SideNotchWindowController(services: self)
        lockScreenManager = LockScreenManager(services: self)
        lockScreenManager?.start()

        clipboard.configure(with: settings)
        QuoteStore.shared.configure(with: settings)
        keepAwake.configure(with: settings)
        smoothScroll.configure(with: settings, cleaning: cleaning)
        clipboard.startMonitoring()
        bluetooth.startMonitoring()
        media.startMonitoring()
        hud.start(settings: settings)
        batteryHUD.start(settings: settings)
        ScreenCaptureVisibility.shared.start(settings: settings)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.notchController?.rebuildPanels() }
        }
    }

    /// Atoll-style: hide the notch panels while the screen is locked.
    func setNotchHidden(_ hidden: Bool) {
        notchController?.setPanelsHidden(hidden)
        sideNotch?.setHidden(hidden)
    }

    /// Opens Settings in a plain AppKit window: reliable for an LSUIElement
    /// agent app with no main menu.
    func showSettings() {
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        // Dock icon while Settings is open, like Vorssaint
        // (WindowActivationPolicy.retain in AppDelegate.showSettings).
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsView.size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        // Reused after closing: a code-created window is released on close by
        // default, which would leave `settingsWindow` dangling.
        window.isReleasedWhenClosed = false
        window.title = "FreeTheNotch Settings"
        // The Lock Screen page's preview draws the real widgets.
        window.contentView = NSHostingView(rootView: SettingsView().appEnvironment(self))
        window.center()
        window.delegate = self
        return window
    }

    /// Dock icon click: bring Settings back, also from the Dock's minimized
    /// windows (it is the only Dock-backed window).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let settingsWindow, settingsWindow.isVisible || settingsWindow.isMiniaturized { showSettings() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        smoothScroll.shutdown()
        settings.flush()
        LockArtworkWallpaper.shared.restoreNow()
        clipboard.handleAppQuit()
        clipboard.stopMonitoring()
        keepAwake.stop()
    }
}

extension AppDelegate: NSWindowDelegate {
    /// Back to an agent app with no Dock icon (Vorssaint's
    /// WindowActivationPolicy.release in windowWillClose).
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}

extension View {
    /// The shared services the lock-screen widgets and Settings read from
    /// the environment.
    func appEnvironment(_ services: AppDelegate) -> some View {
        environmentObject(services.settings)
            .environmentObject(services.smoothScroll)
            .environmentObject(services.aiUsage)
            .environmentObject(services.aiActivities)
            .environmentObject(services.system)
            .environmentObject(services.media)
            .environmentObject(services.timerStore)
            .environmentObject(services.bluetooth)
            .environmentObject(services.calendar)
    }
}

#if DEBUG
    /// Debug-only hang catcher. A dedicated thread pings the main thread
    /// every second; if it does not answer for 3 s, `/usr/bin/sample`
    /// records every thread's stack to
    /// ~/Library/Logs/FreeTheNotch/hang-<time>.txt (one sample per hang),
    /// for stalls the unified log cannot explain.
    final class MainThreadWatchdog: @unchecked Sendable {
        static let shared = MainThreadWatchdog()

        private static let pingInterval: TimeInterval = 1
        private static let stallThreshold: TimeInterval = 3
        private static let sampleSeconds = 3

        private let lock = NSLock()
        private var lastPong = Date()
        private var sampledThisHang = false
        private var thread: Thread?

        func start() {
            guard thread == nil else { return }
            let thread = Thread { [weak self] in self?.loop() }
            thread.name = "FreeTheNotch.watchdog"
            thread.qualityOfService = .utility
            self.thread = thread
            thread.start()
        }

        private func loop() {
            while true {
                Thread.sleep(forTimeInterval: Self.pingInterval)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.lock.withLock {
                        self.lastPong = Date()
                        self.sampledThisHang = false
                    }
                }
                let (stalled, shouldSample) = lock.withLock { () -> (TimeInterval, Bool) in
                    let stalled = Date().timeIntervalSince(lastPong)
                    let shouldSample = stalled >= Self.stallThreshold && !sampledThisHang
                    if shouldSample { sampledThisHang = true }
                    return (stalled, shouldSample)
                }
                if shouldSample { sample(stalled: stalled) }
            }
        }

        private func sample(stalled: TimeInterval) {
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/FreeTheNotch", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let file = dir.appendingPathComponent("hang-\(stamp).txt")
            Logger.app.notice(
                "[FreeTheNotch] main thread stalled \(stalled, format: .fixed(precision: 1), privacy: .public)s; sampling to \(file.path, privacy: .public)"
            )
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            task.arguments = [
                String(ProcessInfo.processInfo.processIdentifier), String(Self.sampleSeconds), "-file", file.path,
            ]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
    }
#endif
