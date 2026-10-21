import Foundation

/// How smoothly a skin animates. Plugged in, skins always run at full
/// smoothness. On battery or in Low Power Mode they run at a lower frame
/// rate and hold still once the notch has been idle for `idleDelay`. They
/// always hold still while the notch cannot be seen.
enum SkinMotion: Equatable {
    case smooth, reduced, still

    /// Seconds without hover, an open notch or music before a skin on
    /// battery holds still.
    static let idleDelay: TimeInterval = 20

    /// Frame interval of the decoration and the swing.
    var frameInterval: TimeInterval {
        switch self {
        case .smooth, .still: return 1.0 / 30
        case .reduced: return 1.0 / 15
        }
    }

    /// Frame interval of the dance to music.
    var danceFrameInterval: TimeInterval {
        switch self {
        case .smooth, .still: return 1.0 / 60
        case .reduced: return 1.0 / 30
        }
    }

    /// Frames per second of the swing (`CoreAnimationMotion`).
    var frameRate: Float { Float((1 / frameInterval).rounded()) }

    /// Frames per second of the dance.
    var danceFrameRate: Float { Float((1 / danceFrameInterval).rounded()) }

    var isStill: Bool { self == .still }

    /// - Parameters:
    ///   - isNotchVisible: false while the screen is locked or asleep.
    ///   - isOnBattery: the Mac runs on its battery.
    ///   - isLowPowerMode: Low Power Mode is on, plugged in or not.
    ///   - isActive: the notch is hovered or open, or music plays.
    ///   - hasIdled: the notch has not been active for `idleDelay`.
    static func resolve(
        isNotchVisible: Bool, isOnBattery: Bool, isLowPowerMode: Bool,
        isActive: Bool, hasIdled: Bool
    ) -> SkinMotion {
        guard isNotchVisible else { return .still }
        guard isOnBattery || isLowPowerMode else { return .smooth }
        if isActive { return .reduced }
        // Low Power Mode asks for every saving: no idle grace period.
        if isLowPowerMode || hasIdled { return .still }
        return .reduced
    }
}
