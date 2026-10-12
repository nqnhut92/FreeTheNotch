import Foundation

/// The scrubber's position as an anchor plus wall-clock time. The media
/// bridge reports the position about once a second, and only as the value at
/// publish time, so the clock runs locally (Atoll's approach) and moves to a
/// reported value only on a seek.
struct PlaybackClock: Equatable {
    var anchorElapsed: Double = 0
    var anchorDate = Date()
    var duration: Double = 0
    var playing = false

    /// A jump this far from the predicted position is a seek; anything
    /// closer is bridge latency.
    static let seekTolerance: TimeInterval = 3

    func elapsed(at date: Date) -> Double {
        let raw = playing ? anchorElapsed + date.timeIntervalSince(anchorDate) : anchorElapsed
        if duration > 0 { return min(duration, max(0, raw)) }
        return max(0, raw)
    }

    func fraction(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, elapsed(at: date) / duration)
    }

    /// The clock after a bridge sample. A new track or a seek (a changed
    /// remote value far from the prediction) re-anchors on the reported
    /// position; play/pause re-anchors on the predicted one; a new duration
    /// (live streams) keeps the anchor. Otherwise the clock is unchanged, so
    /// the bar never snaps to a sample.
    func reconciled(
        remoteElapsed: Double, remoteElapsedChanged: Bool,
        duration: Double, playing: Bool, trackChanged: Bool, now: Date
    ) -> PlaybackClock {
        let predicted = elapsed(at: now)
        if trackChanged
            || (remoteElapsedChanged && abs(remoteElapsed - predicted) > Self.seekTolerance)
        {
            return PlaybackClock(anchorElapsed: remoteElapsed, anchorDate: now, duration: duration, playing: playing)
        }
        if playing != self.playing {
            return PlaybackClock(anchorElapsed: predicted, anchorDate: now, duration: duration, playing: playing)
        }
        if self.duration != duration {
            return PlaybackClock(
                anchorElapsed: anchorElapsed, anchorDate: anchorDate, duration: duration, playing: playing)
        }
        return self
    }
}
