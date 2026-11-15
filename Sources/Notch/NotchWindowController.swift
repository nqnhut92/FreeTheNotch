import AppKit
import Combine
import SwiftUI

// MARK: - Per-panel UI state

/// Collapsed/expanded state for one display's notch panel.
@MainActor
final class NotchPanelState: ObservableObject {
    @Published var isHovered = false
    @Published var isExpanded = false
    /// Which tool the open island is showing. Drives the shape height.
    @Published var page: NotchPage = .home
    /// False while the panel is hidden (screen locked, or a full-screen app
    /// on its display) or the displays sleep: nothing on it needs to animate.
    @Published var isOnScreen = true
}

// MARK: - Window controller

/// Owns one borderless panel per display, anchored top-center.
///
/// The panel is always the full expanded size; only the SwiftUI shape
/// morphs. Hover is detected by polling `NSEvent.mouseLocation` (like Atoll)
/// rather than an NSTrackingArea, which is unreliable for a non-responder
/// owner. Hovering (after the configured delay) opens the island; moving the
/// pointer away closes it.
@MainActor
final class NotchWindowController: NSObject {
    /// Everything that belongs to one display's panel. Dropped as a whole
    /// on rebuild, which also cancels its subscriptions.
    private struct PanelEntry {
        let panel: NSPanel
        let state: NotchPanelState
        let hosting: NotchHostingView<AnyView>
        let screen: NSScreen
        var hoverTimer: Timer?
        var hitSizeSubscription: AnyCancellable?
    }

    private weak var services: AppDelegate?
    private var entries: [ObjectIdentifier: PanelEntry] = [:]
    private var hoverPollTimer: Timer?
    private var scopeObserver: AnyCancellable?
    private var tabObserver: AnyCancellable?
    private var sleepObservers: [AnyCancellable] = []
    private var hudObserver: AnyCancellable?
    private var isHiddenWhileLocked = false
    /// Displays showing a full-screen app, where the notch stays out of the
    /// way (Settings → General → Hide in full screen).
    private var fullScreenDisplays: Set<CGDirectDisplayID> = []
    private var areScreensAsleep = false

    /// Atoll's level: above the menu bar, below pop-up menus.
    static let windowLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    /// Fixed window width (fits the expanded panel).
    static let windowWidth: CGFloat = 740
    /// Forgiveness padding around the island for hover detection.
    private static let hoverPadding: CGFloat = 10
    /// Room under the tallest body, inside the fixed window.
    private static let bottomSlack: CGFloat = 24

