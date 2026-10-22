import Foundation
import SwiftUI
import Testing
@testable import Nook

@Suite struct DayPlannerTests {
    private let cal = Calendar.current
    private var day: Date { cal.startOfDay(for: Date()) }
    private let planner = DayPlanner() // 09:00 to 18:00, 5 min buffer, 15 min snap

    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        cal.date(byAdding: .day, value: dayOffset, to: day)!.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> AgendaEvent {
        AgendaEvent(id: title, title: title, start: start, end: end, isAllDay: allDay, color: .blue)
    }

    private func task(_ title: String, priority: TaskItem.Priority = .none, minutes: Int? = nil, order: Double = 0, start: Date? = nil) -> TaskItem {
        var task = TaskItem(title: title, priority: priority)
        task.estimateMinutes = minutes
        task.order = order
        task.scheduledStart = start
        return task
    }

    // MARK: Free slots

    @Test func emptyDayIsOneSlotOfWorkingHours() {
        let slots = planner.freeSlots(on: day, events: [], tasks: [])
        #expect(slots == [DateInterval(start: at(9), end: at(18))])
    }

    @Test func eventsAndBlocksSplitTheDayAndAllDayIsIgnored() {
        let events = [event("Meeting", at(10), at(11)), event("Holiday", at(0), at(23), allDay: true)]
        let blocked = task("Write", minutes: 60, start: at(13))
        let slots = planner.freeSlots(on: day, events: events, tasks: [blocked])
        #expect(slots == [
            DateInterval(start: at(9), end: at(10)),
            DateInterval(start: at(11), end: at(13)),
            DateInterval(start: at(14), end: at(18)),
        ])
    }

    @Test func bufferKeepsMinutesClearAroundBusyTime() {
        let slots = planner.freeSlots(on: day, events: [event("Meeting", at(10), at(11))], tasks: [], buffer: 5)
        #expect(slots == [DateInterval(start: at(9), end: at(9, 55)), DateInterval(start: at(11, 5), end: at(18))])
    }

    @Test func afterClipsTheStartAndSkipsRunningEvents() {
        let slots = planner.freeSlots(on: day, events: [event("Meeting", at(10), at(11))], tasks: [], after: at(10, 30))
        #expect(slots == [DateInterval(start: at(11), end: at(18))])
        #expect(planner.freeSlots(on: day, events: [], tasks: [], after: at(18, 30)).isEmpty)
    }

    @Test func doneAndUnscheduledTasksDoNotBlockTime() {
        var finished = task("Done", minutes: 60, start: at(10))
        finished.done = true
        let slots = planner.freeSlots(on: day, events: [], tasks: [finished, task("Loose")])
        #expect(slots == [DateInterval(start: at(9), end: at(18))])
    }

    // MARK: Snapping

    @Test func snapsToFifteenMinutes() {
        #expect(planner.snapped(at(10, 7)) == at(10))
        #expect(planner.snapped(at(10, 8)) == at(10, 15))
        #expect(planner.snapped(at(10, 1), up: true) == at(10, 15))
        #expect(planner.snapped(at(10, 15), up: true) == at(10, 15))
    }

    // MARK: Plan my day

    @Test func packsByPriorityThenOrderWithBuffer() {
        let low = task("Low", priority: .low, minutes: 30, order: 1)
        let high = task("High", priority: .high, minutes: 60, order: 3)
        let highFirst = task("HighFirst", priority: .high, minutes: 30, order: 2)
        let none = task("None", order: 0)
        let plan = planner.planDay(on: day, tasks: [low, none, high, highFirst], events: [], now: at(9, 7))
        #expect(plan.map(\.id) == [highFirst.id, high.id, low.id, none.id])
        // 09:15-09:45, 10:00-11:00 (the 5 min buffer pushes the next start to the grid), 11:15-11:45, 12:00
        #expect(plan.map(\.start) == [at(9, 15), at(10), at(11, 15), at(12)])
        #expect(plan.last?.minutes == 30) // default estimate
    }

    @Test func leavesRoomAroundEvents() {
        let plan = planner.planDay(on: day, tasks: [task("Long", minutes: 60)], events: [event("Meeting", at(9, 30), at(10, 30))], now: at(9))
        #expect(plan.first?.start == at(10, 45))
    }

    @Test func squeezesIntoAGapThatFits() {
        let events = [event("A", at(9, 30), at(12)), event("B", at(12, 45), at(18))]
        let small = task("Small", minutes: 15)
        let big = task("Big", priority: .high, minutes: 60)
        let plan = planner.planDay(on: day, tasks: [big, small], events: events, now: at(9, 30))
        #expect(plan.map(\.id) == [small.id]) // the big one fits nowhere, the small one still lands
        #expect(plan.first?.start == at(12, 15))
    }

    @Test func respectsWorkingHours() {
        let late = planner.planDay(on: day, tasks: [task("T", minutes: 60)], events: [], now: at(17, 30))
        #expect(late.isEmpty)
        var custom = planner
        custom.workStart = 10 * 60
        custom.workEnd = 12 * 60
        let plan = custom.planDay(on: day, tasks: [task("A", minutes: 60), task("B", minutes: 60, order: 1)], events: [], now: at(7))
        #expect(plan.map(\.start) == [at(10)]) // B would need 11:15-12:15, past the end
    }

    @Test func tomorrowIgnoresNowAndStartsWithTheWorkday() {
        let plan = planner.planDay(on: at(0, dayOffset: 1), tasks: [task("T", minutes: 30)], events: [], now: at(15))
        #expect(plan.first?.start == at(9, dayOffset: 1))
    }

    @Test func onlyOpenUnscheduledTasksDueByThatDayAreCandidates() {
        var done = task("Done"); done.done = true
        var archived = task("Archived"); archived.archivedAt = Date()
        let scheduled = task("Scheduled", start: at(16))
        var future = task("Future"); future.due = at(9, dayOffset: 3)
        let stale = task("Stale", start: at(10, dayOffset: -1))
        let fresh = task("Fresh")
        let plan = planner.planDay(on: day, tasks: [done, archived, scheduled, future, stale, fresh], events: [], now: at(9))
        #expect(Set(plan.map(\.id)) == [stale.id, fresh.id])
    }

    @Test func existingBlocksAreRespected() {
        let existing = task("Existing", minutes: 60, start: at(9))
        let plan = planner.planDay(on: day, tasks: [existing, task("New", minutes: 30)], events: [], now: at(8))
        #expect(plan.first?.start == at(10, 15)) // 10:00 + 5 buffer, snapped up
    }

    // MARK: Push rest

    @Test func pushRestShiftsLaterBlocksOfThatDayOnly() {
        let before = task("Before", start: at(10))
        let later = task("Later", start: at(11))
        let evening = task("Evening", start: at(14))
        let tomorrow = task("Tomorrow", start: at(11, dayOffset: 1))
        var done = task("Done", start: at(15)); done.done = true
        let moves = planner.pushRest(on: day, tasks: [before, later, evening, tomorrow, done], from: at(10, 30), by: 15)
        #expect(moves == [later.id: at(11, 15), evening.id: at(14, 15)])
    }

    @Test func overrunRoundsUpToFiveMinutes() {
        #expect(DayPlanner.roundedOverrun(1) == 5)
        #expect(DayPlanner.roundedOverrun(5 * 60) == 5)
        #expect(DayPlanner.roundedOverrun(6 * 60) == 10)
        #expect(DayPlanner.roundedOverrun(0) == 5)
        #expect(DayPlanner.roundedOverrun(12 * 60) == 15)
    }

    // MARK: Next free slot

    @Test func nextFreeSlotSkipsPastBusyTimeAndIgnoresTheMovedBlock() {
        let moving = task("Moving", minutes: 60, start: at(14))
        let events = [event("Meeting", at(15), at(16))]
        let slot = planner.nextFreeSlot(after: at(15), minutes: 60, events: events, tasks: [moving], excluding: [moving.id])
        #expect(slot == at(16, 15))
    }

    @Test func nextFreeSlotRollsToTomorrowWhenTodayIsFull() {
        let slot = planner.nextFreeSlot(after: at(17, 30), minutes: 60, events: [], tasks: [])
        #expect(slot == at(9, dayOffset: 1))
        #expect(planner.nextFreeSlot(after: at(8), minutes: 24 * 60, events: [], tasks: []) == nil)
    }

    // MARK: Overlap layout

    @Test func overlappingSpansShareColumns() {
        let a = DayPlanner.Span(id: "a", start: at(9), end: at(10))
        let b = DayPlanner.Span(id: "b", start: at(9, 30), end: at(10, 30))
        let c = DayPlanner.Span(id: "c", start: at(10), end: at(11))
        let alone = DayPlanner.Span(id: "alone", start: at(13), end: at(14))
        let columns = DayPlanner.columns(for: [c, alone, b, a])
        #expect(columns["a"] == .init(column: 0, columns: 2))
        #expect(columns["b"] == .init(column: 1, columns: 2))
        #expect(columns["c"] == .init(column: 0, columns: 2))
        #expect(columns["alone"] == .init(column: 0, columns: 1))
        #expect(DayPlanner.overlapping([a, b, c, alone]) == ["a", "b", "c"])
    }

    // MARK: Up next and planned vs actual

    @Test func upNextIsTheCurrentBlockPlusTheNextThree() {
        let now = at(10, 10)
        let current = task("Current", minutes: 30, start: at(10))
        let b1 = task("B1", minutes: 30, start: at(11))
        let b2 = task("B2", minutes: 30, start: at(13))
        let past = task("Past", minutes: 30, start: at(8))
        let events = [event("Standup", at(10, 30), at(11)), event("Lunch", at(12), at(13)), event("All day", at(0), at(23), allDay: true)]
        let list = UpNextItem.list(events: events, blocks: [current, b1, b2, past], now: now)
        #expect(list.map { $0.task?.title ?? $0.event?.title ?? "" } == ["Current", "Standup", "B1", "Lunch"])
    }

    @Test func plannedVsActualCountsTodaysFocusPerScheduledTask() {
        let a = task("A", minutes: 30, start: at(9))
        let b = task("B", minutes: 60, start: at(11))
        let unplanned = task("C")
        let sessions = [
            FocusSession(start: at(9, 5), duration: 40 * 60, taskID: a.id),
            FocusSession(start: at(9, dayOffset: -1), duration: 99 * 60, taskID: a.id),
            FocusSession(start: at(12), duration: 10 * 60, taskID: unplanned.id),
        ]
        let plan = PlannedVsActual(tasks: [b, unplanned, a], sessions: sessions, now: at(13))
        #expect(plan.rows.map(\.title) == ["A", "B"])
        #expect(plan.rows[0].actual == 40 * 60)
        #expect(plan.rows[0].overran)
        #expect(plan.rows[1].actual == 0)
        #expect(plan.plannedTotal == 90)
    }
}
