import Foundation
import Testing

struct SkinMotionTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let visible: Bool
        let battery: Bool
        let lowPower: Bool
        let active: Bool
        let idled: Bool
        let expected: SkinMotion

        var testDescription: String {
            "visible \(visible), battery \(battery), low power \(lowPower), active \(active), idled \(idled)"
        }
    }

    @Test(arguments: [
        // Never animates where it cannot be seen, plugged in or not.
        Case(visible: false, battery: false, lowPower: false, active: true, idled: false, expected: .still),
        Case(visible: false, battery: true, lowPower: false, active: true, idled: false, expected: .still),
        // Plugged in: full smoothness, idle or not.
        Case(visible: true, battery: false, lowPower: false, active: false, idled: true, expected: .smooth),
        Case(visible: true, battery: false, lowPower: false, active: true, idled: false, expected: .smooth),
        // On battery: a lower frame rate, still once idle.
        Case(visible: true, battery: true, lowPower: false, active: true, idled: true, expected: .reduced),
        Case(visible: true, battery: true, lowPower: false, active: false, idled: false, expected: .reduced),
        Case(visible: true, battery: true, lowPower: false, active: false, idled: true, expected: .still),
        // Low Power Mode, even plugged in: still as soon as nothing is active.
        Case(visible: true, battery: false, lowPower: true, active: false, idled: false, expected: .still),
        Case(visible: true, battery: true, lowPower: true, active: true, idled: false, expected: .reduced),
    ])
    func resolvesMotion(_ testCase: Case) {
        let motion = SkinMotion.resolve(
            isNotchVisible: testCase.visible, isOnBattery: testCase.battery, isLowPowerMode: testCase.lowPower,
            isActive: testCase.active, hasIdled: testCase.idled)
        #expect(motion == testCase.expected)
    }

    @Test func pluggedInKeepsTheOriginalFrameRates() {
        #expect(SkinMotion.smooth.frameInterval == 1.0 / 30)
        #expect(SkinMotion.smooth.danceFrameInterval == 1.0 / 60)
    }

    @Test func onBatteryHalvesTheFrameRates() {
        #expect(SkinMotion.reduced.frameInterval == 1.0 / 15)
        #expect(SkinMotion.reduced.danceFrameInterval == 1.0 / 30)
    }
}
