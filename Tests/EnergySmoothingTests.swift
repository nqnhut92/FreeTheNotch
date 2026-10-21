import Foundation
import Testing

struct EnergySmoothingTests {
    // MARK: Moving average

    @Test func anAppSeenForTheFirstTimeStartsAtItsSample() {
        var smoother = EnergySmoother()
        let averages = smoother.add([7: 40], elapsed: 4)
        #expect(averages == [7: 40])
    }

    /// After one time constant the average has covered 1 - 1/e of the step:
    /// 40 → 0 leaves 40 / e ≈ 14.715.
    @Test func anAppMissingFromTheSampleFadesOut() throws {
        var smoother = EnergySmoother()
        smoother.add([7: 40], elapsed: 4)
        let averages = smoother.add([:], elapsed: EnergySmoother.timeConstant)
        let average = try #require(averages[7])
        #expect(abs(average - 14.715) < 0.001)
    }

    /// 10 → 30 over one time constant: 10 + 20 × (1 - 1/e) ≈ 22.642.
    @Test func aRiseIsFollowedGradually() throws {
        var smoother = EnergySmoother()
        smoother.add([7: 10], elapsed: 4)
        let averages = smoother.add([7: 30], elapsed: EnergySmoother.timeConstant)
        let average = try #require(averages[7])
        #expect(abs(average - 22.642) < 0.001)
    }

    /// 0.2 × 1/e ≈ 0.074, under the 0.1 cut.
    @Test func averagesThatFadeToAlmostNothingAreDropped() {
        var smoother = EnergySmoother()
        smoother.add([7: 0.2], elapsed: 4)
        let averages = smoother.add([:], elapsed: EnergySmoother.timeConstant)
        #expect(averages.isEmpty)
    }

    @Test func noElapsedTimeKeepsTheAverage() {
        var smoother = EnergySmoother()
        smoother.add([7: 40], elapsed: 4)
        let averages = smoother.add([7: 0], elapsed: 0)
        #expect(averages == [7: 40])
    }

    // MARK: Significant list

    /// Joins at 20, stays down to 10, and needs 20 again to come back.
    @Test func aListedAppStaysUntilItDropsBelowTheLeaveThreshold() {
        var filter = SignificantEnergyFilter()
        let listed = [25.0, 15, 25, 8, 15].map { filter.update([7: $0]).contains(7) }
        #expect(listed == [true, true, true, false, false])
    }

    @Test func anAppUnderTheJoinThresholdIsNeverListed() {
        var filter = SignificantEnergyFilter()
        let listed = [19.9, 15, 19].map { filter.update([7: $0]).contains(7) }
        #expect(listed == [false, false, false])
    }

    @Test func anAppGoneFromTheSharesLeavesTheList() {
        var filter = SignificantEnergyFilter()
        filter.update([7: 30, 8: 30])
        let listed = filter.update([8: 30])
        #expect(listed == [8])
    }
}
