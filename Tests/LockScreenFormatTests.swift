import Foundation
import Testing

struct LockScreenFormatTests {
    private static func approximately(_ a: RGB, _ b: RGB) -> Bool {
        abs(a.red - b.red) < 1e-9 && abs(a.green - b.green) < 1e-9 && abs(a.blue - b.blue) < 1e-9
    }

    @Test(arguments: [
        (0, LockScreenFormat.batteryLow),
        (19, LockScreenFormat.batteryLow),
        (20, LockScreenFormat.batteryMedium),
        (49, LockScreenFormat.batteryMedium),
        (50, LockScreenFormat.batteryHigh),
        (100, LockScreenFormat.batteryHigh),
    ])
    func batteryTint(_ level: Int, expected: RGB) {
        #expect(LockScreenFormat.batteryTint(level) == expected)
    }

    @Test(arguments: [
        (9, "battery.0percent"),
        (10, "battery.25percent"),
        (39, "battery.25percent"),
        (40, "battery.50percent"),
        (69, "battery.50percent"),
        (70, "battery.75percent"),
        (89, "battery.75percent"),
        (90, "battery.100percent"),
    ])
    func batteryIcon(_ level: Int, expected: String) {
        #expect(LockScreenFormat.batteryIconName(for: level) == expected)
    }

    @Test(arguments: [
        (Int?.none, String?.none),
        (-1, nil),
        (0, nil),
        (59, "59m"),
        (60, "1h 0m"),
        (97, "1h 37m"),
        (0x7fff, nil),
        (0xffff, nil),
    ])
    func chargingTime(_ minutes: Int?, expected: String?) {
        #expect(LockScreenFormat.formattedChargingTime(minutes) == expected)
    }

    /// Past an hour the minutes keep counting: "62:05" fits the 36 pt label.
    @Test(arguments: [
        (Double.nan, "0:00"),
        (.infinity, "0:00"),
        (-1, "0:00"),
        (0, "0:00"),
        (59.4, "0:59"),
        (59.6, "1:00"),
        (3600, "60:00"),
        (3725, "62:05"),
    ])
    func clock(_ seconds: Double, expected: String) {
        #expect(LockScreenFormat.clock(seconds) == expected)
    }

    @Test func sampleSongLoopsAndTheRealOneStops() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let clock = PlaybackClock(anchorElapsed: 62, anchorDate: start, duration: 214, playing: true)
        let later = start.addingTimeInterval(160)
        let looped = LockScreenFormat.progress(of: clock, loops: true, at: later)
        #expect(looped.elapsed == 8)
        #expect(looped.fraction == 8.0 / 214)
        let real = LockScreenFormat.progress(of: clock, loops: false, at: later)
        #expect(real.elapsed == 214)
        #expect(real.fraction == 1)
        // A live stream has no length to loop over.
        let live = PlaybackClock(anchorElapsed: 62, anchorDate: start, duration: 0, playing: true)
        #expect(LockScreenFormat.progress(of: live, loops: true, at: later).fraction == 0)
    }

    @Test func temperatureRampEndsAndMiddles() {
        let ramp = LockScreenFormat.temperatureRamp
        #expect(LockScreenFormat.temperatureColor(for: -40) == ramp[0].color)
        #expect(LockScreenFormat.temperatureColor(for: -15) == ramp[0].color)
        #expect(LockScreenFormat.temperatureColor(for: 38) == ramp[6].color)
        #expect(LockScreenFormat.temperatureColor(for: 45) == ramp[6].color)
        #expect(Self.approximately(LockScreenFormat.temperatureColor(for: 0), ramp[1].color))
        // Halfway between 0° and 10°.
        #expect(Self.approximately(LockScreenFormat.temperatureColor(for: 5), RGB(0.245, 0.71, 0.965)))
    }

    @Test func temperatureGradientSamplesTheRange() {
        let gradient = LockScreenFormat.temperatureGradient(for: 0...10)
        #expect(gradient.count == 12)
        #expect(Self.approximately(gradient[0], LockScreenFormat.temperatureColor(for: 0)))
        #expect(Self.approximately(gradient[11], LockScreenFormat.temperatureColor(for: 10)))
        #expect(LockScreenFormat.temperatureGradient(for: 16...16) == [LockScreenFormat.temperatureColor(for: 16)])
    }

    @Test(arguments: [
        (Double(5), 0.0...10.0, 0.5),
        (-5, 0.0...10.0, 0),
        (15, 0.0...10.0, 1),
        (21, 16.0...27.0, 5.0 / 11),
        (7, 7.0...7.0, 0.5),
    ])
    func gaugeFraction(_ value: Double, range: ClosedRange<Double>, expected: Double) {
        #expect(abs(LockScreenFormat.gaugeFraction(of: value, in: range) - expected) < 1e-9)
    }

    @Test(arguments: [
        (50, RGB(0.20, 0.79, 0.39)),
        (51, RGB(0.97, 0.82, 0.30)),
        (150, RGB(0.98, 0.57, 0.24)),
        (200, RGB(0.91, 0.29, 0.25)),
        (300, RGB(0.65, 0.32, 0.86)),
        (301, RGB(0.50, 0.13, 0.28)),
    ])
    func aqiTint(_ aqi: Int, expected: RGB) {
        #expect(LockScreenFormat.aqiTint(aqi) == expected)
    }

    @Test(arguments: [
        (Int?.some(0), "sun.max.fill"),
        (2, "cloud.sun.fill"),
        (3, "cloud.fill"),
        (48, "cloud.fog.fill"),
        (61, "cloud.rain.fill"),
        (82, "cloud.rain.fill"),
        (75, "cloud.snow.fill"),
        (99, "cloud.bolt.rain.fill"),
        (42, "thermometer.medium"),
        (nil, "thermometer.medium"),
    ])
    func weatherSymbol(_ code: Int?, expected: String) {
        #expect(LockScreenFormat.weatherSymbol(code) == expected)
    }

    private static let countdowns: [(remaining: TimeInterval, text: String)] = [
        (-60, "now"),
        (0, "now"),
        (30, "in 1 min"),
        (60, "in 1 min"),
        (61, "in 2 min"),
        (3540, "in 59 min"),
        (3600, "in 1h"),
        (3660, "in 1h 1m"),
        (7500, "in 2h 5m"),
    ]

    @Test(arguments: countdowns)
    func reminderCountdown(_ remaining: TimeInterval, expected: String) {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        #expect(LockScreenFormat.relativeDescription(due: now.addingTimeInterval(remaining), now: now) == expected)
    }
}
