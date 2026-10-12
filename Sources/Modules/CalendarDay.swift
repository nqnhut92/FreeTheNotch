import Foundation

/// One cell of the month grid.
struct CalendarDay: Identifiable {
    let id = UUID()
    let date: Date?
    /// False for days from the previous or next month, shown dimmed.
    var isCurrentMonth: Bool = true

    var number: Int {
        guard let date else { return 0 }
        return Calendar.current.component(.day, from: date)
    }
}

extension CalendarDay {
    /// The Monday-first grid for the month that starts at `month`: whole
    /// weeks, padded with the adjacent months' days.
    static func monthGrid(startingAt month: Date, calendar: Calendar) -> [CalendarDay] {
        guard let dayCount = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let weekday = calendar.component(.weekday, from: month)  // 1 is Sunday.
        let leadingCount = (weekday + 5) % 7
        let currentMonth = leadingCount..<(leadingCount + dayCount)
        let cellCount = (currentMonth.upperBound + 6) / 7 * 7
        return (0..<cellCount).compactMap { cell in
            calendar.date(byAdding: .day, value: cell - leadingCount, to: month).map {
                CalendarDay(date: $0, isCurrentMonth: currentMonth.contains(cell))
            }
        }
    }
}
