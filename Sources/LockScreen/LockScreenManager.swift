import AppKit
import Combine
import SwiftUI
import os

/// Shows widgets over the macOS lock screen (Atoll-style).
///
/// The widgets are a small transparent window on the main display, not a
/// second lock screen: a full-screen coloured window flashed, then sat on
/// the desktop for a few seconds after unlock. Like Atoll, the unlock
/// notification hides them immediately; a `CGSSessionScreenIsLocked` poll
/// and a screens-did-wake re-check are the fallbacks when that
/// notification is late or missing. A stretched lock notch (Atoll's
/// LockScreenLiveActivityWindowManager) replaces the hidden notch panels.
@MainActor
final class LockScreenManager {
    /// Why the widgets went away, for the log.
    private enum HideReason: String {
        case unlockNotification = "unlock-notification"
        case sessionPoll = "session-poll"
        case screensDidWake = "screens-did-wake"
    }

    /// The session poll's interval: the fallback for a late unlock notification.
    private static let sessionPollInterval: TimeInterval = 0.4
    /// The lock notch waits for the session to report locked, polling this
    /// often, and shows anyway after `lockNotchMaxPolls` polls (2 s).
    private static let lockNotchPollInterval: TimeInterval = 0.1
    private static let lockNotchMaxPolls = 20
    /// The artwork wallpaper waits this long for the switch, the player and
    /// the artwork to settle: each change restarts WallpaperAgent.
    private static let artworkDebounce: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(300)

    private weak var services: AppDelegate?
    private var observers: [NSObjectProtocol] = []
    private var isLocked = false
    private var lockPollTimer: Timer?
    /// The widget window (main display only), while locked.
    private var widgetWindow: NSWindow?
    /// This lock's artwork switch, for rebuilding the widget root on realign.
    private var currentArtworkSwitch: LockArtworkSwitch?
    private var artworkWatch: AnyCancellable?
    private var artworkClick: LockArtworkClickWindow?
    /// The lock notch window (SkyLight space), on the notch screen only.
    private var lockNotchWindow: NSWindow?
    private let lockNotchModel = LockNotchModel()
    private var lockNotchHideTask: Task<Void, Never>?
    /// Polls until the session is really locked, then shows the lock notch.
    /// Fixed delays are racy: the lock screen comes up at varying speeds.
    private var lockNotchPollTimer: Timer?

    init(services: AppDelegate) {
        self.services = services
    }

