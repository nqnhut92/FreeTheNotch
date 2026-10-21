import CoreGraphics
import Foundation
import Testing

struct SkinMotionCurveTests {
    private static let tolerance = 1e-9

    private static func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < tolerance }

    private static func close(_ a: CGPoint, _ b: CGPoint) -> Bool { close(a.x, b.x) && close(a.y, b.y) }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    // MARK: Curves

    /// sin(t × 1.7) repeats every 2π / 1.7 ≈ 3.696 s and peaks at 7° a
    /// quarter of the way in.
    @Test func swaySwingsSevenDegreesEachWay() {
        let curve = SkinMotionCurve.sway
        #expect(Self.close(curve.period, 2 * .pi / 1.7))
        #expect(Self.close(curve.pose(at: 0).rotation, 0))
        #expect(Self.close(curve.pose(at: curve.period / 4).rotation, Self.radians(7)))
        #expect(Self.close(curve.pose(at: curve.period * 3 / 4).rotation, Self.radians(-7)))
    }

    /// 120 BPM: a beat every 0.5 s, the swing back and forth every two beats.
    @Test func beatSwingReachesTwelveDegreesHalfwayThroughABeat() {
        let curve = SkinMotionCurve.beatSwing(bpm: 120)
        #expect(Self.close(curve.period, 1))
        #expect(Self.close(curve.pose(at: 0.25).rotation, Self.radians(12)))
        #expect(Self.close(curve.pose(at: 0.5).rotation, 0))
    }

    /// 60 BPM, halfway through the first beat: the full hop.
    @Test func beatDanceStretchesNodsAndDropsAtTheHop() {
        let pose = SkinMotionCurve.beatDance(bpm: 60, amount: 2).pose(at: 0.5)
        #expect(Self.close(pose.rotation, Self.radians(6)))
        #expect(Self.close(pose.scaleX, 0.96))
        #expect(Self.close(pose.scaleY, 1.08))
        #expect(Self.close(pose.offsetY, 6))
    }

    @Test func beatDanceRestsOnTheBeat() {
        let pose = SkinMotionCurve.beatDance(bpm: 90, amount: 1).pose(at: 0)
        #expect(pose == SkinPose(rotation: 0))
    }

    @Test func keyframesLoopBackToTheFirstPose() throws {
        let anchor = CGPoint(x: 20, y: 0)
        let keyframes = SkinMotionCurve.sway.keyframes(count: 4, anchor: anchor)
        #expect(keyframes.count == 5)
        let first = try #require(keyframes.first)
        let last = try #require(keyframes.last)
        let probe = CGPoint(x: 37, y: 41)
        #expect(Self.close(probe.applying(first), probe.applying(last)))
    }

    // MARK: Transforms

    /// Clockwise in a y-down space: a point to the right of the pivot swings
    /// below it, and the pivot stays put.
    @Test func rotationPivotsOnTheAnchor() {
        let transform = SkinPose(rotation: .pi / 2).transform(anchor: CGPoint(x: 10, y: 0))
        #expect(Self.close(CGPoint(x: 10, y: 0).applying(transform), CGPoint(x: 10, y: 0)))
        #expect(Self.close(CGPoint(x: 20, y: 0).applying(transform), CGPoint(x: 10, y: 10)))
    }

    @Test func scaleStretchesAwayFromTheAnchorThenOffsets() {
        let transform = SkinPose(rotation: 0, scaleY: 2, offsetY: 5).transform(anchor: CGPoint(x: 10, y: 0))
        #expect(Self.close(CGPoint(x: 10, y: 0).applying(transform), CGPoint(x: 10, y: 5)))
        #expect(Self.close(CGPoint(x: 10, y: 10).applying(transform), CGPoint(x: 10, y: 25)))
    }

    /// The same quarter turn in a y-up space 30 pt tall: the pivot is at
    /// y = 30, and (20, 30) lands 10 pt below it.
    @Test func aYUpSpaceSeesTheSameMovement() {
        let transform = SkinPose(rotation: .pi / 2).transform(anchor: CGPoint(x: 10, y: 0)).inYUpSpace(height: 30)
        #expect(Self.close(CGPoint(x: 10, y: 30).applying(transform), CGPoint(x: 10, y: 30)))
        #expect(Self.close(CGPoint(x: 20, y: 30).applying(transform), CGPoint(x: 10, y: 20)))
    }
}
