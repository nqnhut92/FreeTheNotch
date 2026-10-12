import AppKit
import Darwin
import os

/// Hides the blink when the wallpaper changes. `killall WallpaperAgent`
/// blanks the wallpaper for a moment and the respawned agent shows the new
/// one within a second; a cover timed to go up after the respawn is too
/// late and flashes. So the cover goes up first: a still of the artwork,
/// fading in over the old wallpaper (to the artwork) or up at once (back:
/// it matches the screen); then the swap and the kill; then the cover
/// lifts.
///
/// To the artwork it lifts a beat after the respawn. Back to the user's
/// wallpaper on the lock screen that is too early: loginwindow keeps the
/// killed agent's last picture (the artwork) and swaps it later with its
/// own crossfade. So there the cover crossfades at once to a still of the
/// user's wallpaper (macOS's export, ArtworkWallpaperFiles) and lifts as
/// soon as macOS has re-exported that wallpaper, ~1 s after the respawn:
/// by then the lock screen shows it. TECHNICAL_DESIGN §3.7 has the details.
///
/// Lock screen: in our SkyLight space, under the widgets and lock notch;
/// it hides macOS's clock and password field while up. After unlock:
/// Atoll's desktop level (`showWallpaperTransition`). Click-through, never
/// left up.
@MainActor
final class LockWallpaperTransition {
    /// Cover fade-in going to the artwork.
    static let fadeIn: TimeInterval = 0.35
    /// After the respawn, before the cover lifts: time for the new agent to
    /// draw (to the artwork; back to a picture on the desktop or without a
    /// saved still).
    nonisolated static let holdToArtwork: TimeInterval = 0.7
    nonisolated static let holdToUserWallpaper: TimeInterval = 0.8
    /// Back to an aerial without a still of it (no export to read): the
    /// cover lifts this long after the respawn. loginwindow still shows the
    /// artwork for a while after that.
    nonisolated static let holdToAerial: TimeInterval = 2.5
    /// Artwork → still of the user's wallpaper, on the way back.
    static let stillFade: TimeInterval = 0.5
    private static let fadeOutDuration: TimeInterval = 0.5
    /// How often `uncover` looks for the respawned agent, and how long it
    /// waits at most.
    private static let respawnPollInterval: TimeInterval = 0.05
    private static let respawnTimeout: TimeInterval = 2

    private var window: NSWindow?
    private var windowIsLockScreen = false
    private let imageLayer = CALayer()
    private var poll: Timer?
    /// Bumped by every `cover` and `dismiss`; older pending steps stop.
    private(set) var generation = 0

    /// WallpaperAgent's process IDs, straight from the kernel (libproc): a
    /// new one means it has respawned. NSWorkspace.runningApplications lags
    /// behind it.
    nonisolated static func agentPIDs() -> Set<pid_t> {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        var name = [CChar](repeating: 0, count: 256)
        var result = Set<pid_t>()
        for pid in pids.prefix(max(0, count)) where pid > 0 {
            if proc_name(pid, &name, UInt32(name.count)) > 0, String(cString: name) == "WallpaperAgent" {
                result.insert(pid)
            }
        }
        return result
    }

    /// Puts the cover up (fading in over `fadeIn`, or at once), then calls
    /// `then` once it fully covers the screen.
    func cover(
        with image: NSImage, on screen: NSScreen, lockScreen: Bool, fadeIn: TimeInterval,
        then: @escaping @MainActor () -> Void
    ) {
        generation += 1
        poll?.invalidate()
        poll = nil
        let window = prepareWindow(on: screen, lockScreen: lockScreen)
        let wasShowing = window.isVisible && window.alphaValue > 0.99
        imageLayer.removeAllAnimations()
        if wasShowing, fadeIn > 0 {
            // A cover already up (next song): crossfade the picture.
            let fade = CATransition()
            fade.duration = fadeIn
            fade.type = .fade
            imageLayer.add(fade, forKey: "contents")
        }
        imageLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        if wasShowing {
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeIn) { then() }
            return
        }
        window.alphaValue = fadeIn > 0 ? 0 : 1
        window.orderFrontRegardless()
        if lockScreen { SkyLightLockSpace.shared.adopt(window) }
        guard fadeIn > 0 else {
            then()
            return
        }
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = fadeIn
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 1
            }, completionHandler: { MainActor.assumeIsolated { then() } })
    }

    /// Call right after the kill. Once WallpaperAgent has respawned (a PID
    /// not in `before`; 2 s at most) and `hold` has passed, lifts the cover;
    /// `onUncover` as it starts. Nil `before`: lift now.
    func uncover(respawnedFrom before: Set<pid_t>?, hold: TimeInterval, onUncover: (() -> Void)? = nil) {
        let current = generation
        poll?.invalidate()
        let lift = { [weak self] in
            guard let self, self.generation == current else { return }
            Logger.artworkWallpaper.notice("[FreeTheNotch] artwork wallpaper: cover lifting")
            onUncover?()
            self.fadeOut(generation: current)
        }
        guard let before else {
            lift()
            return
        }
        let started = Date()
        poll = Timer.scheduledTimer(withTimeInterval: Self.respawnPollInterval, repeats: true) { [weak self] timer in
            // Scheduled on the main run loop.
            MainActor.assumeIsolated {
                guard let self, self.generation == current else {
                    timer.invalidate()
                    return
                }
                let respawned = !Self.agentPIDs().subtracting(before).isEmpty
                guard respawned || Date().timeIntervalSince(started) > Self.respawnTimeout else { return }
                timer.invalidate()
                self.poll = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + (respawned ? hold : 0), execute: lift)
            }
        }
    }

    /// Crossfades the cover's picture, if no newer switch has started.
    func crossfade(to image: NSImage, duration: TimeInterval, generation expected: Int) {
        guard generation == expected, window?.isVisible == true else { return }
        let fade = CATransition()
        fade.duration = duration
        fade.type = .fade
        imageLayer.add(fade, forKey: "contents")
        imageLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Lifts the cover, if no newer switch has started.
    func lift(generation expected: Int) {
        guard generation == expected else { return }
        Logger.artworkWallpaper.notice("[FreeTheNotch] artwork wallpaper: cover lifting")
        fadeOut(generation: expected)
    }

    /// Unlocked: a lock-screen cover still waiting for macOS goes now
    /// (no delayed hide after unlock).
    func dismissLockScreenCover() {
        guard windowIsLockScreen, window?.isVisible == true else { return }
        dismiss()
    }

    /// Removes the cover at once.
    func dismiss() {
        generation += 1
        poll?.invalidate()
        poll = nil
        window?.orderOut(nil)
    }

    private func fadeOut(generation current: Int) {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = Self.fadeOutDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 0
            },
            completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    // Not if a newer switch has put the cover back up meanwhile.
                    guard let self, self.generation == current else { return }
                    window.orderOut(nil)
                }
            })
    }

    private func prepareWindow(on screen: NSScreen, lockScreen: Bool) -> NSWindow {
        if let window, windowIsLockScreen == lockScreen {
            window.setFrame(screen.frame, display: false)
            imageLayer.frame = CGRect(origin: .zero, size: screen.frame.size)
            return window
        }
        window?.orderOut(nil)
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Lock screen: under the lock notch (+0) and the widgets (+1).
        // Desktop: Atoll's level, above the wallpaper and under every window.
        window.level = lockScreen ? LockScreenLevel.cover : LockScreenLevel.desktopCover
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.frame = view.bounds
        view.layer?.addSublayer(imageLayer)
        window.contentView = view
        self.window = window
        windowIsLockScreen = lockScreen
        return window
    }
}
