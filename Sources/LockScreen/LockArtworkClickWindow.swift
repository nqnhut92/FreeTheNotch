import AppKit
import Combine

/// Turns the artwork wallpaper off on a click on the artwork itself (no
/// separate button). A window of its own over exactly the sharp artwork
/// (LockArtworkImage.visibleRect), since the widget window starts under
/// macOS's clock and the artwork's top half sits above it. Nearly clear
/// (alpha 0.001): a fully transparent window lets clicks through to the
/// lock screen. Up only while the artwork is the wallpaper.
@MainActor
final class LockArtworkClickWindow {
    /// The lowest alpha that still takes clicks.
    private static let clickableAlpha: CGFloat = 0.001

    private let window: NSWindow
    private var screen: NSScreen
    private var watch: AnyCancellable?
    private var lastState: (show: Bool, artwork: NSImage?) = (false, nil)

    init(screen: NSScreen, artworkSwitch: LockArtworkSwitch, media: MediaRemoteAdapter) {
        self.screen = screen
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.level = LockScreenLevel.artworkClick
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = ClickView { [weak artworkSwitch] in
            guard let artworkSwitch else { return }
            // Answer the click at once, as the card's artwork does.
            artworkSwitch.presentation = .switching
            artworkSwitch.isOn = false
        }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.withAlphaComponent(Self.clickableAlpha).cgColor
        window.contentView = view
        watch = Publishers.CombineLatest(artworkSwitch.$presentation, media.$artwork)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] presentation, artwork in
                self?.update(show: presentation == .artwork, artwork: artwork)
            }
    }

    func close() {
        watch = nil
        window.orderOut(nil)
    }

    /// Displays changed while locked: follow the current main display.
    func relayout() {
        if let main = NSScreen.lockScreenMain { screen = main }
        update(show: lastState.show, artwork: lastState.artwork)
    }

    private func update(show: Bool, artwork: NSImage?) {
        lastState = (show, artwork)
        guard show, let art = artwork?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            window.orderOut(nil)
            return
        }
        // Same canvas as LockArtworkWallpaper.apply: the screen in pixels.
        let hit = LockArtworkImage.visibleRect(
            artworkPixels: CGSize(width: art.width, height: art.height),
            screenSize: screen.frame.size, scale: screen.backingScaleFactor)
        window.setFrame(
            NSRect(
                x: screen.frame.minX + hit.rect.minX,
                y: screen.frame.maxY - hit.rect.maxY,
                width: hit.rect.width, height: hit.rect.height), display: false)
        window.contentView?.layer?.cornerRadius = hit.cornerRadius
        if !window.isVisible {
            window.orderFrontRegardless()
            SkyLightLockSpace.shared.adopt(window)
        }
    }

    private final class ClickView: NSView {
        let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { action() }
    }
}
