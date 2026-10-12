import Foundation

/// Countdown clocks shared by the timer and keep-awake.
enum DurationFormat {
    /// "4:05" under an hour; "1:04:05" from an hour up, or whenever
    /// `showsHours` is set (a 2-hour timer reads "0:59:59", not "59:59").
    static func clock(_ seconds: Int, showsHours: Bool = false) -> String {
        let total = max(0, seconds)
        let minutes = total / 60
        let secs = total % 60
        if showsHours || total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, minutes % 60, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// A media position or length: "3:07", "1:02:05" past an hour (Atoll's
    /// timeString), rounded to the second. Unknown or negative is "0:00".
    static func playback(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0, seconds < Double(Int.max) else { return "0:00" }
        return clock(Int(seconds.rounded()))
    }
}
