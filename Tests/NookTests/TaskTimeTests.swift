import Foundation
import Testing
@testable import Nook

@Suite struct TaskTimeTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    private func session(_ task: TaskItem?, day: Int, minutes: Double) -> FocusSession {
        FocusSession(start: date(day), duration: minutes * 60, label: task?.title, taskID: task?.id)
    }

    @Test func formatsDurations() {
        #expect(TaskTime.text(47 * 60) == "47m")
        #expect(TaskTime.text(65 * 60) == "1h 05m")
        #expect(TaskTime.text(120 * 60) == "2h")
        #expect(TaskTime.chip(59) == nil)
        #expect(TaskTime.chip(60) == "1m")
    }

    @Test func sumsSessionsPerTaskAndRanksThem() {
        let a = TaskItem(title: "A"), b = TaskItem(title: "B"), c = TaskItem(title: "C", done: true)
        let summary = InsightsSummary(
            tasks: [a, b, c],
            sessions: [
                session(a, day: 10, minutes: 25), session(a, day: 9, minutes: 5),
                session(b, day: 10, minutes: 50),
                session(c, day: 8, minutes: 10),
                session(nil, day: 10, minutes: 99),
            ],
            now: date(10, 18), calendar: calendar
        )
        #expect(summary.taskTimes.map(\.title) == ["B", "A", "C"])
        let seconds: [TimeInterval] = summary.taskTimes.map(\.duration)
        let expected: [TimeInterval] = [3000, 1800, 600]
        #expect(seconds == expected)
        #expect(summary.taskTimes[1].sessions == 2)
        #expect(summary.taskTimes[2].done)
    }

    @Test func onlyTheLastSevenDaysCountAndDeletedTasksKeepTheirLabel() {
        let old = TaskItem(title: "Old")
        let gone = TaskItem(title: "Gone")
        let summary = InsightsSummary(
            tasks: [old],
            sessions: [session(old, day: 2, minutes: 30), session(gone, day: 9, minutes: 20)],
            now: date(10, 18), calendar: calendar
        )
        #expect(summary.taskTimes.map(\.title) == ["Gone"])
        let seconds: TimeInterval? = summary.taskTimes.first?.duration
        #expect(seconds == 1200)
    }

    @Test func keepsOnlyTheTopFive() {
        let tasks = (1...7).map { TaskItem(title: "T\($0)") }
        let summary = InsightsSummary(
            tasks: tasks,
            sessions: tasks.enumerated().map { session($0.element, day: 10, minutes: Double($0.offset + 1) * 10) },
            now: date(10, 18), calendar: calendar
        )
        #expect(summary.taskTimes.count == InsightsSummary.topTaskLimit)
        #expect(summary.taskTimes.first?.title == "T7")
    }

    @Test func plannerSumsFocusTimeAcrossExtensions() {
        let planner = PlannerStore(url: nil)
        let task = TaskItem(title: "Report")
        planner.add(task)
        planner.log(session(task, day: 10, minutes: 25))
        planner.log(session(task, day: 10, minutes: 5))
        planner.log(session(nil, day: 10, minutes: 40))
        #expect(planner.focusTime(for: task.id) == 30 * 60)
    }
}
