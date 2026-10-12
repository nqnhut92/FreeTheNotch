// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// helpers/ScreenCaptureVisibilityManager.swift (`hideDynamicIslandFromScreenCapture`).

import AppKit
import Combine

/// Keeps the app's overlay windows (notch, menu-bar panel, lock-screen
/// widgets) out of screenshots, screen recordings and screen sharing.
///
/// Atoll registers each window by hand. Here every untitled window of the
/// app is covered as soon as it comes on screen (occlusion change), so new
/// windows cannot be forgotten. The titled Settings window stays capturable.
@MainActor
final class ScreenCaptureVisibility {
    static let shared = ScreenCaptureVisibility()

    private var hide = true
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start(settings: SettingsStore) {
        settings.$hideFromScreenCapture
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] hide in
                self?.hide = hide
                self?.applyToAllWindows()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)
            .compactMap { $0.object as? NSWindow }
            .sink { [weak self] window in self?.apply(to: window) }
            .store(in: &cancellables)
    }

    func applyToAllWindows() {
        NSApp.windows.forEach(apply(to:))
    }

    private func apply(to window: NSWindow) {
        guard !window.styleMask.contains(.titled) else { return }
        let type: NSWindow.SharingType = hide ? .none : .readOnly
        if window.sharingType != type { window.sharingType = type }
    }
}
