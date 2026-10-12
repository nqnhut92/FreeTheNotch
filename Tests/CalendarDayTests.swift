import Foundation
import Testing

struct CalendarDayTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }()

    private func firstDay(year: Int, month: Int) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    /// Every month of 2026–2028, including those that end on a Sunday
    /// (May 2026, January and February 2027), which once crashed the grid.
    @Test(arguments: 2026...2028, 1...12)
    func gridIsWholeMondayFirstWeeksAroundTheMonth(year: Int, month: Int) throws {
        let start = firstDay(year: year, month: month)
        let grid = CalendarDay.monthGrid(startingAt: start, calendar: Self.calendar)
        let dayCount = try #require(Self.calendar.range(of: .day, in: .month, for: start)).count

        #expect(grid.count % 7 == 0)
        let firstCell = try #require(grid.first?.date)
        let lastCell = try #require(grid.last?.date)
        #expect(Self.calendar.component(.weekday, from: firstCell) == 2)
        #expect(Self.calendar.component(.weekday, from: lastCell) == 1)

        let currentMonth = grid.filter(\.isCurrentMonth)
        #expect(currentMonth.map(\.number) == Array(1...dayCount))
        #expect(currentMonth.first?.date == start)
        #expect(grid.count - currentMonth.count < 14)
    }

    @Test func monthStartingOnMondayWithFourWeeksHasNoPadding() {
        // February 2027 starts on a Monday and has 28 days.
        let grid = CalendarDay.monthGrid(startingAt: firstDay(year: 2027, month: 2), calendar: Self.calendar)
        #expect(grid.count == 28)
        #expect(grid.allSatisfy { $0.isCurrentMonth })
    }

    @Test func consecutiveCellsAreConsecutiveDays() {
        let grid = CalendarDay.monthGrid(startingAt: firstDay(year: 2026, month: 3), calendar: Self.calendar)
        let dates = grid.compactMap(\.date)
        #expect(dates.count == grid.count)
        for (earlier, later) in zip(dates, dates.dropFirst()) {
            #expect(Self.calendar.dateComponents([.day], from: earlier, to: later).day == 1)
        }
    }
}
