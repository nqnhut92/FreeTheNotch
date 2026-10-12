import Foundation
import Testing

struct LunarCalendarTests {
    typealias Astronomy = LunarCalendar.Astronomy

    // MARK: - Astronomy

    @Test func newMoonMatchesMeeusExample49a() {
        // Meeus, example 49.a: the new moon of 1977 February 18.
        #expect(abs(Astronomy.newMoon(lunation: -283) - 2_443_192.65118) < 0.00001)
    }

    @Test func solarLongitudeMatchesMeeusExample25a() {
        // Meeus, example 25.a: 1992 October 13.0 TD.
        #expect(abs(Astronomy.apparentSolarLongitude(julianEphemerisDay: 2_448_908.5) - 199.90895) < 0.0001)
    }

    @Test func newMoonOfTheApril2024EclipseIsWithinTwoMinutes() {
        // The total solar eclipse of 2024-04-08: new moon at 18:21 UT.
        let lunation = Astronomy.lunation(near: Double(LunarCalendar.CivilDay.number(year: 2024, month: 4, day: 8)))
        let instant = Astronomy.universalTime(Astronomy.newMoon(lunation: lunation))
        let hours = (instant + 0.5).truncatingRemainder(dividingBy: 1) * 24
        #expect(abs(hours - (18 + 21.0 / 60)) < 2.0 / 60)
    }

    @Test func decemberSolstice2026IsWithinFiveMinutes() {
        // 2026-12-21 20:50 UT, which is already December 22 in Vietnam.
        let instant = Astronomy.universalTime(Astronomy.decemberSolstice(year: 2026))
        let hours = (instant + 0.5).truncatingRemainder(dividingBy: 1) * 24
        #expect(abs(hours - (20 + 50.0 / 60)) < 5.0 / 60)
        #expect(
            LunarCalendar.CivilDay.of(julianDay: instant)
                == LunarCalendar.CivilDay.number(year: 2026, month: 12, day: 22))
    }

    // MARK: - Calendar

    /// Tết in Vietnam. 1968, 1985 and 2007 differ from China's calendar
    /// (UTC+8), so they guard the UTC+7 reckoning.
    @Test(arguments: [
        (1968, 1, 29), (1985, 1, 21), (2007, 2, 17), (2020, 1, 25), (2021, 2, 12),
        (2022, 2, 1), (2023, 1, 22), (2024, 2, 10), (2025, 1, 29), (2026, 2, 17), (2027, 2, 6),
    ])
    func tetFallsOnTheFirstDayOfTheFirstMonth(year: Int, month: Int, day: Int) {
        let tet = LunarCalendar.lunarDate(year: year, month: month, day: day)
        #expect(tet == LunarCalendar.LunarDate(day: 1, month: 1, year: year, isLeapMonth: false))

        let eve = CivilDate(year: year, month: month, day: day).adding(days: -1)
        let lastDay = LunarCalendar.lunarDate(year: eve.year, month: eve.month, day: eve.day)
        #expect(lastDay.month == 12 && lastDay.year == year - 1 && !lastDay.isLeapMonth)
    }

    @Test(arguments: [(2017, 6), (2020, 4), (2023, 2), (2025, 6), (2028, 5)])
    func leapMonthOfYear(year: Int, leapMonth: Int) {
        let leapMonths = Set(
            CivilDate(year: year, month: 1, day: 1).days(through: CivilDate(year: year, month: 12, day: 31))
                .map { LunarCalendar.lunarDate(year: $0.year, month: $0.month, day: $0.day) }
                .filter(\.isLeapMonth)
                .map(\.month)
        )
        #expect(leapMonths == [leapMonth])
    }

    /// Day by day, the lunar date either advances by one or starts a new
    /// month of 29 or 30 days, and each lunar year has at most one leap month.
    @Test func consecutiveDaysAreConsistentFrom1950To2100() {
        var previous = LunarCalendar.lunarDate(year: 1949, month: 12, day: 31)
        var leapMonthsByYear: [Int: Set<Int>] = [:]
        for date in CivilDate(year: 1950, month: 1, day: 1).days(through: CivilDate(year: 2100, month: 12, day: 31)) {
            let current = LunarCalendar.lunarDate(year: date.year, month: date.month, day: date.day)
            if current.day == 1 {
                #expect(previous.day == 29 || previous.day == 30, "\(date)")
                let isNextMonth =
                    current.isLeapMonth
                    ? current.month == previous.month && !previous.isLeapMonth
                    : current.month == previous.month % 12 + 1
                #expect(isNextMonth, "\(date)")
                #expect(current.year == previous.year + (current.month == 1 && !current.isLeapMonth ? 1 : 0), "\(date)")
            } else {
                #expect(current.day == previous.day + 1, "\(date)")
                #expect(current.month == previous.month && current.isLeapMonth == previous.isLeapMonth, "\(date)")
            }
            if current.isLeapMonth { leapMonthsByYear[current.year, default: []].insert(current.month) }
            previous = current
        }
        #expect(leapMonthsByYear.values.allSatisfy { $0.count == 1 })
    }

    @Test func lunarDateForDateUsesTheGivenCalendarsDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // 2026-02-17 01:00 UTC is still February 16 in Los Angeles.
        let instant = Date(timeIntervalSince1970: 1_771_290_000)
        #expect(
            LunarCalendar.lunarDate(for: instant, calendar: calendar)
                == LunarCalendar.lunarDate(year: 2026, month: 2, day: 16))
    }

    // MARK: - Names

    @Test(arguments: [(1984, "Giáp Tý"), (1900, "Canh Tý"), (2026, "Bính Ngọ"), (2043, "Quý Hợi"), (1800, "Canh Thân")])
    func canChi(year: Int, name: String) {
        #expect(LunarCalendar.canChi(year: year) == name)
    }

    @Test func displayTextMarksLeapMonths() {
        #expect(
            LunarCalendar.LunarDate(day: 1, month: 9, year: 2026, isLeapMonth: false).displayText == "1/9 năm Bính Ngọ")
        #expect(
            LunarCalendar.LunarDate(day: 15, month: 4, year: 2020, isLeapMonth: true).displayText
                == "15/4 nhuận năm Canh Tý")
    }
}

/// A Gregorian calendar day, for walking ranges of days in tests.
private struct CivilDate: CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    func adding(days: Int) -> CivilDate {
        let date = Self.calendar.date(from: DateComponents(year: year, month: month, day: day + days))!
        let components = Self.calendar.dateComponents([.year, .month, .day], from: date)
        return CivilDate(year: components.year!, month: components.month!, day: components.day!)
    }

    func days(through end: CivilDate) -> [CivilDate] {
        let start = Self.calendar.date(from: DateComponents(year: year, month: month, day: day))!
        let last = Self.calendar.date(from: DateComponents(year: end.year, month: end.month, day: end.day))!
        let count = Self.calendar.dateComponents([.day], from: start, to: last).day!
        return (0...count).map { adding(days: $0) }
    }
}
