import Foundation

// Unlock rule ported from Vorssaint's CleaningModeManager
// (vorssaint/vorssaint-utils, GPL-3.0-or-later).

/// Counts the Esc presses that end Cleaning Mode.
///
/// Five distinct Esc presses unlock. Any other key (a cloth resting next to
/// Esc) starts over, auto-repeat is ignored, and a pause longer than
/// `pressWindow` between two Esc presses starts the count again, so isolated
/// hits spread across a long wipe never add up.
struct CleaningUnlockCounter {
    static let escapeKeyCode: Int64 = 53
    /// Slow deliberate presses still count; stray ones far apart do not.
    static let pressWindow: TimeInterval = 6.0

    let threshold: Int
    private(set) var progress = 0
    private var lastEscapeTime: TimeInterval?

    init(threshold: Int = 5) {
        self.threshold = threshold
    }

    /// Feeds one key-down (or modifier change) at uptime `time`. Returns true
    /// when this press completes the unlock.
    mutating func registerKeyDown(code: Int64, isRepeat: Bool, at time: TimeInterval) -> Bool {
        guard !isRepeat else { return false }
        guard code == Self.escapeKeyCode else {
            progress = 0
            return false
        }
        if let lastEscapeTime, time - lastEscapeTime > Self.pressWindow {
            progress = 0
        }
        lastEscapeTime = time
        progress += 1
        return progress >= threshold
    }

    mutating func reset() {
        progress = 0
        lastEscapeTime = nil
    }
}
