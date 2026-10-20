// Ported from Atoll (github.com/Ebullioscopic/Atoll), GPL-3.0-or-later:
// components/Calendar/DynamicIslandCalendar.swift — EventListView,
// StandaloneEventCardList, AllDayEventsStrip, ConferenceJoinButton and
// EmptyEventsView. Reminders use our ReminderCard (Atoll's reminderCard);
// "auto scroll to next event" is Atoll's default (on).

import SwiftUI

private enum AllDayStripMetrics {
    static let chipRowHeight: CGFloat = 28
    static let verticalPadding: CGFloat = 3
    static let listTopInset: CGFloat = 30
}

/// What both event lists share: the rows in a plain List that scrolls to the
/// relevant event, with the all-day strip pinned over its top.
private struct AgendaList<Rows: View>: View {
    let selectedDate: Date
    let events: AgendaDayEvents
    @ViewBuilder let rows: Rows
    @State private var initialAutoScrollDone = false

    var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                List { rows }
                    .listStyle(.plain)
                    .scrollIndicators(.never)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.top, events.allDay.isEmpty ? 0 : AllDayStripMetrics.listTopInset)
                    .onAppear {
                        scrollToRelevantEvent(proxy: proxy)
                        if !events.timed.isEmpty { initialAutoScrollDone = true }
                    }
                    .onChange(of: selectedDate) { _, _ in scrollToRelevantEvent(proxy: proxy) }
                    // Events load after the list appears on the first open.
                    .onChange(of: events.timed.isEmpty) { wasEmpty, isEmpty in
                        guard wasEmpty, !isEmpty, !initialAutoScrollDone else { return }
                        scrollToRelevantEvent(proxy: proxy)
                        initialAutoScrollDone = true
                    }
            }

            if !events.allDay.isEmpty {
                AllDayEventsStrip(events: events.allDay)
                    .background(Color.black.opacity(0.95))
            }
        }
    }

    private func scrollToRelevantEvent(proxy: ScrollViewProxy) {
        guard let target = events.scrollTarget(on: selectedDate) else { return }
        // The rows are not laid out yet within the same update.
        DispatchQueue.main.async {
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(target.id, anchor: .center)
            }
        }
    }
}

/// Atoll's EventListView: compact rows with separators, beside the player.
struct EventListView: View {
    @EnvironmentObject var calendar: CalendarStore
    @Environment(\.openURL) private var openURL
    let selectedDate: Date

    var body: some View {
        let events = AgendaDayEvents(calendar.eventsForSelectedDay)
        AgendaList(selectedDate: selectedDate, events: events) {
            ForEach(events.timed) { event in
                Button {
                    if let url = event.calendarAppURL { openURL(url) }
                } label: {
                    eventRow(event)
                }
                .id(event.id)
                .padding(.leading, -5)
                .buttonStyle(.plain)
                .listRowSeparator(.automatic)
                .listRowSeparatorTint(.gray.opacity(0.2))
                .listRowBackground(Color.clear)
            }
            ForEach(calendar.remindersForSelectedDay) { reminder in
                Button {
                    if let url = reminder.appURL { openURL(url) }
                } label: {
                    reminderRow(reminder)
                }
                .padding(.leading, -5)
                .buttonStyle(.plain)
                .listRowSeparator(.automatic)
                .listRowSeparatorTint(.gray.opacity(0.2))
                .listRowBackground(Color.clear)
            }
        }
    }

    private func reminderRow(_ reminder: AgendaReminder) -> some View {
        let isOverdue = reminder.hasTime && (reminder.dueDate.map { $0 < Date() } ?? false)
        return HStack(spacing: 8) {
            ReminderToggle(
                isOn: Binding(
                    get: { reminder.isCompleted },
                    set: { calendar.setReminderCompleted(reminder, completed: $0) }
                ),
                color: reminder.calendarColor
            )
            HStack {
                Text(reminder.title)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if reminder.hasTime, let due = reminder.dueDate {
                    Text(due, style: .time)
                        .foregroundStyle(.white)
                        .font(.caption)
                } else {
                    Text("All-day")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .opacity(reminder.isCompleted ? 0.4 : (isOverdue ? 0.6 : 1.0))
        }
        .padding(.vertical, 4)
    }

    private func eventRow(_ event: AgendaEvent) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Rectangle()
                .fill(event.calendarColor)
                .frame(width: 3)
                .clipShape(.rect(cornerRadius: 1.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.notchSecondary)
                        .lineLimit(1)
                }
                if let conferenceURL = event.conferenceURL {
                    ConferenceJoinButton(url: conferenceURL, event: event)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(event.startDate, style: .time)
                    .foregroundStyle(.white)
                Text(event.endDate, style: .time)
                    .foregroundStyle(.notchSecondary)
            }
            .font(.caption)
            .frame(minWidth: 44, alignment: .trailing)
        }
        .opacity(event.endedToday ? 0.6 : 1.0)
    }
}

