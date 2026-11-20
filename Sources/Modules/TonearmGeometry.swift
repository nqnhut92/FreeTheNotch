import Foundation

/// Geometry of the tonearm in the turntable's 300 × 300 drawing space.
enum TonearmGeometry {
    /// Side of the square space the turntable is drawn in.
    static let canvasSide = 300.0
    /// Where the arm turns.
    static let pivot = CGPoint(x: 262, y: 40)
    /// The stylus when the arm rests on the record.
    static let stylus = CGPoint(x: 200, y: 200)
    /// Rotation in degrees: 0 on the record, negative lifts the arm off to the right. At rest the arm leans out
    /// past straight down, as a real one does when it sits on its rest.
    static let playingAngle = 0.0
    static let restingAngle = -28.0

    /// The angle that points the arm at `pointer`, kept between resting and playing.
    static func angle(pointingAt pointer: CGPoint) -> Double {
        let reference = atan2(stylus.y - pivot.y, stylus.x - pivot.x)
        let target = atan2(pointer.y - pivot.y, pointer.x - pivot.x)
        let degrees = (target - reference) * 180 / .pi
        return min(playingAngle, max(restingAngle, degrees))
    }

    /// Whether an arm let go at `angle` counts as lowered onto the record.
    static func isOnRecord(_ angle: Double) -> Bool {
        angle > (playingAngle + restingAngle) / 2
    }
}