    func start() {
        let distributed = DistributedNotificationCenter.default()
        observers.append(
            distributed.addObserver(
                forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    Logger.lockScreen.notice("[FreeTheNotch] LOCK notification received")
                    self?.show()
                }
            })
        observers.append(
            distributed.addObserver(
                forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    Logger.lockScreen.notice("[FreeTheNotch] UNLOCK notification received")
                    self?.handleUnlockNotification()
                }
            })
        // No sessionDidBecomeActive fallback: it hid the widgets right after lock.

        // Lid close → open: re-check the canonical lock flag as soon as the
        // screens wake (Atoll realigns its lock panels on the same
        // notification), instead of relying only on an unlock notification
        // that may never arrive after sleep.
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isLocked else { return }
                    let locked = Self.sessionIsLocked()
                    Logger.lockScreen.notice(
                        "[FreeTheNotch] screens did wake, sessionLocked=\(locked ? 1 : 0, privacy: .public)")
                    if locked {
                        self.realignForScreenChange(reason: "screens-did-wake")
                    } else {
                        self.hide(.screensDidWake)
                    }
                }
            })
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.realignForScreenChange(reason: "screen-parameters") }
            })
    }

    /// Canonical lock flag. Frontmost-app checks lag the real unlock by a
    /// couple of seconds, which is the extra layer after typing the password.
    private static func sessionIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    // MARK: Lock and unlock

    private func show() {
        guard let services, !isLocked else {
            Logger.lockScreen.notice("[FreeTheNotch] lock event ignored (already locked)")
            return
        }
        isLocked = true
        Logger.lockScreen.notice("[FreeTheNotch] creating lock-screen widgets on the main display")
        // Atoll-style: hide the notch panels while locked (they are behind
        // the lock screen anyway); the lock notch stands in for them.
        services.setNotchHidden(true)
        services.system.refreshForLockScreen()
        startLockNotchPoll()
        // Artwork wallpaper for this lock: starts from the setting, the
        // player's artwork flips it.
        let artworkSwitch = LockArtworkSwitch(isOn: services.settings.lockArtworkWallpaper)
        currentArtworkSwitch = artworkSwitch
        watchArtworkWallpaper(artworkSwitch)
        // Main display only: macOS draws the clock and password field there,
        // so the widgets sit under that clock.
        if let screen = NSScreen.lockScreenMain {
            artworkClick = LockArtworkClickWindow(
                screen: screen, artworkSwitch: artworkSwitch, media: services.media)
            widgetWindow = makeWidgetWindow(on: screen, artworkSwitch: artworkSwitch)
        }
        Logger.lockScreen.notice(
            "[FreeTheNotch] lock-screen window on \(SkyLightLockSpace.shared.isAvailable ? "SkyLight" : "shielding level", privacy: .public)"
        )
        lockPollTimer?.invalidate()
        lockPollTimer = Timer.scheduledTimer(withTimeInterval: Self.sessionPollInterval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isLocked, !Self.sessionIsLocked() else { return }
                self.hide(.sessionPoll)
            }
        }
    }

    /// Atoll's screenUnlocked: trust the notification and hide right away.
    /// While CGSSessionScreenIsLocked can still say locked for up to ~0.4 s
    /// after a real unlock, so waiting for it only left the widgets on the
    /// desktop. The session poll and the wake re-check stay as fallbacks.
    private func handleUnlockNotification() {
        Logger.lockScreen.notice(
            "[FreeTheNotch] unlock notification, sessionLocked=\(Self.sessionIsLocked() ? 1 : 0, privacy: .public)")
        hide(.unlockNotification)
    }

    private func hide(_ reason: HideReason) {
        Logger.lockScreen.notice(
            "[FreeTheNotch] hide() called from \(reason.rawValue, privacy: .public), isLocked=\(self.isLocked ? 1 : 0, privacy: .public)"
        )
        guard isLocked else { return }
        isLocked = false
        lockPollTimer?.invalidate()
        lockPollTimer = nil
        lockNotchPollTimer?.invalidate()
        lockNotchPollTimer = nil
        Logger.lockScreen.notice("[FreeTheNotch] hiding lock-screen widgets")
        // Bring the notch panels back. The lock notch plays the unlock
        // (open shackle, then close); the panels do not repeat it.
        services?.setNotchHidden(false)
        transitionLockNotchToUnlocked()
        widgetWindow?.orderOut(nil)
        widgetWindow = nil
        currentArtworkSwitch = nil
        // Give the wallpaper back, crossfading on the desktop (Atoll's
        // desktop-level transition window).
        artworkWatch = nil
        artworkClick?.close()
        artworkClick = nil
        LockArtworkWallpaper.shared.restore(on: NSScreen.lockScreenMain, lockScreen: false)
    }

    // MARK: Widgets

    private func makeWidgetWindow(on screen: NSScreen, artworkSwitch: LockArtworkSwitch) -> NSWindow {
        let placement = LockScreenLayout.widgetPlacement(onScreenFrame: screen.frame)
        let window = NSWindow(contentRect: placement.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = false
        window.ignoresMouseEvents = false
        window.hidesOnDeactivate = false
        window.level = LockScreenLevel.widgets
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let hosting = NSHostingView(
            rootView: widgetRoot(artworkSwitch: artworkSwitch, controlsOffset: placement.controlsOffset))
        hosting.frame = NSRect(origin: .zero, size: placement.frame.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        // The window needs a number before SkyLight will adopt it.
        window.orderFrontRegardless()
        SkyLightLockSpace.shared.adopt(window)
        return window
    }

    private func widgetRoot(artworkSwitch: LockArtworkSwitch, controlsOffset: CGFloat) -> AnyView {
        guard let services else { return AnyView(EmptyView()) }
        return AnyView(
            LockScreenRoot(artworkSwitch: artworkSwitch, controlsOffset: controlsOffset)
                .appEnvironment(services))
    }

    /// Displays changed while locked (lid opened, a display plugged in or
    /// out, a new main display): moves the windows onto the current main
    /// display instead of leaving them beside or off the clock. Atoll's
    /// handleScreenGeometryChange (LockScreenPanelManager,
    /// LockScreenLiveActivityWindowManager), on the same two notifications.
    private func realignForScreenChange(reason: String) {
        guard isLocked else { return }
        let screen = NSScreen.lockScreenMain
        if let screen, let window = widgetWindow, let artworkSwitch = currentArtworkSwitch {
            let placement = LockScreenLayout.widgetPlacement(onScreenFrame: screen.frame)
            if window.frame != placement.frame {
                window.setFrame(placement.frame, display: true)
            }
            (window.contentView as? NSHostingView<AnyView>)?.rootView =
                widgetRoot(artworkSwitch: artworkSwitch, controlsOffset: placement.controlsOffset)
        }
        artworkClick?.relayout()
        realignLockNotch()
        Logger.lockScreen.notice(
            "[FreeTheNotch] lock-screen windows realigned (\(reason, privacy: .public)) on \(screen?.localizedName ?? "no screen", privacy: .public)"
        )
    }

    // MARK: Artwork wallpaper

    /// While locked: the artwork is the wallpaper when the switch is on and
    /// the player shows (playing, Media on); otherwise the user's own.
    /// Debounced, because each change restarts WallpaperAgent. Drives the
    /// widgets' `presentation`: hidden while switching, back in step with
    /// the clock and password field.
    private func watchArtworkWallpaper(_ artworkSwitch: LockArtworkSwitch) {
        guard let services else { return }
        let settings = services.settings
        let media = services.media
        artworkWatch = Publishers.CombineLatest3(artworkSwitch.$isOn, media.$isPlaying, media.$artwork)
            .debounce(for: Self.artworkDebounce, scheduler: DispatchQueue.main)
            .sink { [weak self] isOn, isPlaying, artwork in
                guard let self, self.isLocked else { return }
                let wallpaper = LockArtworkWallpaper.shared
                if isOn, isPlaying, settings.lockMedia, settings.mediaEnabled, let artwork,
                    let screen = NSScreen.lockScreenMain
                {
                    let started = wallpaper.apply(
                        artwork, screen: screen,
                        onShown: { artworkSwitch.presentation = .artwork },
                        onFailed: { artworkSwitch.presentation = .widgets })
                    // A new song while the artwork is up keeps the controls.
                    if started, artworkSwitch.presentation != .artwork { artworkSwitch.presentation = .switching }
                } else {
                    let wasUp = wallpaper.restore(
                        on: NSScreen.lockScreenMain, lockScreen: true,
                        onRevealed: { artworkSwitch.presentation = .widgets })
                    // Paused or switched off: the artwork controls go at
                    // once; the widgets return with the user's wallpaper.
                    artworkSwitch.presentation = wasUp ? .switching : .widgets
                }
            }
    }

    // MARK: Lock notch (Atoll's LockScreenLiveActivityWindowManager)

    /// Polls sessionIsLocked() until the lock screen is really up, then shows
    /// the notch. Shows it anyway after 2 s in case the session check misbehaves.
    private func startLockNotchPoll() {
        lockNotchPollTimer?.invalidate()
        var polls = 0
        lockNotchPollTimer = Timer.scheduledTimer(withTimeInterval: Self.lockNotchPollInterval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                polls += 1
                guard Self.sessionIsLocked() || polls >= Self.lockNotchMaxPolls else { return }
                self.lockNotchPollTimer?.invalidate()
                self.lockNotchPollTimer = nil
                if self.isLocked { self.showLockNotch() }
            }
        }
    }

    /// Shows the stretched lock notch (Atoll's showLocked) on the notch
    /// screen only.
    private func showLockNotch() {
        lockNotchHideTask?.cancel()
        hideLockNotchWindow()
        guard let screen = NSScreen.lockNotchScreen else { return }
        // Atoll's showLocked animation state.
        lockNotchModel.isLocked = true
        lockNotchModel.scale = LockNotchAnimation.hiddenScale
        lockNotchModel.opacity = 0
        let notchSize = LockNotchLayout.notchSize(on: screen)
        let frame = LockNotchLayout.windowFrame(
            size: LockNotchLayout.windowSize(notchSize: notchSize), onScreenFrame: screen.frame)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false
        window.hasShadow = false
        window.level = LockScreenLevel.notch
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.alphaValue = 0
        window.animationBehavior = .none
        let hostingView = NSHostingView(rootView: LockNotchView(model: lockNotchModel, notchSize: notchSize))
        hostingView.frame = CGRect(origin: .zero, size: window.frame.size)
        window.contentView = hostingView
        window.displayIfNeeded()
        window.orderFrontRegardless()
        SkyLightLockSpace.shared.adopt(window)
        window.alphaValue = 1
        lockNotchWindow = window
        Logger.lockScreen.notice("[FreeTheNotch] lock-notch shown on \(screen.localizedName, privacy: .public)")
        DispatchQueue.main.async {
            withAnimation(LockNotchAnimation.springIn) { self.lockNotchModel.scale = 1 }
            withAnimation(LockNotchAnimation.fadeIn) { self.lockNotchModel.opacity = 1 }
        }
    }

    /// On unlock: the shackle opens, holds, then the notch springs closed
    /// (Atoll's showUnlockAndScheduleHide).
    private func transitionLockNotchToUnlocked() {
        guard lockNotchWindow != nil else { return }
        lockNotchHideTask?.cancel()
        lockNotchModel.isLocked = false
        lockNotchModel.scale = 1
        lockNotchModel.opacity = 1
        lockNotchHideTask = Task { [weak self] in
            try? await Task.sleep(for: LockNotchAnimation.unlockedHold)
            guard let self, !Task.isCancelled else { return }
            withAnimation(LockNotchAnimation.springOut) { self.lockNotchModel.scale = LockNotchAnimation.hiddenScale }
            withAnimation(LockNotchAnimation.fadeOut) { self.lockNotchModel.opacity = 0 }
            try? await Task.sleep(for: LockNotchAnimation.outDuration)
            guard !Task.isCancelled else { return }
            self.hideLockNotchWindow()
        }
    }

    /// Atoll's handleScreenGeometryChange: re-centre the lock notch on the
    /// notch screen (else the main one).
    private func realignLockNotch() {
        guard let window = lockNotchWindow, let screen = NSScreen.lockNotchScreen else { return }
        let notchSize = LockNotchLayout.notchSize(on: screen)
        let target = LockNotchLayout.windowFrame(
            size: LockNotchLayout.windowSize(notchSize: notchSize), onScreenFrame: screen.frame)
        if window.frame != target {
            window.setFrame(target, display: true)
        }
        if let hosting = window.contentView as? NSHostingView<LockNotchView> {
            hosting.frame = CGRect(origin: .zero, size: window.frame.size)
            hosting.rootView = LockNotchView(model: lockNotchModel, notchSize: notchSize)
        }
    }

    private func hideLockNotchWindow() {
        lockNotchHideTask?.cancel()
        lockNotchHideTask = nil
        lockNotchWindow?.orderOut(nil)
        lockNotchWindow = nil
    }
}

