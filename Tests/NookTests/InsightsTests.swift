import Foundation
import Testing
@testable import Nook

@Suite struct InsightsTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    private func done(_ day: Int) -> TaskItem {
        TaskItem(title: "t", done: true, completedAt: date(day))
    }

    @Test func todayCounts() {
        let summary = InsightsSummary(
            tasks: [done(10), done(10), done(9)],
            sessions: [FocusSession(start: date(10, 9), duration: 25 * 60), FocusSession(start: date(9, 9), duration: 50 * 60)],
            now: date(10, 18), calendar: calendar
        )
        #expect(summary.tasksDoneToday == 2)
        #expect(summary.focusMinutesToday == 25)
        #expect(summary.focusMinutesThisWeek == 75)
        #expect(summary.days.count == 7)
        #expect(summary.mostFocusedHour == 9)
        #expect(summary.bestDay?.date == calendar.startOfDay(for: date(9)))
    }

    @Test func streakSkipsEmptyToday() {
        let summary = InsightsSummary(tasks: [done(9), done(8), done(7), done(5)], sessions: [], now: date(10), calendar: calendar)
        #expect(summary.streak == 3)
    }

    @Test func streakBreaksOnGap() {
        let summary = InsightsSummary(tasks: [done(10), done(8)], sessions: [], now: date(10), calendar: calendar)
        #expect(summary.streak == 1)
    }

    @Test func emptyState() {
        let summary = InsightsSummary(tasks: [], sessions: [], now: date(10), calendar: calendar)
        #expect(summary.streak == 0)
        #expect(summary.bestDay == nil)
        #expect(summary.mostFocusedHour == nil)
    }
}
