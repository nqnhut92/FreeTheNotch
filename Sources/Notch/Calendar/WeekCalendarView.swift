// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// components/Calendar/DynamicIslandCalendar.swift — CalendarView (the column
// beside the player) and WheelPicker.

import SwiftUI

/// Column beside the player. Collapsed: one "Fri, Oct 9" line and the events
/// fill the column. Hovering the header expands month/year and the date strip.
struct WeekCalendarView: View {
    @EnvironmentObject var calendar: CalendarStore
    @EnvironmentObject var settings: SettingsStore
    @State private var dateExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    if dateExpanded {
                        Text(calendar.selectedDay.formatted(.dateTime.month(.abbreviated)))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        Text(calendar.selectedDay.formatted(.dateTime.year()))
                            .font(.caption)
                            .fontWeight(.regular)
                            .foregroundStyle(.notchSecondary)
                    } else {
                        Text(calendar.selectedDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize()
                        if settings.showLunarDate {
                            Text(LunarCalendar.lunarDate(for: calendar.selectedDay).displayText)
                                .font(.caption2)
                                .foregroundStyle(Color(white: 0.6))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
                .frame(width: 100, alignment: .leading)

                ZStack {
                    WeekWheelPicker(selectedDate: $calendar.selectedDay)
                        .frame(maxWidth: .infinity)
                    // Edge fades over the horizontally scrolling strip.
                    LinearGradient(
                        colors: [Color.black.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 16)
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.45)], startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 16)
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(height: dateExpanded ? 50 : 0)
                .opacity(dateExpanded ? 1 : 0)
                .allowsHitTesting(dateExpanded)
                .clipped()
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .contentShape(Rectangle())
            .onHover { inside in
                withAnimation(.easeInOut(duration: 0.18)) {
                    dateExpanded = inside
                }
            }

            if calendar.eventsForSelectedDay.isEmpty && calendar.remindersForSelectedDay.isEmpty {
                EmptyEventsView(selectedDate: calendar.selectedDay)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EventListView(selectedDate: calendar.selectedDay)
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            calendar.requestAccessIfNeeded()
            // Atoll resets the selection to today whenever the island opens.
            calendar.selectedDay = Calendar.current.startOfDay(for: Date())
        }
    }
}

private struct CellWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Horizontally scrolling date strip that snaps the selected day to the
/// center. Trackpad scroll, click and mouse press-drag all change the day.
private struct WeekWheelPicker: View {
    @Binding var selectedDate: Date
    @State private var scrollPosition: Int?
    /// Set when the code moves the strip, so the scroll-position change it
    /// causes does not select a day a second time.
    @State private var byClick = false
    @State private var dragAnchorPos: Int?
    @State private var measuredCellWidth: CGFloat = 40
    private let layout = WeekWheelLayout()

    private static let dayNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter
    }()

    private var calendar: Calendar { .current }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                let today = Date()
                ForEach(0..<layout.itemCount, id: \.self) { index in
                    if layout.dateIndices.contains(index) {
                        let date = layout.date(at: index, today: today, calendar: calendar)
                        dateButton(date: date, isSelected: calendar.isDate(date, inSameDayAs: selectedDate), id: index)
                        {
                            selectedDate = calendar.startOfDay(for: date)
                            byClick = true
                            withAnimation {
                                scrollPosition = index
                            }
                        }
                    } else {
                        Spacer()
                            .frame(width: 24, height: 24)
                            .id(index)
                    }
                }
            }
            .frame(height: 50)
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .safeAreaPadding(.horizontal)
        .onChange(of: scrollPosition) { _, newValue in
            if !byClick {
                handleScrollChange(newValue: newValue)
            } else {
                byClick = false
            }
        }
        .onAppear { scrollToToday() }
        .onChange(of: selectedDate) { _, newValue in
            let targetIndex = layout.index(for: newValue, today: Date(), calendar: calendar)
            if scrollPosition != targetIndex {
                byClick = true
                withAnimation {
                    scrollPosition = targetIndex
                }
            }
        }
        .onPreferenceChange(CellWidthKey.self) { measuredCellWidth = $0 }
        // A mouse has no horizontal scroll; press-drag scrubs the dates.
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if dragAnchorPos == nil { dragAnchorPos = scrollPosition }
                    guard let start = dragAnchorPos, measuredCellWidth > 1 else { return }
                    let steps = Int((-value.translation.width / measuredCellWidth).rounded())
                    let newPos = layout.dragTarget(from: start, movedBy: steps)
                    if newPos != scrollPosition {
                        withTransaction(Transaction(animation: nil)) {
                            scrollPosition = newPos
                        }
                    }
                }
                .onEnded { _ in dragAnchorPos = nil }
        )
    }

    /// Atoll's dateButton: weekday above, today = accent circle,
    /// selected = accent 25% background.
    private func dateButton(date: Date, isSelected: Bool, id: Int, onClick: @escaping () -> Void) -> some View {
        let isToday = calendar.isDateInToday(date)
        return Button(action: onClick) {
            VStack(spacing: 8) {
                Text(Self.dayNameFormatter.string(from: date))
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white : .notchSecondary)
                ZStack {
                    Circle()
                        .fill(isToday ? Color.accentColor : .clear)
                        .frame(width: 20, height: 20)
                    Text("\(calendar.component(.day, from: date))")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(isSelected ? Color.white : Color(white: isToday ? 0.9 : 0.65))
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .id(id)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: CellWidthKey.self, value: geo.size.width)
            })
    }

    private func handleScrollChange(newValue: Int?) {
        guard let newIndex = newValue, layout.dateIndices.contains(newIndex) else { return }
        let date = layout.date(at: newIndex, today: Date(), calendar: calendar)
        if !calendar.isDate(date, inSameDayAs: selectedDate) {
            selectedDate = calendar.startOfDay(for: date)
        }
    }

    private func scrollToToday() {
        byClick = true
        scrollPosition = layout.index(for: Date(), today: Date(), calendar: calendar)
        selectedDate = calendar.startOfDay(for: Date())
    }
}
