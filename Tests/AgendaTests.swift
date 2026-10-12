import Foundation
import Testing

struct AgendaScrollTargetTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private static func event(
        _ id: String, _ start: Date, _ end: Date, allDay: Bool = false, meeting: Bool = false
    ) -> AgendaEvent {
        AgendaEvent(
            id: id, title: id, timeString: "", location: nil, startDate: start, endDate: end, isAllDay: allDay,
            conferenceURL: meeting ? URL(string: "https://meet.google.com/abc") : nil)
    }

    private static let ended = event("ended", at(12, 8), at(12, 9))
    private static let running = event("running", at(12, 9, 30), at(12, 11))
    private static let meeting = event("meeting", at(12, 9, 45), at(12, 10, 30), meeting: true)
    private static let later = event("later", at(12, 12), at(12, 13))
    private static let now = at(12, 10)

    private func target(_ events: [AgendaEvent], day: Date = now) -> String? {
        AgendaDayEvents(events).scrollTarget(on: day, now: Self.now, calendar: Self.calendar)?.id
    }

    @Test func prefersAMeetingInProgress() {
        #expect(target([Self.later, Self.running, Self.meeting, Self.ended]) == "meeting")
    }

    @Test func thenAnyEventInProgress() {
        #expect(target([Self.later, Self.running, Self.ended]) == "running")
    }

    @Test func thenTheNextOne() {
        #expect(target([Self.later, Self.ended]) == "later")
    }

    @Test func elseTheLast() {
        let earlier = Self.event("earlier", Self.at(12, 6), Self.at(12, 7))
        #expect(target([Self.ended, earlier]) == "ended")
        #expect(target([]) == nil)
    }

    /// Another day is measured from its start, so its first event wins.
    @Test func anotherDayStartsAtMidnight() {
        let first = Self.event("first", Self.at(13, 8), Self.at(13, 9))
        let second = Self.event("second", Self.at(13, 12), Self.at(13, 13))
        #expect(target([second, first], day: Self.at(13, 0)) == "first")
    }

    @Test func allDayEventsGoToTheStripInStartOrder() {
        let holiday = Self.event("holiday", Self.at(12, 0), Self.at(13, 0), allDay: true)
        let trip = Self.event("trip", Self.at(11, 0), Self.at(14, 0), allDay: true)
        let day = AgendaDayEvents([Self.later, holiday, Self.ended, trip])
        #expect(day.allDay.map(\.id) == ["trip", "holiday"])
        #expect(day.timed.map(\.id) == ["ended", "later"])
        #expect(target([holiday, trip]) == nil)
    }

    @Test func status() {
        #expect(Self.ended.status(at: Self.now) == .ended)
        #expect(Self.running.status(at: Self.now) == .inProgress)
        #expect(Self.later.status(at: Self.now) == .upcoming)
        // An event is in progress from its start up to, not including, its end.
        #expect(Self.later.status(at: Self.at(12, 12)) == .inProgress)
        #expect(Self.later.status(at: Self.at(12, 13)) == .ended)
    }
}

struct WeekWheelLayoutTests {
    private static let layout = WeekWheelLayout()

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private static func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func atollsDefaults() {
        // 7 days back, today, 14 ahead; two spacers each side.
        #expect(Self.layout.dateCount == 22)
        #expect(Self.layout.itemCount == 26)
        #expect(Self.layout.dateIndices == 2..<24)
    }

    @Test func indexMath() {
        let calendar = Self.calendar("Asia/Ho_Chi_Minh")
        let today = Self.date(calendar, 2026, 10, 12, hour: 23)
        func index(_ offset: Int) -> Int {
            Self.layout.index(
                for: calendar.date(byAdding: .day, value: offset, to: today)!, today: today, calendar: calendar)
        }
        #expect(index(0) == 9)
        #expect(index(-7) == 2)
        #expect(index(14) == 23)
        // Out of range clamps to the ends of the strip.
        #expect(index(-30) == 2)
        #expect(index(40) == 23)
    }

    /// Every cell's day maps back to its cell, at midnight, one day apart,
    /// including weeks where the clocks change.
    @Test(arguments: [
        ("America/New_York", 2026, 11, 3),  // DST ended on Nov 1
        ("America/New_York", 2026, 3, 10),  // DST began on Mar 8
        ("Europe/Berlin", 2026, 10, 27),  // DST ended on Oct 25
        ("Asia/Ho_Chi_Minh", 2026, 10, 12),
    ])
    func cellsRoundTrip(zone: String, year: Int, month: Int, day: Int) {
        let calendar = Self.calendar(zone)
        let today = Self.date(calendar, year, month, day)
        var previous: Date?
        for index in Self.layout.dateIndices {
            let date = Self.layout.date(at: index, today: today, calendar: calendar)
            #expect(calendar.component(.hour, from: date) == 0)
            #expect(Self.layout.index(for: date, today: today, calendar: calendar) == index)
            if let previous {
                #expect(calendar.dateComponents([.day], from: previous, to: date).day == 1)
            }
            previous = date
        }
        let todayIndex = Self.layout.index(for: today, today: today, calendar: calendar)
        #expect(calendar.isDate(Self.layout.date(at: todayIndex, today: today, calendar: calendar), inSameDayAs: today))
    }

    @Test func dragsStopAtTheFirstDayAndTheLastItem() {
        #expect(Self.layout.dragTarget(from: 9, movedBy: 3) == 12)
        #expect(Self.layout.dragTarget(from: 9, movedBy: -20) == 2)
        #expect(Self.layout.dragTarget(from: 9, movedBy: 100) == 25)
    }
}
