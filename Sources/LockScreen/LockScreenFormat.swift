import Foundation

/// An sRGB colour as plain numbers, so the lock screen's colour rules can be
/// compared in tests. `Color(_:)` turns it into a SwiftUI colour.
struct RGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// The colour `t` of the way (0…1) from `self` to `other`.
    func mixed(with other: RGB, by t: Double) -> RGB {
        RGB(red + (other.red - red) * t, green + (other.green - green) * t, blue + (other.blue - blue) * t)
    }
}

/// Labels, colours and symbols for the lock-screen widgets, mostly Atoll's
/// (LockScreenWeatherWidget, LockScreenReminderWidget).
enum LockScreenFormat {
    // MARK: Battery

    static let batteryLow = RGB(0.91, 0.29, 0.25)
    static let batteryMedium = RGB(0.98, 0.57, 0.24)
    static let batteryHigh = RGB(0.20, 0.79, 0.39)

    static func batteryTint(_ level: Int) -> RGB {
        switch level {
        case ..<20: return batteryLow
        case ..<50: return batteryMedium
        default: return batteryHigh
        }
    }

    /// Atoll's battery icon names by level.
    static func batteryIconName(for level: Int) -> String {
        switch level {
        case ..<10: return "battery.0percent"
        case ..<40: return "battery.25percent"
        case ..<70: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// IOPowerSources reports 0xFFFF (and -1 or 0) while it is still
    /// estimating; anything at or above this is not a real time.
    static let unknownChargingMinutes = 0x7fff

    /// Atoll's charging time format: "1h 37m", "45m". Nil while macOS has no
    /// estimate yet.
    static func formattedChargingTime(_ minutes: Int?) -> String? {
        guard let minutes, minutes > 0, minutes < unknownChargingMinutes else { return nil }
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }

    // MARK: Media

    /// A media position: "3:07". Past an hour the minutes keep counting
    /// ("62:05"): the lock screen's time labels are 36 pt wide.
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0, seconds < Double(Int.max) else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Elapsed seconds and the seek bar's fraction at `date`. The Settings
    /// preview's sample song loops instead of stopping at its end.
    static func progress(of clock: PlaybackClock, loops: Bool, at date: Date) -> (elapsed: Double, fraction: Double) {
        guard loops, clock.duration > 0 else {
            return (clock.elapsed(at: date), clock.fraction(at: date))
        }
        let raw = clock.anchorElapsed + date.timeIntervalSince(clock.anchorDate)
        let elapsed = raw.truncatingRemainder(dividingBy: clock.duration)
        return (elapsed, elapsed / clock.duration)
    }

    // MARK: Weather

    /// Atoll's temperature ramp: interpolated, not stepped. A stepped scale
    /// paints both ends of the arc the same colour and the gradient disappears.
    static let temperatureRamp: [(celsius: Double, color: RGB)] = [
        (-15, RGB(0.36, 0.44, 0.95)),
        (0, RGB(0.29, 0.63, 1.00)),
        (10, RGB(0.20, 0.79, 0.93)),
        (18, RGB(0.20, 0.79, 0.39)),
        (24, RGB(0.95, 0.77, 0.25)),
        (30, RGB(0.97, 0.58, 0.29)),
        (38, RGB(0.91, 0.29, 0.25)),
    ]

    static func temperatureColor(for celsius: Double) -> RGB {
        guard let first = temperatureRamp.first, let last = temperatureRamp.last else { return RGB(1, 1, 1) }
        if celsius <= first.celsius { return first.color }
        if celsius >= last.celsius { return last.color }
        for (lower, upper) in zip(temperatureRamp, temperatureRamp.dropFirst()) where celsius <= upper.celsius {
            let span = upper.celsius - lower.celsius
            return lower.color.mixed(with: upper.color, by: span > 0 ? (celsius - lower.celsius) / span : 0)
        }
        return last.color
    }

    /// The temperature arc's gradient, sampled across the day's range
    /// (Atoll-style). One colour when the range is empty.
    static func temperatureGradient(for range: ClosedRange<Double>, samples: Int = 12) -> [RGB] {
        let span = range.upperBound - range.lowerBound
        guard span > 0, samples > 1 else { return [temperatureColor(for: range.lowerBound)] }
        return (0..<samples).map { step in
            temperatureColor(for: range.lowerBound + span * (Double(step) / Double(samples - 1)))
        }
    }

    /// Where a reading sits across a range, 0 at the low end and 1 at the
    /// high; the middle when the range is empty.
    static func gaugeFraction(of value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0.5 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    /// The AQI ring is full at this value (US EPA "Hazardous" starts above it).
    static let aqiScaleMaximum = 300

    /// Atoll's AQI colours (US EPA breakpoints).
    static func aqiTint(_ aqi: Int) -> RGB {
        switch aqi {
        case ..<51: return RGB(0.20, 0.79, 0.39)  // Good
        case ..<101: return RGB(0.97, 0.82, 0.30)  // Moderate
        case ..<151: return RGB(0.98, 0.57, 0.24)  // Unhealthy for sensitive groups
        case ..<201: return RGB(0.91, 0.29, 0.25)  // Unhealthy
        case ..<301: return RGB(0.65, 0.32, 0.86)  // Very unhealthy
        default: return RGB(0.50, 0.13, 0.28)  // Hazardous
        }
    }

    /// SF Symbol for an Open-Meteo WMO weather code.
    static func weatherSymbol(_ code: Int?) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 61, 63, 65, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "thermometer.medium"
        }
    }

    // MARK: Reminders

    /// Atoll's relative description: "now", "in 1 min", "in 12 min",
    /// "in 2h", "in 2h 5m". Minutes round up, so a reminder 30 s away
    /// reads "in 1 min".
    static func relativeDescription(due: Date, now: Date) -> String {
        let remaining = due.timeIntervalSince(now)
        guard remaining > 0 else { return "now" }
        let minutes = Int(ceil(remaining / 60))
        if minutes < 60 { return minutes == 1 ? "in 1 min" : "in \(minutes) min" }
        let hours = minutes / 60
        let mins = minutes % 60
        return mins == 0 ? "in \(hours)h" : "in \(hours)h \(mins)m"
    }
}
