// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// DynamicIsland/managers/LockScreenLiveActivityWindowManager.swift and its
// LockScreenLiveActivityOverlay / LockScreenLiveActivityOverlayModel.
// Simplified: no fingerprint on the right.

import AppKit
import SwiftUI

/// Drives the lock notch's appear/disappear animation (Atoll's
/// LockScreenLiveActivityOverlayModel). Shared by the lock screen and the
/// Settings preview.
@MainActor
final class LockNotchModel: ObservableObject {
    @Published var scale: CGFloat = LockNotchAnimation.hiddenScale
    @Published var opacity: Double = 0
    @Published var isLocked = true
}

/// Atoll's lock-notch timings, shared by LockScreenManager and the preview.
enum LockNotchAnimation {
    static let hiddenScale: CGFloat = 0.6
    static let springIn = Animation.spring(response: 0.45, dampingFraction: 0.82)
    static let fadeIn = Animation.easeOut(duration: 0.18)
    /// The open shackle shows this long after unlock.
    static let unlockedHold: Duration = .seconds(1.2)
    static let springOut = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let fadeOut = Animation.easeOut(duration: 0.25)
    /// From the start of the shrink to the window going away.
    static let outDuration: Duration = .seconds(0.4)
}

/// Stretched island on the lock screen: padlock indicator on the left,
/// black notch in the middle (Atoll's LockScreenLiveActivityOverlay).
struct LockNotchView: View {
    @ObservedObject var model: LockNotchModel
    let notchSize: CGSize

    private var indicatorSize: CGFloat {
        LockNotchLayout.indicatorSize(notchHeight: notchSize.height)
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .overlay(alignment: .leading) {
                    Image(systemName: model.isLocked ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: indicatorSize * 0.55, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: indicatorSize, height: indicatorSize)
                }
                .frame(width: indicatorSize, height: notchSize.height)
            Rectangle()
                .fill(.black)
                .frame(width: notchSize.width, height: notchSize.height)
            // Atoll has a fingerprint here.
            Color.clear
                .frame(width: indicatorSize, height: notchSize.height)
        }
        .frame(width: notchSize.width + indicatorSize * 2, height: notchSize.height)
        .padding(.horizontal, LockNotchLayout.horizontalPadding)
        .background(Color.black)
        .clipShape(NotchShape(topRadius: 0, bottomRadius: LockNotchLayout.horizontalPadding))
        .frame(width: LockNotchLayout.windowSize(notchSize: notchSize).width, height: notchSize.height)
        .scaleEffect(x: model.scale, y: 1, anchor: .center)
        .opacity(model.opacity)
    }
}

extension LockNotchLayout {
    /// The closed island's size on `screen`, snapped to whole points.
    static func notchSize(on screen: NSScreen) -> CGSize {
        snapped(DisplayGeometry.collapsedSize(for: screen))
    }
}

extension NSScreen {
    /// The display macOS draws the lock-screen clock and password field on
    /// (`CGMainDisplayID`), where the widgets go. Atoll also uses one screen.
    static var lockScreenMain: NSScreen? {
        screens.first { $0.displayID == CGMainDisplayID() } ?? screens.first
    }

    /// Where the lock notch goes: the physical-notch display, else the main
    /// one. Like Atoll's lockContext(), only one: on an external display
    /// without a notch it glitches (wallpaper shrink and flash).
    static var lockNotchScreen: NSScreen? {
        screens.first(where: DisplayGeometry.hasNotch) ?? .main
    }
}
