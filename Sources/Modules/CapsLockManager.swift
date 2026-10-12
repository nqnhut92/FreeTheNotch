import AppKit
import Combine
import SwiftUI

/// Monitors Caps Lock state via NSEvent modifier flags (Atoll-style).
/// Shows a live activity in the collapsed notch while Caps Lock is active.
final class CapsLockManager: ObservableObject {
    static let shared = CapsLockManager()

    @Published private(set) var isCapsLockActive: Bool = false

    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    private init() {
        isCapsLockActive = NSEvent.modifierFlags.contains(.capsLock)

        // Monitor flag changes when app is focused.
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        // Monitor flag changes globally (even when app is not focused).
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }
    }

    deinit {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let newState = event.modifierFlags.contains(.capsLock)
        guard newState != isCapsLockActive else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            isCapsLockActive = newState
        }
    }
}
