import Foundation
import Testing

struct CleaningUnlockCounterTests {
    private static let escape = CleaningUnlockCounter.escapeKeyCode
    private static let letterA: Int64 = 0

    /// Presses Esc at each time; returns whether the last press unlocked.
    private func pressEscape(_ counter: inout CleaningUnlockCounter, at times: [TimeInterval]) -> Bool {
        var isUnlocked = false
        for time in times {
            isUnlocked = counter.registerKeyDown(code: Self.escape, isRepeat: false, at: time)
        }
        return isUnlocked
    }

    @Test func fiveEscapePressesUnlock() {
        var counter = CleaningUnlockCounter()
        let isUnlockedEarly = pressEscape(&counter, at: [0, 1, 2, 3])
        #expect(!isUnlockedEarly)
        #expect(counter.progress == 4)
        let isUnlocked = pressEscape(&counter, at: [4])
        #expect(isUnlocked)
    }

    @Test func anotherKeyStartsTheCountAgain() {
        var counter = CleaningUnlockCounter()
        _ = pressEscape(&counter, at: [0, 1, 2, 3])
        let isUnlockedByLetter = counter.registerKeyDown(code: Self.letterA, isRepeat: false, at: 3.5)
        #expect(!isUnlockedByLetter)
        #expect(counter.progress == 0)
        _ = pressEscape(&counter, at: [4])
        #expect(counter.progress == 1)
    }

    @Test func heldEscapeCountsOnce() {
        var counter = CleaningUnlockCounter()
        _ = pressEscape(&counter, at: [0])
        for time in stride(from: 0.5, through: 3, by: 0.5) {
            let isUnlocked = counter.registerKeyDown(code: Self.escape, isRepeat: true, at: time)
            #expect(!isUnlocked)
        }
        #expect(counter.progress == 1)
    }

    @Test(arguments: [
        // 6 s apart is still inside the window: the count goes on.
        (6.0, 2),
        // A longer pause starts over; this press is the first of a new count.
        (6.5, 1),
    ])
    func pauseBetweenPresses(gap: TimeInterval, expectedProgress: Int) {
        var counter = CleaningUnlockCounter()
        _ = pressEscape(&counter, at: [10, 10 + gap])
        #expect(counter.progress == expectedProgress)
    }

    @Test func resetForgetsEarlierPresses() {
        var counter = CleaningUnlockCounter()
        _ = pressEscape(&counter, at: [0, 1, 2])
        counter.reset()
        #expect(counter.progress == 0)
        let isUnlockedEarly = pressEscape(&counter, at: [3, 4, 5, 6])
        #expect(!isUnlockedEarly)
        let isUnlocked = pressEscape(&counter, at: [7])
        #expect(isUnlocked)
    }
}
