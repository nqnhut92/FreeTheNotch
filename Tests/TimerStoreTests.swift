import Foundation
import Testing

@MainActor
struct TimerStoreTests {
    /// A clock the test moves by hand.
    private final class FakeClock {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        func advance(_ seconds: TimeInterval) { now += seconds }
    }

    @Test func startsIdleAtTwentyFiveMinutes() {
        let store = TimerStore(now: Date.init, onFinish: {})
        #expect(store.formattedRemaining == "25:00")
        #expect(!store.isActive)
        #expect(store.progressFraction == 0)
    }

    @Test func countsDownFromTheEndDate() {
        let clock = FakeClock()
        let store = TimerStore(now: { clock.now }, onFinish: {})
        store.setDuration(90)
        store.start()
        clock.advance(30.2)
        store.tick()
        #expect(store.remainingSeconds == 60)  // 59.8 s left rounds up
        #expect(store.formattedRemaining == "1:00")
        #expect(abs(store.progressFraction - 1.0 / 3) < 1e-9)
        #expect(store.isActive)

        store.pause()
        #expect(!store.isRunning)
        #expect(store.isActive)  // paused part-way keeps the live activity
        store.reset()
        #expect(store.remainingSeconds == 90)
        #expect(!store.isActive)
    }

    @Test func finishesOnceAtZero() {
        let clock = FakeClock()
        var finished = 0
        let store = TimerStore(now: { clock.now }, onFinish: { finished += 1 })
        store.setDuration(10)
        store.start()
        clock.advance(11)
        store.tick()
        store.tick()
        #expect(store.remainingSeconds == 0)
        #expect(!store.isRunning)
        #expect(!store.isActive)
        #expect(store.progressFraction == 1)
        #expect(finished == 1)
    }

    @Test func longTimersKeepTheHourField() {
        let clock = FakeClock()
        let store = TimerStore(now: { clock.now }, onFinish: {})
        store.setDuration(7200)
        #expect(store.formattedRemaining == "2:00:00")
        store.start()
        clock.advance(3601)
        store.tick()
        #expect(store.formattedRemaining == "0:59:59")
    }

    @Test(arguments: [
        (0, false, "0:00"),
        (-5, false, "0:00"),
        (65, false, "1:05"),
        (3599, false, "59:59"),
        (3600, false, "1:00:00"),
        (3725, false, "1:02:05"),
        (59, true, "0:00:59"),
    ])
    func durationClock(_ seconds: Int, showsHours: Bool, expected: String) {
        #expect(DurationFormat.clock(seconds, showsHours: showsHours) == expected)
    }
}
