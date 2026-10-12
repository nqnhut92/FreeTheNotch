// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// DynamicIsland/managers/FullScreenArtworkWindowManager.swift. The file work
// is in ArtworkWallpaperFiles. Changes from Atoll:
// - A backup left behind by a crash or force quit is restored at the next
//   launch (`recoverAfterCrash`), and on quit (`restoreNow`).
// - The image is `LockArtworkImage` (sharp artwork over a blurred fill)
//   instead of the raw artwork, which macOS stretched and pixelated.
// - File work and the WallpaperAgent restart run on a serial queue, off the
//   main thread. No live/video wallpaper, overlays or click receiver.
// - LockWallpaperTransition covers the switch both ways; Atoll restores
//   with no transition.

import AppKit
import os

/// Swaps the macOS wallpaper (desktop and lock screen) for the playing
/// artwork, and puts the user's back. Main-thread state; the files are
/// touched on `queue` only.
@MainActor
final class LockArtworkWallpaper {
    static let shared = LockArtworkWallpaper(files: .live)

    /// How often `waitForExport` looks for macOS's re-export, and how long
    /// it waits at most.
    private nonisolated static let exportPollInterval: TimeInterval = 0.1
    private nonisolated static let exportTimeout: TimeInterval = 4

    private let queue = DispatchQueue(label: "com.freethenotch.artwork-wallpaper")
    private let files: ArtworkWallpaperFiles
    private let transition = LockWallpaperTransition()
    /// Bumped by every apply and restore; a pending apply step that finds
    /// it changed was superseded and stops before touching the wallpaper.
    private let applyGeneration = ArtworkApplyGeneration()
    /// Artwork currently applied, so a repeat does nothing.
    private var appliedArtwork: ObjectIdentifier?
    /// The artwork is (being) put up.
    private var isUp = false
    /// The artwork wallpaper as shown: the cover on the way back.
    private var currentCover: NSImage?

    init(files: ArtworkWallpaperFiles) {
        self.files = files
    }