/// Atoll's StandaloneEventCardList: one card per event, beside the month.
struct StandaloneEventCardList: View {
    @EnvironmentObject var calendar: CalendarStore
    @Environment(\.openURL) private var openURL
    let selectedDate: Date

    var body: some View {
        let events = AgendaDayEvents(calendar.eventsForSelectedDay)
        AgendaList(selectedDate: selectedDate, events: events) {
            ForEach(events.timed) { event in
                calendarEventCard(event)
                    .contentShape(Rectangle())
                    .onTapGesture { if let url = event.calendarAppURL { openURL(url) } }
                    .padding(.horizontal, 2)
                    .id(event.id)
                    .padding(.bottom, 8)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            ForEach(calendar.remindersForSelectedDay) { reminder in
                Button {
                    if let url = reminder.appURL { openURL(url) }
                } label: {
                    ReminderCard(
                        reminder: reminder,
                        onToggle: { completed in
                            calendar.setReminderCompleted(reminder, completed: completed)
                        }, accent: reminder.calendarColor)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 2)
                .padding(.bottom, 8)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .clipped()
    }

    private func calendarEventCard(_ event: AgendaEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.calendarColor)
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.notchSecondary)
                        .lineLimit(1)
                }

                if let conferenceURL = event.conferenceURL {
                    ConferenceJoinButton(url: conferenceURL, event: event)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                if event.isAllDay {
                    Text("All-day")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                } else {
                    Text(event.startDate, style: .time)
                        .font(.caption)
                        .foregroundStyle(.white)
                    Text(event.endDate, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.notchSecondary)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(NotchCardBackground())
        .opacity(event.endedToday ? 0.6 : 1)
    }
}

extension AgendaEvent {
    /// Today's finished events are dimmed, as in Atoll.
    fileprivate var endedToday: Bool {
        status == .ended && Calendar.current.isDateInToday(startDate)
    }
}

private struct AllDayEventsStrip: View {
    @Environment(\.openURL) private var openURL
    let events: [AgendaEvent]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(events) { event in
                        allDayChip(event)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, AllDayStripMetrics.verticalPadding)
            }
            .frame(height: AllDayStripMetrics.chipRowHeight)
            .clipped()

            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 4)
        }
    }

    private func allDayChip(_ event: AgendaEvent) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(event.calendarColor)
                .frame(width: 8, height: 8)
            Text(event.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("All-day")
                .font(.caption2)
                .foregroundStyle(Color(white: 0.6))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, AllDayStripMetrics.verticalPadding)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .contentShape(Capsule())
        .onTapGesture { if let url = event.calendarAppURL { openURL(url) } }
    }
}

private struct ConferenceJoinButton: View {
    let url: URL
    let event: AgendaEvent
    @Environment(\.openURL) private var openURL

    /// Atoll enables Join 15 minutes before the start.
    private static let joinLead: TimeInterval = 15 * 60

    private var provider: ConferenceProvider { .detect(from: url) }
    private var isJoinable: Bool { event.startDate.addingTimeInterval(-Self.joinLead) <= Date() }
    private var buttonText: String { event.status == .inProgress ? "Rejoin" : "Join" }

    var body: some View {
        Button {
            openURL(ConferenceProvider.joinURL(for: url))
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                    .font(.system(size: 9))
                Text(provider.name.isEmpty ? buttonText : "\(buttonText) \(provider.name)")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isJoinable ? Color.white : Color(white: 0.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isJoinable ? provider.color.opacity(0.85) : Color.gray.opacity(0.3))
            .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!isJoinable)
        .help(
            isJoinable
                ? "Join the meeting"
                : "Meeting starts at \(event.startDate.formatted(date: .omitted, time: .shortened))")
    }
}

/// Atoll's EmptyEventsView.
struct EmptyEventsView: View {
    let selectedDate: Date

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.notchSecondary)
                .padding(.bottom, 7)
            Text(Calendar.current.isDateInToday(selectedDate) ? "No events today" : "No events")
                .font(.subheadline)
                .foregroundStyle(.white)
            Text("Enjoy your free time!")
                .font(.caption)
                .foregroundStyle(.notchSecondary)
                .padding(.top, 1)
        }
        .multilineTextAlignment(.center)
    }
}
