// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// components/Calendar/DynamicIslandCalendar.swift — WheelPicker's Config and
// its index helpers.

import Foundation

/// Item layout of the date strip: spacer cells at both ends around one cell
/// per day. Atoll's `Config` defaults: 7 days back, 14 ahead, one day per
/// step, two spacers each side.
struct WeekWheelLayout {
    var past = 7
    var future = 14
    var steps = 1
    var spacerCount = 2

    private var step: Int { max(steps, 1) }

    var dateCount: Int { Int(ceil(Double(past + future) / Double(step))) + 1 }

    /// Spacers and dates together.
    var itemCount: Int { dateCount + 2 * spacerCount }

    var dateIndices: Range<Int> { spacerCount..<(spacerCount + dateCount) }

    /// Index of the cell for `date`, clamped to the strip.
    func index(for date: Date, today: Date, calendar: Calendar) -> Int {
        let first = calendar.startOfDay(for: firstDate(today: today, calendar: calendar))
        let days = calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: date)).day ?? 0
        return spacerCount + max(0, min(days / step, dateCount - 1))
    }

    /// Day shown by the cell at `index` (a date index, not a spacer).
    func date(at index: Int, today: Date, calendar: Calendar) -> Date {
        let first = firstDate(today: today, calendar: calendar)
        return calendar.date(byAdding: .day, value: (index - spacerCount) * step, to: first)
            ?? calendar.startOfDay(for: today)
    }

    /// Where a press-drag that started at `start` and moved `steps` cells
    /// lands. Like Atoll, it can run onto the trailing spacers, which select
    /// nothing.
    func dragTarget(from start: Int, movedBy steps: Int) -> Int {
        min(max(spacerCount, start + steps), itemCount - 1)
    }

    private func firstDate(today: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: today)
        return calendar.date(byAdding: .day, value: -past, to: start) ?? start
    }
}