    init(services: AppDelegate) {
        self.services = services
        super.init()
        rebuildPanels()
        startHoverPolling()
        // Settings → Show on: the target screens change with the scope.
        scopeObserver = services.settings.$displayScopeRaw
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildPanels() }
        tabObserver = Publishers.CombineLatest(
            services.settings.$hiddenNotchTabsRaw, services.settings.$notchTabOrderRaw
        )
        .dropFirst()
        .receive(on: DispatchQueue.main)
        .sink { [weak self, weak services] _ in
            guard let self, let services else { return }
            let visible = services.settings.visibleNotchTabs
            for entry in self.entries.values where !visible.contains(entry.state.page) {
                entry.state.page = visible.first ?? .home
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            (NSWorkspace.screensDidSleepNotification, true),
            (NSWorkspace.screensDidWakeNotification, false),
        ].map { name, isAsleep in
            workspace.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.setScreensAsleep(isAsleep) }
        }
        // The volume and brightness HUDs replace the system's own overlay,
        // so they still show over a full-screen app.
        hudObserver = services.hud.$isHUDVisible
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.fullScreenDisplays.isEmpty else { return }
                self.applyVisibility()
            }
    }

    private func setScreensAsleep(_ isAsleep: Bool) {
        areScreensAsleep = isAsleep
        applyVisibility()
    }

    deinit {
        hoverPollTimer?.invalidate()
    }

    // MARK: Panel lifecycle

    private var targetScreens: [NSScreen] {
        let screens = NSScreen.screens
        guard let services else { return screens }
        // The built-in display shows nothing with the lid closed; the notch
        // must not fall back to an external display.
        return DisplayGeometry.targetScreens(for: services.settings.displayScope, in: screens)
    }

    func rebuildPanels() {
        for entry in entries.values {
            entry.panel.orderOut(nil)
            entry.hoverTimer?.invalidate()
        }
        entries.removeAll()
        for screen in targetScreens { makePanel(for: screen) }
    }

    /// Fixed window frame: always the full expanded size, top-center.
    private func fixedFrame(for screen: NSScreen, settings: SettingsStore) -> NSRect {
        let notchHeight = DisplayGeometry.collapsedSize(for: screen).height
        let height = notchHeight + NotchPage.tallest + Self.bottomSlack
        return NSRect(
            x: screen.frame.midX - Self.windowWidth / 2,
            y: screen.frame.maxY - height,
            width: Self.windowWidth,
            height: height)
    }

    /// Hide/show all notch panels (Atoll-style lock behavior).
    func setPanelsHidden(_ hidden: Bool) {
        isHiddenWhileLocked = hidden
        applyVisibility()
    }

    /// Hides the panels on these displays while they show a full-screen app
    /// (Atoll's `hideOnClosed`, per screen).
    func setFullScreenDisplays(_ displays: Set<CGDirectDisplayID>) {
        guard displays != fullScreenDisplays else { return }
        fullScreenDisplays = displays
        applyVisibility()
    }

    private func isOverFullScreenApp(_ screen: NSScreen) -> Bool {
        screen.displayID.map(fullScreenDisplays.contains) ?? false
    }

    private func isHidden(on screen: NSScreen) -> Bool {
        if isHiddenWhileLocked { return true }
        return isOverFullScreenApp(screen) && services?.hud.isHUDVisible != true
    }

    /// Orders every panel in or out to match the lock state and its
    /// display's full-screen state.
    private func applyVisibility() {
        for id in Array(entries.keys) { applyVisibility(to: id) }
    }

    private func applyVisibility(to id: ObjectIdentifier) {
        guard let entry = entries[id] else { return }
        let hidden = isHidden(on: entry.screen)
        let isOnScreen = !hidden && !areScreensAsleep
        if entry.state.isOnScreen != isOnScreen { entry.state.isOnScreen = isOnScreen }
        if hidden {
            collapse(id)
            entry.panel.alphaValue = 0
            entry.panel.orderOut(nil)
        } else if !entry.panel.isVisible {
            entry.panel.alphaValue = 1
            entry.panel.orderFrontRegardless()
        }
    }

    /// Closes the island and forgets the hover, for a panel going away.
    private func collapse(_ id: ObjectIdentifier) {
        entries[id]?.hoverTimer?.invalidate()
        entries[id]?.hoverTimer = nil
        guard let state = entries[id]?.state else { return }
        if state.isHovered { state.isHovered = false }
        if state.isExpanded { state.isExpanded = false }
    }

    private func makePanel(for screen: NSScreen) {
        guard let services else { return }
        let state = NotchPanelState()
        state.page = services.settings.visibleNotchTabs.first ?? .home
        state.isOnScreen = !isHidden(on: screen) && !areScreensAsleep

        let frame = fixedFrame(for: screen, settings: services.settings)
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        // isFloatingPanel resets the level to .floating, under the menu bar:
        // set it first, then the level (Atoll's order).
        panel.isFloatingPanel = true
        panel.level = Self.windowLevel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let rootView = NotchRootView(
            screen: screen, panelState: state,
            openSettings: { [weak services] in services?.showSettings() }
        )
        .environmentObject(services.settings)
        .environmentObject(services.media)
        .environmentObject(services.clipboard)
        .environmentObject(services.aiUsage)
        .environmentObject(services.aiActivities)
        .environmentObject(services.bluetooth)
        .environmentObject(services.keepAwake)
        .environmentObject(services.cleaning)
        .environmentObject(services.calendar)
        .environmentObject(services.system)
        .environmentObject(services.timerStore)
        .environmentObject(services.hud)
        .environmentObject(services.capsLock)
        .environmentObject(services.batteryHUD)
        .environmentObject(services.deviceSync)

        let hosting = NotchHostingView(rootView: AnyView(rootView))
        hosting.autoresizingMask = [.width, .height]
        // SwiftUI otherwise insets the shape by the menu-bar / notch safe
        // area, which slides the island under the menu bar.
        hosting.safeAreaRegions = []
        hosting.sizingOptions = []
        hosting.hitSize = DisplayGeometry.collapsedSize(for: screen)

        // The window is created at the origin and moved to the top only after
        // it has its content view (Atoll's order): a window created over the
        // menu bar gets a content view shrunk to exclude that band.
        panel.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: panel.frame.size)
        pin(panel, to: screen, settings: services.settings)

        var entry = PanelEntry(panel: panel, state: state, hosting: hosting, screen: screen)
        entry.hitSizeSubscription = hitSizeTriggers(for: state, services: services)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak hosting, weak state] in
                guard let self, let hosting, let state else { return }
                self.applyHitSize(hosting: hosting, screen: screen, state: state)
            }
        entries[ObjectIdentifier(screen)] = entry

        if isHidden(on: screen) {
            panel.alphaValue = 0
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Everything that changes the island's size, so the hit-test rect
    /// follows the visible shape: `NotchPage.bodyHeight` inputs while open,
    /// the live activities (`NotchRootView.widensForLiveActivity`) and the
    /// HUDs while closed.
    private func hitSizeTriggers(for state: NotchPanelState, services: AppDelegate) -> AnyPublisher<Void, Never> {
        Publishers.MergeMany([
            state.$isExpanded.asTrigger,
            state.$page.asTrigger,
            services.media.$isPlaying.asTrigger,
            services.media.$upNext.asTrigger,
            services.media.$title.asTrigger,
            services.settings.$homeQuote.removeDuplicates().asTrigger,
            services.settings.$homeBatteryStrip.removeDuplicates().asTrigger,
            services.settings.$capsLockEnabled.removeDuplicates().asTrigger,
            services.settings.$mediaEnabled.removeDuplicates().asTrigger,
            services.calendar.$monthCursor.asTrigger,
            services.capsLock.$isCapsLockActive.removeDuplicates().asTrigger,
            services.hud.$isHUDVisible.asTrigger,
            services.aiActivities.$activities.asTrigger,
            services.aiUsage.$quotaAlert.asTrigger,
            services.batteryHUD.$activeKind.asTrigger,
            services.settings.$deviceSyncEnabled.removeDuplicates().asTrigger,
            services.deviceSync.$isSyncing.asTrigger,
            services.deviceSync.$labelWidth.asTrigger,
            // The timer widens the island through isRunning and
            // remainingSeconds together; objectWillChange fires before the
            // change and receive(on:) delivers after it.
            services.timerStore.objectWillChange.asTrigger,
        ])
        .eraseToAnyPublisher()
    }

    /// Hit-test rect mirrors NotchRootView's shape math.
    private func applyHitSize(hosting: NotchHostingView<AnyView>, screen: NSScreen, state: NotchPanelState) {
        guard let services else { return }
        let notchSize = DisplayGeometry.collapsedSize(for: screen)
        if state.isExpanded {
            hosting.hitSize = CGSize(
                width: DisplayGeometry.expandedWidth,
                height: notchSize.height
                    + NotchPage.bodyHeight(
                        for: state.page, media: services.media,
                        settings: services.settings, calendar: services.calendar))
        } else if let kind = services.batteryHUD.activeKind {
            hosting.hitSize = kind.size(notchWidth: notchSize.width, notchHeight: notchSize.height)
        } else if services.aiUsage.quotaAlert != nil, !services.hud.isHUDVisible {
            hosting.hitSize = DisplayGeometry.aiQuotaHUDSize(notchWidth: notchSize.width, notchHeight: notchSize.height)
        } else if !services.hud.isHUDVisible, isShowingDeviceSync {
            hosting.hitSize = CGSize(
                width: DeviceSyncActivity.islandWidth(
                    notchWidth: notchSize.width, labelWidth: services.deviceSync.labelWidth),
                height: notchSize.height)
        } else if services.hud.isHUDVisible || isLiveActivity {
            hosting.hitSize = CGSize(
                width: DisplayGeometry.liveActivityWidth(notchWidth: notchSize.width),
                height: notchSize.height)
        } else {
            hosting.hitSize = notchSize
        }
    }

    private var isShowingDeviceSync: Bool {
        guard let services else { return false }
        return NotchRootView.showsDeviceSync(
            settings: services.settings, capsLock: services.capsLock, deviceSync: services.deviceSync)
    }

    private var isLiveActivity: Bool {
        guard let services else { return false }
        return NotchRootView.widensForLiveActivity(
            settings: services.settings, media: services.media, capsLock: services.capsLock,
            timerStore: services.timerStore, aiActivities: services.aiActivities)
    }

    // MARK: Hover polling (Atoll-style)

    private func startHoverPolling() {
        guard hoverPollTimer == nil else { return }
        hoverPollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollHover() }
        }
    }

    /// Keep the panel's top edge on the screen's top edge. AppKit will
    /// otherwise drop it below the menu bar after ordering front.
    /// Also re-asserts the contentView frame: AppKit likes to shrink it to
    /// exclude the menu-bar band, which makes band clicks miss hit-testing.
    private func pin(_ panel: NSPanel, to screen: NSScreen, settings: SettingsStore) {
        let frame = fixedFrame(for: screen, settings: settings)
        if abs(panel.frame.maxY - screen.frame.maxY) > 0.5
            || abs(panel.frame.midX - screen.frame.midX) > 0.5
            || abs(panel.frame.width - frame.width) > 0.5
            || abs(panel.frame.height - frame.height) > 0.5
        {
            panel.setFrame(frame, display: true)
        }
        if let contentView = panel.contentView,
            abs(contentView.frame.height - panel.frame.height) > 0.5
                || abs(contentView.frame.width - panel.frame.width) > 0.5
        {
            contentView.frame = NSRect(origin: .zero, size: panel.frame.size)
        }
    }

    private func pollHover() {
        guard let services else { return }
        let mouse = NSEvent.mouseLocation
        for (id, entry) in entries {
            // No island to open over a full-screen app, even while a HUD
            // has the panel up.
            if isOverFullScreenApp(entry.screen) { continue }
            let panel = entry.panel
            let state = entry.state
            pin(panel, to: entry.screen, settings: services.settings)
            // The visible shape is top-centered in the fixed window.
            let hitSize = entry.hosting.hitSize
            var hitRect = NSRect(
                x: panel.frame.midX - hitSize.width / 2,
                y: panel.frame.maxY - hitSize.height,
                width: hitSize.width,
                height: hitSize.height)
            hitRect = hitRect.insetBy(dx: -Self.hoverPadding, dy: 0)
            hitRect.size.height += Self.hoverPadding
            // An open popover (output picker) is its own window; keep the
            // island open while it shows, like Atoll.
            let hovering =
                hitRect.contains(mouse)
                || (state.isExpanded && NotchPopoverTracker.shared.isOpen)
            guard hovering != state.isHovered else { continue }
            state.isHovered = hovering
            if hovering {
                scheduleExpand(id: id)
            } else {
                entries[id]?.hoverTimer?.invalidate()
                entries[id]?.hoverTimer = nil
                state.isExpanded = false
                // Atoll's close(): back to the first tab unless "Remember last tab".
                if !services.settings.rememberLastTab {
                    state.page = services.settings.visibleNotchTabs.first ?? .home
                }
            }
        }
    }

    private func scheduleExpand(id: ObjectIdentifier) {
        guard let services else { return }
        entries[id]?.hoverTimer?.invalidate()
        entries[id]?.hoverTimer = Timer.scheduledTimer(
            withTimeInterval: services.settings.hoverDelay,
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let state = self?.entries[id]?.state, state.isHovered else { return }
                state.isExpanded = true
            }
        }
    }
}

extension Publisher where Failure == Never {
    /// The event without its value, for merging unrelated publishers.
    fileprivate var asTrigger: AnyPublisher<Void, Never> {
        map { _ in () }.eraseToAnyPublisher()
    }
}
