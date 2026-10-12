import Foundation
import Testing

/// Independently calculated wheel distances, gesture classification and glide invariants.
struct SmoothScrollTests {
    @Test(arguments: [(0.0, 0.25, 0.25), (3.0, 0.0, 3.0), (-2.0, -0.5, -0.5)])
    func fractionalTicksWinOverTruncatedLines(_ line: Double, fixed: Double, expected: Double) {
        #expect(SmoothScrollSupport.ticks(line: line, fixedPoint: fixed) == expected)
    }

    @Test(arguments: [(4.0, 40.0, 40.0, 40.0), (4.0, 0.0, 40.0, 40.0), (8.0, 20.0, 80.0, 40.0)])
    func continuousWheelUsesPointsAndScalesOnlyOnce(_ fixed: Double, point: Double, step: Double, expected: Double) {
        #expect(
            SmoothScrollSupport.continuousDistance(fixedPointDelta: fixed, pointDelta: point, step: step) == expected)
    }

    @Test(arguments: [
        (false, Int64(0), Int64(0), Int64(0), Optional<Double>.none, true),
        (true, 0, 1, 0, nil, false),
        (true, 1, 0, 0, nil, false),
        (true, 0, 0, 0, nil, true),
        (true, 0, 0, 2, 0.5, false),
        (true, 0, 0, 2, 1.1, true),
    ])
    func touchGesturesKeepNativeScrolling(
        _ continuous: Bool, momentum: Int64, phase: Int64,
        count: Int64, elapsed: Double?, expected: Bool
    ) {
        let traits = SmoothScrollSupport.WheelTraits(
            isContinuous: continuous, momentumPhase: momentum,
            scrollPhase: phase, scrollCount: count)
        #expect(SmoothScrollSupport.isMouseWheel(traits, secondsSinceLastGesturePhase: elapsed) == expected)
    }

    @Test func shiftRedirectsOnlyAVerticalWheel() {
        #expect(
            SmoothScrollSupport.axes(vertical: -2, horizontal: 0, shiftPressed: true)
                == SmoothScrollSupport.Axes(vertical: 0, horizontal: -2))
        #expect(
            SmoothScrollSupport.axes(vertical: 2, horizontal: 3, shiftPressed: true)
                == SmoothScrollSupport.Axes(vertical: 2, horizontal: 3))
        #expect(
            SmoothScrollSupport.axes(vertical: 2, horizontal: 0, shiftPressed: false)
                == SmoothScrollSupport.Axes(vertical: 2, horizontal: 0))
    }

    @Test func reversingTheWheelReplacesItsOldTail() {
        var engine = SmoothScrollSupport.Engine()
        engine.add(vertical: 40, horizontal: 20)
        engine.add(vertical: -10, horizontal: 5)
        #expect(engine.remainingVertical == -10)
        #expect(engine.remainingHorizontal == 25)
        #expect(SmoothScrollSupport.carry(0.8, continuing: -10) == 0)
        #expect(SmoothScrollSupport.carry(0.8, continuing: 10) == 0.8)
    }

    @Test(arguments: [30.0, 60.0, 120.0])
    func refreshRateDoesNotChangeTotalWheelDistance(_ framesPerSecond: Double) {
        var engine = SmoothScrollSupport.Engine()
        engine.add(vertical: 120, horizontal: -40)
        var vertical = 0.0
        var horizontal = 0.0
        for _ in 0..<240 {
            let frame = engine.advance(elapsed: 1 / framesPerSecond, response: 65, coast: 100)
            vertical += frame.vertical
            horizontal += frame.horizontal
            if frame.finished { break }
        }
        #expect(!engine.isActive)
        #expect(abs(vertical - 120) < 0.000_001)
        #expect(abs(horizontal + 40) < 0.000_001)
    }

    @Test func elapsedTimeKeepsTheSameDecayAcrossDisplayCadences() {
        let oneFrame = SmoothScrollSupport.frameDelta(remaining: 400, elapsed: 1 / 60.0, response: 65)
        let halfFrame = SmoothScrollSupport.frameDelta(remaining: 400, elapsed: 1 / 120.0, response: 65)
        let secondHalf = SmoothScrollSupport.frameDelta(remaining: 400 - halfFrame, elapsed: 1 / 120.0, response: 65)
        #expect(abs(oneFrame - halfFrame - secondHalf) < 0.000_001)
    }

    @Test func responseAndCoastChangeTheCurveWithoutChangingTheBudget() {
        let slow = SmoothScrollSupport.frameDelta(remaining: 40, elapsed: 1 / 60.0, response: 0)
        let fast = SmoothScrollSupport.frameDelta(remaining: 40, elapsed: 1 / 60.0, response: 100)
        #expect(fast > slow)
        #expect(SmoothScrollSupport.coastStretch(coast: 100, remaining: 20, glide: 40) == 1.5)
        #expect(SmoothScrollSupport.coastStretch(coast: 0, remaining: 20, glide: 40) == 1)
    }

    @Test func fractionalPixelsAreCarriedAndSpentOnLanding() {
        let first = SmoothScrollSupport.wholePixels(1.4, carry: 0)
        #expect(first.pixels == 1)
        #expect(abs(first.carry - 0.4) < 0.000_001)
        let second = SmoothScrollSupport.wholePixels(1.4, carry: first.carry)
        #expect(second.pixels == 1)
        #expect(SmoothScrollSupport.finalPixels(0.4, carry: second.carry) == 1)
        #expect(SmoothScrollSupport.finalPixels(-0.5, carry: 0) == -1)
    }

    @Test func invalidMotionCannotPoisonTheEngineAndLongStallsAreClamped() {
        var engine = SmoothScrollSupport.Engine()
        engine.add(vertical: .nan, horizontal: .infinity)
        #expect(!engine.isActive)
        #expect(SmoothScrollSupport.frameDelta(remaining: 40, elapsed: .nan, response: 65) == 0)
        #expect(
            SmoothScrollSupport.frameDelta(remaining: 40, elapsed: 3, response: 65)
                == SmoothScrollSupport.frameDelta(remaining: 40, elapsed: 0.05, response: 65))
        engine.add(vertical: 40, horizontal: 20)
        engine.reset()
        #expect(!engine.isActive)
    }

    @Test func pointerCacheExpiresOrChangesWhenThePointerLeavesItsWindow() {
        let target = MouseScrollTarget(
            bundleIdentifier: "com.example.app",
            region: CGRect(x: 10, y: 20, width: 100, height: 80),
            point: CGPoint(x: 30, y: 40), resolvedAt: 5)
        #expect(target.contains(CGPoint(x: 50, y: 50), now: 5.1))
        #expect(!target.contains(CGPoint(x: 0, y: 0), now: 5.1))
        #expect(!target.contains(CGPoint(x: 50, y: 50), now: 5.3))
        #expect(target.namesWindow(at: CGPoint(x: 50, y: 50)))
        #expect(!target.namesWindow(at: CGPoint(x: 200, y: 200)))
        #expect(!target.contains(CGPoint(x: 50, y: 50), now: 4.9))
        let desktop = MouseScrollTarget(bundleIdentifier: nil, region: nil, point: .zero, resolvedAt: 5)
        #expect(desktop.contains(.zero, now: 5.1))
        #expect(!desktop.contains(CGPoint(x: 1, y: 0), now: 5.1))
    }

    @Test(arguments: [(0, 40), (-1, 20), (10, 20), (70, 70), (120, 100)])
    func speedStaysWithinItsAllowedRange(_ stored: Int, expected: Int) {
        #expect(SmoothScrollSupport.sanitizedStep(stored) == expected)
    }

    @Test(arguments: [(-1, 0), (0, 0), (65, 65), (100, 100), (101, 100)])
    func responseAndCoastStayWithinTheirAllowedRanges(_ stored: Int, expected: Int) {
        #expect(SmoothScrollSupport.sanitizedResponse(stored) == expected)
        #expect(SmoothScrollSupport.sanitizedCoast(stored) == expected)
    }

    @Test func exclusionsAreTrimmedAndDeduplicated() {
        #expect(
            SmoothScrollSupport.sanitizedExclusions([" com.example.app ", "", "com.example.app", "com.other.app"])
                == ["com.example.app", "com.other.app"])
    }
}