    /// Puts the artwork up: fades a still of it in over the screen, swaps
    /// the real wallpaper (WallpaperAgent restart) under it, and lifts it
    /// once the new agent is drawing. `onShown` when the artwork covers the
    /// screen, `onFailed` if nothing changed. Returns false if this artwork
    /// is already up or being put up.
    @discardableResult
    func apply(
        _ artwork: NSImage, screen: NSScreen,
        onShown: @escaping () -> Void, onFailed: @escaping () -> Void
    ) -> Bool {
        let id = ObjectIdentifier(artwork)
        guard appliedArtwork != id,
            let cgArt = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return false }
        appliedArtwork = id
        let generation = applyGeneration.next()
        let canvas = LockArtworkImage.canvas(pointSize: screen.frame.size, scale: screen.backingScaleFactor)
        let pointSize = screen.frame.size
        let files = files
        let applyGeneration = applyGeneration
        // Back on the main thread with the rendered image: cover, then swap.
        let showCover: @MainActor (CGImage, URL) -> Void = { [self] image, imageURL in
            // Superseded (next song, switch off, unlock) while rendering.
            guard applyGeneration.isCurrent(generation) else { return }
            isUp = true
            let cover = NSImage(cgImage: image, size: pointSize)
            currentCover = cover
            transition.cover(with: cover, on: screen, lockScreen: true, fadeIn: LockWallpaperTransition.fadeIn) {
                [self] in
                // Superseded during the fade-in: restore() has already run
                // (with nothing to restore yet) and owns the cover.
                guard applyGeneration.isCurrent(generation) else { return }
                onShown()
                queue.async { [self] in
                    swapInArtwork(imageURL, generation: generation, files: files, applyGeneration: applyGeneration)
                }
            }
        }
        queue.async {
            guard let image = LockArtworkImage.render(cgArt, canvas: canvas),
                let imageURL = files.writePNG(image)
            else {
                Logger.artworkWallpaper.error("[FreeTheNotch] artwork wallpaper: render failed")
                DispatchQueue.main.async { onFailed() }
                return
            }
            DispatchQueue.main.async { showCover(image, imageURL) }
        }
        return true
    }

    /// Queue only: backs up, patches the plist and restarts WallpaperAgent,
    /// then has the cover lift.
    private nonisolated func swapInArtwork(
        _ imageURL: URL, generation: Int, files: ArtworkWallpaperFiles, applyGeneration: ArtworkApplyGeneration
    ) {
        // A restore queued behind this block would find no backup yet.
        guard applyGeneration.isCurrent(generation) else { return }
        guard files.backUpIfNeeded() else {
            Logger.artworkWallpaper.error(
                "[FreeTheNotch] artwork wallpaper: no backup, not touching the wallpaper")
            DispatchQueue.main.async { self.transition.uncover(respawnedFrom: nil, hold: 0) }
            return
        }
        let agentsBefore = LockWallpaperTransition.agentPIDs()
        guard files.patchPlist(imageURL: imageURL) else {
            Logger.artworkWallpaper.error("[FreeTheNotch] artwork wallpaper: plist patch failed")
            files.restore()
            DispatchQueue.main.async {
                self.transition.uncover(
                    respawnedFrom: agentsBefore, hold: LockWallpaperTransition.holdToUserWallpaper)
            }
            return
        }
        files.restartWallpaperAgent()
        files.removeImages(except: imageURL)
        Logger.artworkWallpaper.notice("[FreeTheNotch] artwork wallpaper applied")
        DispatchQueue.main.async {
            self.transition.uncover(respawnedFrom: agentsBefore, hold: LockWallpaperTransition.holdToArtwork)
        }
    }

    /// Puts the user's wallpaper back, if the artwork is up: the artwork
    /// still goes up at once (it matches the screen), the user's wallpaper
    /// comes back under it, and the cover crossfades to a still of the
    /// user's wallpaper and lifts once macOS shows it (LockWallpaperTransition),
    /// on the lock screen or (after unlock) on the desktop. `onRevealed` as
    /// the user's wallpaper appears. Returns whether the artwork was up.
    @discardableResult
    func restore(on screen: NSScreen?, lockScreen: Bool, onRevealed: (() -> Void)? = nil) -> Bool {
        appliedArtwork = nil
        applyGeneration.invalidate()
        let files = files
        guard isUp else {
            if !lockScreen { transition.dismissLockScreenCover() }
            queue.async { files.restore() }
            return false
        }
        isUp = false
        guard let cover = currentCover, let screen else {
            transition.dismiss()
            queue.async {
                files.restore()
                DispatchQueue.main.async { onRevealed?() }
            }
            currentCover = nil
            return true
        }
        currentCover = nil
        let canvas = LockArtworkImage.canvas(pointSize: screen.frame.size, scale: screen.backingScaleFactor)
        let pointSize = screen.frame.size
        transition.cover(with: cover, on: screen, lockScreen: lockScreen, fadeIn: 0) { [self] in
            let generation = transition.generation
            queue.async { [self] in
                let still = files.loadUserStill(canvas: canvas)
                let agentsBefore = LockWallpaperTransition.agentPIDs()
                let fallbackHold =
                    files.backupIsAerial()
                    ? LockWallpaperTransition.holdToAerial : LockWallpaperTransition.holdToUserWallpaper
                let exportBefore = files.exportStamp()
                let killed = Date()
                files.restore()
                DispatchQueue.main.async { [self] in
                    guard let still else {
                        transition.uncover(respawnedFrom: agentsBefore, hold: fallbackHold, onUncover: onRevealed)
                        return
                    }
                    transition.crossfade(
                        to: NSImage(cgImage: still, size: pointSize),
                        duration: LockWallpaperTransition.stillFade, generation: generation)
                    onRevealed?()
                    guard lockScreen else {
                        // The desktop is the agent's own window: it draws
                        // within a second of the respawn.
                        transition.uncover(
                            respawnedFrom: agentsBefore,
                            hold: LockWallpaperTransition.holdToUserWallpaper)
                        return
                    }
                    // Lifts on the export, or after the cap without one.
                    // Never on a timer alone (AGENTS.md).
                    waitForExport(changedFrom: exportBefore, since: killed) { _ in
                        DispatchQueue.main.async { [self] in transition.lift(generation: generation) }
                    }
                }
            }
        }
        return true
    }

    /// On quit: restore before the process ends.
    func restoreNow() {
        appliedArtwork = nil
        applyGeneration.invalidate()
        isUp = false
        transition.dismiss()
        let files = files
        queue.sync { _ = files.restore() }
    }

    /// At launch: a backup still on disk means the app died while the
    /// artwork was up (crash, force quit, restart). Put the wallpaper back.
    func recoverAfterCrash() {
        let files = files
        queue.async {
            guard files.hasBackup else { return }
            Logger.artworkWallpaper.notice("[FreeTheNotch] artwork wallpaper: restoring after an unclean exit")
            files.restore()
        }
    }

    /// Calls `done(true)` once macOS has re-exported the user's wallpaper
    /// after the restart, `done(false)` after `exportTimeout`. Polls on the
    /// queue.
    private nonisolated func waitForExport(
        changedFrom before: Date?, since killed: Date, done: @escaping (Bool) -> Void
    ) {
        let files = files
        queue.asyncAfter(deadline: .now() + Self.exportPollInterval) { [self] in
            let elapsed = Date().timeIntervalSince(killed)
            if let stamp = files.exportStamp(), stamp != before, !files.exportIsArtwork() {
                Logger.artworkWallpaper.notice(
                    "[FreeTheNotch] artwork wallpaper: user's wallpaper exported \(elapsed, format: .fixed(precision: 2), privacy: .public) s after the restart"
                )
                done(true)
            } else if elapsed > Self.exportTimeout {
                Logger.artworkWallpaper.notice(
                    "[FreeTheNotch] artwork wallpaper: no export within \(Self.exportTimeout, privacy: .public) s")
                done(false)
            } else {
                waitForExport(changedFrom: before, since: killed, done: done)
            }
        }
    }
}
