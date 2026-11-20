import Foundation

/// The turning angle of the record. It turns at a constant speed while playing and holds its angle when paused.
struct VinylSpin: Equatable, Sendable {
    /// 33⅓ revolutions per minute.
    static let degreesPerSecond = 200.0

    private var restingAngle = 0.0
    private var spinningSince: Date?

    var isSpinning: Bool { spinningSince != nil }

    /// The angle in degrees, in 0..<360.
    func angle(at date: Date) -> Double {
        guard let spinningSince else { return restingAngle }
        let turned = date.timeIntervalSince(spinningSince) * Self.degreesPerSecond
        return (restingAngle + turned).truncatingRemainder(dividingBy: 360)
    }

    mutating func setSpinning(_ spinning: Bool, at date: Date) {
        if spinning {
            if spinningSince == nil { spinningSince = date }
        } else if spinningSince != nil {
            restingAngle = angle(at: date)
            spinningSince = nil
        }
    }
}
