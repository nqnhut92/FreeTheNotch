// No reference equivalent: CodeNotch and DuoBar have no Dock rule.

import AppKit
import Combine

/// Which edge the Dock is on. When it is on the left or right, the side
/// notch takes the opposite edge whatever Settings says. Read from the
/// Dock's own preferences (works for an auto-hiding Dock, where
/// `visibleFrame` shows nothing). No reliable notification exists for Dock
/// preference changes, so it is re-read on screen changes, app activation
/// and a slow timer while the side notch is on.
final class DockSide: ObservableObject {
    enum Side: String { case left, bottom, right }

    static let shared = DockSide()

    @Published private(set) var side: Side = DockSide.read()

    private var timer: Timer?
    private var activation: AnyCancellable?

    func start() {
        reload()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.reload() }
        activation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.reload() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        activation = nil
    }

    func reload() {
        let now = Self.read()
        if side != now { side = now }
    }

    /// The edge the Dock leaves free, or `preferred` when the Dock is at the bottom.
    func effectiveEdge(for preferred: SideNotchEdge) -> SideNotchEdge {
        Self.effectiveEdge(dock: side, preferred: preferred)
    }

    /// The edge the Dock takes, if it takes one.
    var blockedEdge: SideNotchEdge? { Self.blockedEdge(dock: side) }

    static func effectiveEdge(dock: Side, preferred: SideNotchEdge) -> SideNotchEdge {
        blockedEdge(dock: dock)?.opposite ?? preferred
    }

    static func blockedEdge(dock: Side) -> SideNotchEdge? {
        switch dock {
        case .left: return .left
        case .right: return .right
        case .bottom: return nil
        }
    }

    private static func read() -> Side {
        // A small plist read through cfprefsd; synchronise to drop our cache.
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        let value = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String
        return value.flatMap(Side.init(rawValue:)) ?? .bottom
    }
}
