import Foundation

/// Number formats of the menu-bar panel, after Vorssaint's MetricFormat
/// (vorssaint/vorssaint-utils, GPL-3.0-or-later). Decimal separators follow
/// the Mac's locale ("7,3 KB" in Vietnamese).
enum PanelFormat {
    private static let byteUnits = ["B", "KB", "MB", "GB", "TB", "PB"]

    /// 1024-based: "506 KB", "926 KB", "26 MB".
    static func bytes(_ bytes: Double, locale: Locale = .current) -> String {
        scaled(bytes, base: 1024, units: byteUnits, locale: locale) { _, _ in 0 }
    }

    /// 1000-based disk sizes: <10 -> "7,3 KB", >=10 -> "616 GB".
    static func diskBytes(_ bytes: Double, locale: Locale = .current) -> String {
        scaled(bytes, base: 1000, units: byteUnits, locale: locale) { unit, value in
            unit > 0 && value < 10 ? 1 : 0
        }
    }

    /// Precise disk sizes for SMART: TB -> "42,59 TB".
    static func diskBytesPrecise(_ bytes: Double, locale: Locale = .current) -> String {
        scaled(bytes, base: 1000, units: byteUnits, locale: locale) { unit, value in
            unit >= 4 ? 2 : (value < 10 ? 1 : 0)
        }
    }

    /// Transfer rate, 1024-based: "3,3 KB/s".
    static func rate(_ bps: Double, locale: Locale = .current) -> String {
        scaled(bps, base: 1024, units: ["B/s", "KB/s", "MB/s", "GB/s"], locale: locale) { unit, value in
            unit > 0 && value < 10 ? 1 : 0
        }
    }

    /// Bit rate, 1000-based: "45,2 Mbps".
    static func bits(_ bps: Double, locale: Locale = .current) -> String {
        scaled(bps, base: 1000, units: ["bps", "Kbps", "Mbps", "Gbps"], locale: locale) { unit, value in
            unit > 0 && value < 10 ? 1 : 0
        }
    }

    /// "25 W", "8,5 W".
    static func watts(_ w: Double, locale: Locale = .current) -> String {
        String(format: w < 10 ? "%.1f W" : "%.0f W", locale: locale, w)
    }

    /// "81 °C". Celsius only.
    static func temperature(celsius: Double?, locale: Locale = .current) -> String {
        guard let celsius else { return "-" }
        return String(format: "%.0f °C", locale: locale, celsius)
    }

    /// 0…1 -> "25%".
    static func percent(_ fraction: Double, locale: Locale = .current) -> String {
        String(format: "%.0f%%", locale: locale, fraction * 100)
    }

    /// Vorssaint's MetricFormat.uptime: "3d 4h", "4h 12min", "12min".
    static func uptime(_ seconds: TimeInterval) -> String {
        let secondsPerMinute = 60
        let secondsPerHour = 60 * secondsPerMinute
        let secondsPerDay = 24 * secondsPerHour
        let total = max(0, Int(seconds))
        let days = total / secondsPerDay
        let hours = (total % secondsPerDay) / secondsPerHour
        let minutes = (total % secondsPerHour) / secondsPerMinute
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)min" }
        return "\(minutes)min"
    }

    /// Memory sizes: "34,56 GB", "Zero KB".
    static func memory(_ bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        return f.string(fromByteCount: Int64(bytes))
    }

    /// Vorssaint's MetricFormat.graphCeiling: the peak rounded up to 1, 2 or 5
    /// of a unit, so the label reads "2.0 MB/s" and only moves when traffic
    /// crosses a step. `unitStep` is 1024 for byte rates, 1000 for watts.
    static func graphCeiling(_ peak: Double, unitStep: Double) -> Double {
        for power in 0..<6 {
            for step in [1.0, 2, 5, 10, 20, 50, 100, 200, 500] {
                let ceiling = step * pow(unitStep, Double(power))
                if ceiling >= peak { return ceiling }
            }
        }
        return peak
    }

    /// Divides by `base` until the value fits its unit, then prints it with
    /// `decimals(unitIndex, value)` fraction digits. A value that rounds up
    /// to the next unit moves there ("1 MB", not "1024 KB"), and one that
    /// rounds up to a coarser precision takes it ("10 KB", not "10,0 KB").
    private static func scaled(
        _ value: Double, base: Double, units: [String], locale: Locale,
        decimals: (_ unit: Int, _ value: Double) -> Int
    ) -> String {
        func rounded(_ v: Double, _ digits: Int) -> Double {
            let scale = pow(10, Double(digits))
            return (v * scale).rounded() / scale
        }
        var v = value
        var unit = 0
        while v >= base, unit < units.count - 1 {
            v /= base
            unit += 1
        }
        var digits = decimals(unit, v)
        if unit < units.count - 1, rounded(v, digits) >= base {
            v /= base
            unit += 1
            digits = decimals(unit, v)
        }
        digits = min(digits, decimals(unit, rounded(v, digits)))
        return String(format: "%.*f %@", locale: locale, digits, v, units[unit])
    }
}
