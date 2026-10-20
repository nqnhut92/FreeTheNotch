import Foundation

/// Short quota reset times for one notch row: the time alone today, a weekday within the coming week,
/// otherwise the date. All parts follow the user's locale.
enum AIUsageResetFormat {
    private static let weekdayRangeDays = 6

    static func text(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        if days == 0 {
            style = style.hour().minute()
        } else if (1...weekdayRangeDays).contains(days) {
            style = style.weekday(.abbreviated).hour().minute()
        } else {
            style = style.day().month(.abbreviated).hour().minute()
        }
        return date.formatted(style)
    }
}
