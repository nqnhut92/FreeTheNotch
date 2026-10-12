import Foundation
import Testing

struct PlaybackClockTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 1_000)

    private static func clock(elapsed: Double = 10, duration: Double = 120, playing: Bool = true) -> PlaybackClock {
        PlaybackClock(anchorElapsed: elapsed, anchorDate: start, duration: duration, playing: playing)
    }

    @Test func runsWhilePlaying() {
        let clock = Self.clock()
        #expect(clock.elapsed(at: Self.start.addingTimeInterval(5)) == 15)
        #expect(clock.fraction(at: Self.start.addingTimeInterval(20)) == 0.25)
    }

    @Test func standsStillWhilePaused() {
        #expect(Self.clock(playing: false).elapsed(at: Self.start.addingTimeInterval(60)) == 10)
    }

    @Test func staysWithinTheTrack() {
        let clock = Self.clock(elapsed: 110, duration: 120)
        #expect(clock.elapsed(at: Self.start.addingTimeInterval(30)) == 120)
        #expect(clock.fraction(at: Self.start.addingTimeInterval(30)) == 1)
        #expect(Self.clock(elapsed: -5, playing: false).elapsed(at: Self.start) == 0)
        // A live stream has no duration: no fraction, no upper bound.
        let live = Self.clock(elapsed: 500, duration: 0)
        #expect(live.elapsed(at: Self.start.addingTimeInterval(10)) == 510)
        #expect(live.fraction(at: Self.start) == 0)
    }

    private func reconcile(
        _ clock: PlaybackClock, remote: Double, changed: Bool = true, duration: Double = 120,
        playing: Bool = true, trackChanged: Bool = false, after seconds: TimeInterval = 5
    ) -> PlaybackClock {
        clock.reconciled(
            remoteElapsed: remote, remoteElapsedChanged: changed, duration: duration,
            playing: playing, trackChanged: trackChanged, now: Self.start.addingTimeInterval(seconds))
    }

    @Test func staleSamplesNeverMoveTheClock() {
        let clock = Self.clock()
        // Predicted 15 s; the bridge still repeats the old 10 s.
        #expect(reconcile(clock, remote: 10, changed: false) == clock)
        // Changed, but within the latency tolerance.
        #expect(reconcile(clock, remote: 16.5) == clock)
    }

    @Test func aSeekReanchorsOnTheReportedPosition() {
        let now = Self.start.addingTimeInterval(5)
        #expect(
            reconcile(Self.clock(), remote: 60)
                == PlaybackClock(anchorElapsed: 60, anchorDate: now, duration: 120, playing: true))
    }

    @Test func aNewTrackStartsFromItsReportedPosition() {
        let now = Self.start.addingTimeInterval(5)
        #expect(
            reconcile(Self.clock(), remote: 0, changed: false, duration: 200, trackChanged: true)
                == PlaybackClock(anchorElapsed: 0, anchorDate: now, duration: 200, playing: true))
    }

    @Test func pausingFreezesThePredictedPosition() {
        let now = Self.start.addingTimeInterval(5)
        #expect(
            reconcile(Self.clock(), remote: 10, changed: false, playing: false)
                == PlaybackClock(anchorElapsed: 15, anchorDate: now, duration: 120, playing: false))
    }

    @Test func aNewDurationKeepsTheAnchor() {
        let clock = Self.clock()
        #expect(
            reconcile(clock, remote: 10, changed: false, duration: 180)
                == PlaybackClock(anchorElapsed: 10, anchorDate: Self.start, duration: 180, playing: true))
    }

    @Test(arguments: [
        (Double.nan, "0:00"),
        (.infinity, "0:00"),
        (-3, "0:00"),
        (0, "0:00"),
        (59.4, "0:59"),
        (59.6, "1:00"),
        (187, "3:07"),
        (3725, "1:02:05"),
    ])
    func positionLabels(_ seconds: Double, expected: String) {
        #expect(DurationFormat.playback(seconds) == expected)
    }
}
