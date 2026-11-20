import AppKit
import Combine
import SwiftUI

/// The spinning record with its tonearm, standing on the artwork wallpaper in the place of the sharp artwork when
/// the song comes from a record player (`VinylSource`). The wallpaper itself is then only the blurred fill. A window
/// of its own, since the artwork's top half sits above the widget window. Clicks pass through to
/// `LockArtworkClickWindow`. Up only while the artwork is the wallpaper.
@MainActor
final class LockVinylWindow {
    private let window: NSWindow
    private var screen: NSScreen
    private var watch: AnyCancellable?
    private var lastShows = false

    init(screen: NSScreen, artworkSwitch: LockArtworkSwitch, media: MediaRemoteAdapter) {
        self.screen = screen
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.level = LockScreenLevel.vinyl
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: LockTurntable(media: media))
        watch = Publishers.CombineLatest(artworkSwitch.$presentation, media.$bundleIdentifier)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] presentation, _ in
                self?.update(show: presentation == .artwork && media.showsVinyl)
            }
    }

    func close() {
        watch = nil
        window.orderOut(nil)
    }

    /// Displays changed while locked: follow the current main display.
    func relayout() {
        if let main = NSScreen.lockScreenMain { screen = main }
        update(show: lastShows)
    }

    private func update(show: Bool) {
        lastShows = show
        guard show else {
            window.orderOut(nil)
            return
        }
        let frame = LockVinylLayout.turntableFrame(in: screen.frame.size)
        window.setFrame(
            NSRect(
                x: screen.frame.minX + frame.minX, y: screen.frame.maxY - frame.maxY,
                width: frame.width, height: frame.height), display: false)
        if !window.isVisible {
            window.orderFrontRegardless()
            SkyLightLockSpace.shared.adopt(window)
        }
    }
}

/// The record and tonearm following the player.
private struct LockTurntable: View {
    @ObservedObject var media: MediaRemoteAdapter

    var body: some View {
        TurntableView(artwork: media.artwork, isPlaying: media.isPlaying, setPlaying: { _ in })
    }
}
