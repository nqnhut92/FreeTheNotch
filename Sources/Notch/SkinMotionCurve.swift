import CoreGraphics
import Foundation

/// A skin part's repeating movement. `CoreAnimationMotion` samples one period
/// into keyframes that Core Animation plays in the render server, so the app
/// does no work per frame (a `TimelineView` re-runs its view 30–60 times a
/// second).
enum SkinMotionCurve: Equatable {
    /// The swing's lazy idle sway.
    case sway
    /// One swing per beat, wider than the sway.
    case beatSwing(bpm: Double)
    /// Bob down and nod on every beat; `amount` scales the drop.
    case beatDance(bpm: Double, amount: Double)

    static let swayDegrees = 7.0
    /// Radians per second of the sway's sine.
    static let swaySpeed = 1.7
    static let beatSwingDegrees = 12.0
    static let danceNodDegrees = 6.0
    static let danceSquash = 0.04
    static let danceStretch = 0.08
    static let danceDrop = 3.0

    /// Seconds before the movement repeats. A beat curve follows
    /// sin(beats × π), which repeats every two beats.
    var period: TimeInterval {
        switch self {
        case .sway: return 2 * .pi / Self.swaySpeed
        case .beatSwing(let bpm), .beatDance(let bpm, _): return 2 * 60 / bpm
        }
    }

    /// The pose `time` seconds into the movement.
    func pose(at time: TimeInterval) -> SkinPose {
        switch self {
        case .sway:
            return SkinPose(rotation: Self.radians(sin(time * Self.swaySpeed) * Self.swayDegrees))
        case .beatSwing(let bpm):
            let beats = time * bpm / 60
            return SkinPose(rotation: Self.radians(sin(beats * .pi) * Self.beatSwingDegrees))
        case .beatDance(let bpm, let amount):
            let beats = time * bpm / 60
            // 0 on the beat, 1 halfway: a sharp drop on each beat.
            let hop = abs(sin(beats * .pi))
            return SkinPose(
                rotation: Self.radians(sin(beats * .pi) * Self.danceNodDegrees),
                scaleX: 1 - Self.danceSquash * hop, scaleY: 1 + Self.danceStretch * hop,
                offsetY: hop * Self.danceDrop * amount)
        }
    }

    /// `count` evenly spaced poses over one period plus the first again, so
    /// a repeating animation loops without a jump. Transforms are in a
    /// y-down space and pivot on `anchor`.
    func keyframes(count: Int, anchor: CGPoint) -> [CGAffineTransform] {
        (0...count).map { index in
            pose(at: period * Double(index) / Double(count)).transform(anchor: anchor)
        }
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
}

/// Where a moving skin part is at one moment, in SwiftUI's terms: a scale
/// and a clockwise rotation about a pivot, then a downward offset.
struct SkinPose: Equatable {
    var rotation: Double
    var scaleX = 1.0
    var scaleY = 1.0
    var offsetY = 0.0

    /// The pose as `scaleEffect(anchor:)`, `rotationEffect(anchor:)` and
    /// `offset(y:)` would apply it, in a y-down space pivoting on `anchor`.
    func transform(anchor: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
            .concatenating(CGAffineTransform(rotationAngle: rotation))
            .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y + offsetY))
    }
}

extension CGAffineTransform {
    /// The same movement expressed in a y-up space of the given height
    /// (a layer whose content is not flipped).
    func inYUpSpace(height: CGFloat) -> CGAffineTransform {
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
        return flip.concatenating(self).concatenating(flip)
    }
}
