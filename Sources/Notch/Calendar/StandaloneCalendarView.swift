// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// components/Calendar/DynamicIslandCalendar.swift — StandaloneCalendarView
// (month picker pane + events pane).

import SwiftUI

/// Full-width calendar shown when nothing is playing.
struct StandaloneCalendarView: View {
    @EnvironmentObject var calendar: CalendarStore
    @EnvironmentObject var settings: SettingsStore
    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(minimum: 14), spacing: 6), count: 7)
    /// Monday first, like the month grid (`CalendarDay.monthGrid`).
    private static let weekdayInitials = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leftPickerPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            rightEventsPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(.white)
        .onAppear {
            calendar.requestAccessIfNeeded()
            let today = cal.startOfDay(for: Date())
            calendar.selectedDay = today
            calendar.showMonth(containing: today)
        }
        .onChange(of: calendar.selectedDay) { _, newDate in
            withAnimation(.smooth(duration: 0.22)) {
                calendar.showMonth(containing: newDate)
            }
        }
    }

    private var monthTitle: String {
        calendar.monthCursor.formatted(.dateTime.month(.wide))
    }

    private var yearTitle: String {
        calendar.monthCursor.formatted(.dateTime.year())
    }

    private var leftPickerPane: some View {
        VStack(alignment: .leading, spacing: StandaloneCalendarMetrics.sectionSpacing) {
            HStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(monthTitle)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(yearTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.notchSecondary)
                    if settings.showLunarDate {
                        // Lunar date of the selected day, like iOS Calendar's alternate calendar.
                        Text("· " + LunarCalendar.lunarDate(for: calendar.selectedDay).displayText)
                            .font(.caption)
                            .foregroundStyle(Color(white: 0.55))
                            .lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    Button {
                        showMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button {
                        showMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: StandaloneCalendarMetrics.headerHeight)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Self.weekdayInitials.indices, id: \.self) { i in
                    Text(Self.weekdayInitials[i])
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(white: 0.55))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: StandaloneCalendarMetrics.weekdayRowHeight)

            // Atoll scrolls the weeks inside a fixed-height pane; here the
            // island is as tall as this month's weeks (4–6 rows), so the
            // whole month shows without scrolling.
            LazyVGrid(columns: columns, spacing: StandaloneCalendarMetrics.rowSpacing) {
                ForEach(calendar.gridDays) { day in
                    if let date = day.date {
                        dayCell(for: date, isCurrentMonth: day.isCurrentMonth)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, StandaloneCalendarMetrics.topPadding)
    }

    private func dayCell(for day: Date, isCurrentMonth: Bool) -> some View {
        let isSelected = cal.isDate(day, inSameDayAs: calendar.selectedDay)
        let isToday = cal.isDateInToday(day)
        return Button {
            withAnimation(.smooth(duration: 0.18)) {
                calendar.selectedDay = cal.startOfDay(for: day)
            }
        } label: {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 28, height: 28)
                }
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(
                        dayTextColor(isCurrentMonth: isCurrentMonth, isSelected: isSelected, isToday: isToday))
            }
            .frame(maxWidth: .infinity)
            .frame(height: StandaloneCalendarMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayTextColor(isCurrentMonth: Bool, isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if !isCurrentMonth { return Color(white: 0.35) }
        if isToday { return .accentColor }
        return .white
    }

    /// Atoll's showPreviousMonth / showNextMonth: select the 1st of that month.
    private func showMonth(by delta: Int) {
        guard let month = cal.date(byAdding: .month, value: delta, to: calendar.monthCursor) else { return }
        withAnimation(.smooth(duration: 0.22)) {
            calendar.selectedDay = cal.startOfDay(for: month)
        }
    }

    private var rightEventsPane: some View {
        Group {
            if calendar.eventsForSelectedDay.isEmpty && calendar.remindersForSelectedDay.isEmpty {
                EmptyEventsView(selectedDate: calendar.selectedDay)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StandaloneEventCardList(selectedDate: calendar.selectedDay)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}
