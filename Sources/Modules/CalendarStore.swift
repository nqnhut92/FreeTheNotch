import EventKit
import Foundation
import SwiftUI

// MARK: - Models

struct AgendaReminder: Identifiable {
    let id: String
    let title: String
    let isCompleted: Bool
    let ekReminder: EKReminder
    var calendarColor: Color {
        ekReminder.calendar.map { Color(cgColor: $0.cgColor) } ?? .accentColor
    }
    /// Atoll's appleCalendarURL for reminders.
    var appURL: URL? {
        guard
            let id = ekReminder.calendarItemIdentifier
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "x-apple-reminderkit://remcdreminder/\(id)")
    }
    /// Due date for display; nil if the reminder has no due date.
    var dueDate: Date? {
        guard let comps = ekReminder.dueDateComponents else { return nil }
        return Calendar.current.date(from: comps)
    }
    /// True if the reminder has a specific time (not just a date).
    var hasTime: Bool {
        ekReminder.dueDateComponents?.hour != nil
    }
}

// MARK: - Store

/// EventKit-backed agenda. Permissions are requested lazily — only when the
/// Calendar tab is first opened — and the UI degrades gracefully if denied.
final class CalendarStore: ObservableObject {
    private let store = EKEventStore()
    private let calendar = Calendar.current

    /// First day of the currently displayed month.
    @Published private(set) var monthCursor: Date = Calendar.current.startOfMonth(for: Date())
    @Published var selectedDay: Date = Calendar.current.startOfDay(for: Date())

    @Published private(set) var events: [AgendaEvent] = []
    /// Incomplete reminders with a due date (any day).
    @Published private(set) var allReminders: [AgendaReminder] = []
    @Published private(set) var accessGranted = false

    /// Today's reminders (lock screen).
    var reminders: [AgendaReminder] { reminders(on: Date()) }

    /// Reminders due on the selected day (Atoll lists them with that day's events).
    var remindersForSelectedDay: [AgendaReminder] { reminders(on: selectedDay) }

    func reminders(on day: Date) -> [AgendaReminder] {
        allReminders.filter { $0.dueDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
    }

    private var storeObserver: NSObjectProtocol?
    private var pendingRefresh: DispatchWorkItem?

    init() {
        // Atoll's CalendarManager: reload when Calendar/Reminders change,
        // so items added after launch show up.
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            self?.scheduleRefresh()
        }
    }

