import CoreGraphics
import Foundation
import Testing

struct VinylTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 5_000)

    @Test func recordTurnsTwoHundredDegreesPerSecondWhileSpinning() {
        var spin = VinylSpin()
        spin.setSpinning(true, at: Self.start)
        #expect(abs(spin.angle(at: Self.start.addingTimeInterval(0.5)) - 100) < 0.001)
        // 2 s = 400°, one full turn and 40°.
        #expect(abs(spin.angle(at: Self.start.addingTimeInterval(2)) - 40) < 0.001)
    }

    @Test func recordHoldsItsAngleWhenPaused() {
        var spin = VinylSpin()
        spin.setSpinning(true, at: Self.start)
        spin.setSpinning(false, at: Self.start.addingTimeInterval(0.9))
        #expect(abs(spin.angle(at: Self.start.addingTimeInterval(60)) - 180) < 0.001)
        #expect(!spin.isSpinning)
    }

    @Test(arguments: [(-28.0, false), (-14.0, false), (-13.9, true), (0.0, true)])
    func armCountsAsLoweredPastTheMiddle(angle: Double, expected: Bool) {
        #expect(TonearmGeometry.isOnRecord(angle) == expected)
    }

    @Test func armPointedAtTheStylusLiesOnTheRecord() {
        #expect(abs(TonearmGeometry.angle(pointingAt: TonearmGeometry.stylus)) < 0.001)
    }

    @Test(arguments: [
        ("com.apple.Music", true), ("com.spotify.client", false), (nil, false),
    ])
    func onlyMusicUsesTheRecord(bundleIdentifier: String?, expected: Bool) {
        #expect(VinylSource.isRecordPlayer(bundleIdentifier: bundleIdentifier) == expected)
    }

    @Test func lockRecordSitsWhereTheArtworkWouldAndTheArmFitsTheTurntable() {
        let screen = CGSize(width: 1512, height: 982)
        let record = LockVinylLayout.recordFrame(in: screen)
        let turntable = LockVinylLayout.turntableFrame(in: screen)
        // 60 % of 34 % of 982 pt.
        #expect(abs(record.width - 0.6 * 0.34 * 982) < 0.001)
        #expect(abs(record.midX - 756) < 0.001)
        #expect(abs(record.midY - (0.36 * 982 + 50)) < 0.001)
        // The record's centre sits at (130, 150) of the 300-unit turntable.
        let scale = turntable.width / 300
        #expect(abs(turntable.minX + 130 * scale - record.midX) < 0.001)
        #expect(abs(turntable.minY + 150 * scale - record.midY) < 0.001)
        #expect(turntable.contains(record))
    }
}