// MARK: - Artwork switch

/// Whether the playing artwork is the wallpaper. One per lock, starting
/// from Settings → Lock Screen → Artwork wallpaper; a click on the player's
/// artwork flips it (LockArtworkWallpaper does the swap).
@MainActor
final class LockArtworkSwitch: ObservableObject {
    @Published var isOn: Bool
    /// What the widget window shows, kept in step with the wallpaper.
    @Published var presentation: LockArtworkPresentation = .widgets

    init(isOn: Bool) { self.isOn = isOn }
}

enum LockArtworkPresentation {
    /// The usual widgets.
    case widgets
    /// Nothing: the wallpaper is switching.
    case switching
    /// The artwork is the wallpaper: just LockScreenArtworkControls.
    case artwork
}

/// The lock screen's root: widgets, artwork controls, or nothing while the
/// wallpaper is switching (LockArtworkSwitch.presentation).
private struct LockScreenRoot: View {
    @ObservedObject var artworkSwitch: LockArtworkSwitch
    let controlsOffset: CGFloat

    var body: some View {
        LockScreenView(
            artworkMode: artworkSwitch.presentation == .artwork,
            hidesAll: artworkSwitch.presentation == .switching,
            artworkControlsOffset: controlsOffset,
            onArtworkTap: {
                // Answer the click at once: the controls go; the
                // rest follows the wallpaper switch.
                artworkSwitch.presentation = .switching
                artworkSwitch.isOn.toggle()
            })
    }
}