    /// Coalesces bursts of change notifications (Atoll throttles too).
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.accessGranted else { return }
            self.reload()
            self.reloadReminders()
        }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: Access

    func requestAccessIfNeeded() {
        guard !accessGranted else {
            // Already allowed: refresh on each open, which also rolls
            // "today" over after midnight.
            scheduleRefresh()
            return
        }
        Task { @MainActor in
            do {
                let eventsOK = try await store.requestFullAccessToEvents()
                let remindersOK = try await store.requestFullAccessToReminders()
                self.accessGranted = eventsOK
                if eventsOK { self.reload() }
                if remindersOK { self.reloadReminders() }
            } catch {
                // Denied: the tab shows its empty state.
            }
        }
    }

    // MARK: Month grid

    private static let eventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    var monthTitle: String { Self.monthTitleFormatter.string(from: monthCursor) }

    /// Monday-first grid cells for the displayed month, including dimmed
    /// leading/trailing days from adjacent months (Atoll-style).
    var gridDays: [CalendarDay] {
        CalendarDay.monthGrid(startingAt: monthCursor, calendar: calendar)
    }

    /// Atoll's StandaloneCalendarView: the shown month follows the selection.
    func showMonth(containing date: Date) {
        let month = calendar.startOfMonth(for: date)
        guard month != monthCursor else { return }
        monthCursor = month
        reload()
    }

    // MARK: Selection

    func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }
    func isSelected(_ date: Date) -> Bool { calendar.isDate(date, inSameDayAs: selectedDay) }
    /// Lock-screen event, Atoll's `nextCalendarEvent` with its defaults
    /// (show for the entire duration = on, lookahead = 3h): skip all-day
    /// events, take an ongoing event or one starting within 3 hours, the
    /// earliest first. Not `events.first`: that is the oldest event of the
    /// loaded three-month window, often a long-past all-day holiday.
    var lockScreenEvent: AgendaEvent? {
        let now = Date()
        let lookaheadEnd = now.addingTimeInterval(3 * 3600)
        return
            events
            .filter { !$0.isAllDay && $0.endDate >= now }
            .filter { ($0.startDate <= now) || ($0.startDate <= lookaheadEnd) }
            .min { $0.startDate < $1.startDate }
    }

    var eventsForSelectedDay: [AgendaEvent] {
        events.filter { calendar.isDate($0.startDate, inSameDayAs: selectedDay) }
    }

    // MARK: Data

    private func reload() {
        guard let start = calendar.date(byAdding: .month, value: -1, to: monthCursor),
            let end = calendar.date(byAdding: .month, value: 2, to: monthCursor)
        else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let timeFormatter = Self.eventTimeFormatter
        events = store.events(matching: predicate).map { e in
            AgendaEvent(
                id: e.eventIdentifier,
                title: e.title ?? "(No title)",
                timeString: e.isAllDay ? "All day" : timeFormatter.string(from: e.startDate),
                location: e.location,
                startDate: e.startDate,
                endDate: e.endDate,
                isAllDay: e.isAllDay,
                calendarColor: e.calendar.map { Color(cgColor: $0.cgColor) } ?? .accentColor,
                conferenceURL: Self.conferenceURL(for: e),
                calendarAppURL: Self.calendarAppURL(for: e))
        }.sorted { $0.startDate < $1.startDate }
    }

    private func reloadReminders() {
        // Atoll-style: predicateForReminders(in:) fetches all reminders;
        // filter by due date in code. predicateForIncompleteReminders with
        // nil dates silently drops reminders that have due dates.
        let calendars = store.calendars(for: .reminder)
        guard !calendars.isEmpty else { return }
        let predicate = store.predicateForReminders(in: calendars)
        store.fetchReminders(matching: predicate) { [weak self] ekReminders in
            DispatchQueue.main.async {
                // Incomplete reminders with a due date; views filter by day.
                self?.allReminders = (ekReminders ?? []).compactMap { r in
                    guard !r.isCompleted,
                        let dueComps = r.dueDateComponents,
                        Calendar.current.date(from: dueComps) != nil
                    else { return nil }
                    return AgendaReminder(
                        id: r.calendarItemIdentifier,
                        title: r.title ?? "(No title)",
                        isCompleted: r.isCompleted,
                        ekReminder: r)
                }
            }
        }
    }

    // MARK: Atoll helpers (CalendarServiceProviding.swift, EventModel.swift)

    private static let conferenceHosts = [
        "zoom.us", "teams.microsoft.com", "meet.google.com", "webex.com",
        "gotomeeting.com", "bluejeans.com", "whereby.com", "meet.jit.si",
        "discord.gg", "discord.com", "facetime.apple.com",
    ]

    private static func isConferenceURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return conferenceHosts.contains { host.contains($0) }
    }

    private static func conferenceURL(in text: String?) -> URL? {
        guard let text, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let matches = detector.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        return matches.lazy.compactMap(\.url).first(where: isConferenceURL)
    }

    /// Atoll's extractConferenceURL: URL field, then location, then notes.
    private static func conferenceURL(for event: EKEvent) -> URL? {
        if let url = event.url, isConferenceURL(url) { return url }
        return conferenceURL(in: event.location) ?? conferenceURL(in: event.notes)
    }

    /// Atoll's appleCalendarURL: opens the event in Calendar.
    private static func calendarAppURL(for event: EKEvent) -> URL? {
        guard
            let id = event.calendarItemIdentifier
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        var date = ""
        if event.hasRecurrenceRules || event.isDetached {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            if !event.isAllDay { formatter.timeZone = .init(secondsFromGMT: 0) }
            guard let formatted = formatter.string(for: event.startDate) else { return nil }
            date = "/\(formatted)"
        }
        return URL(string: "ical://ekevent\(date)/\(id)?method=show&options=more")
    }

    func setReminderCompleted(_ reminder: AgendaReminder, completed: Bool) {
        reminder.ekReminder.isCompleted = completed
        try? store.save(reminder.ekReminder, commit: true)
        reloadReminders()
    }
}

extension Calendar {
    fileprivate func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
