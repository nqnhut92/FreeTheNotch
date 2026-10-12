import Foundation
import SwiftUI

/// A calendar event as the notch and the lock screen show it, with the
/// fields Atoll's EventModel uses for its event cards.
struct AgendaEvent: Identifiable {
    let id: String
    let title: String
    let timeString: String
    let location: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    var calendarColor: Color = .accentColor
    var conferenceURL: URL?
    var calendarAppURL: URL?

    /// Atoll's `eventStatus`.
    enum Status { case upcoming, inProgress, ended }

    var status: Status { status(at: Date()) }

    func status(at now: Date) -> Status {
        if startDate > now { return .upcoming }
        if endDate > now { return .inProgress }
        return .ended
    }

    func isInProgress(at date: Date) -> Bool {
        startDate <= date && endDate > date
    }
}

/// One day's events split the way both notch event lists show them: all-day
/// events in a strip on top, timed events in the list, each by start time.
struct AgendaDayEvents {
    let allDay: [AgendaEvent]
    let timed: [AgendaEvent]

    init(_ events: [AgendaEvent]) {
        let sorted = events.sorted { $0.startDate < $1.startDate }
        allDay = sorted.filter(\.isAllDay)
        timed = sorted.filter { !$0.isAllDay }
    }

    /// Atoll's scrollTargetForTimedEvents: a meeting in progress, else any
    /// event in progress, else the next one, else the last. Measured from
    /// `now` on today and from the start of any other day.
    func scrollTarget(on day: Date, now: Date = Date(), calendar: Calendar = .current) -> AgendaEvent? {
        let reference = calendar.isDate(day, inSameDayAs: now) ? now : calendar.startOfDay(for: day)
        return timed.first { $0.conferenceURL != nil && $0.isInProgress(at: reference) }
            ?? timed.first { $0.isInProgress(at: reference) }
            ?? timed.first { $0.startDate > reference }
            ?? timed.last
    }
}
