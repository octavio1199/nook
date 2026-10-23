import Foundation
import Testing
@testable import Nook

@Suite struct SubtaskTests {
    private func store(with task: TaskItem) -> PlannerStore {
        let store = PlannerStore(url: nil)
        store.add(task)
        return store
    }

    private func undoable(_ store: PlannerStore, _ body: () -> Void) {
        store.undoManager.beginUndoGrouping()
        body()
        store.undoManager.endUndoGrouping()
    }

    @Test func addCheckRenameMoveDeleteAndProgress() {
        let task = TaskItem(title: "Ship v0.3")
        let s = store(with: task)
        s.addSubtask("  Write notes ", to: task.id)
        s.addSubtask("", to: task.id)
        s.addSubtask("Tag release", to: task.id)
        s.addSubtask("Announce", to: task.id)
        var subs = s.task(task.id)!.subtasks
        #expect(subs.map(\.title) == ["Write notes", "Tag release", "Announce"])
        #expect(s.task(task.id)!.subtaskProgress! == (0, 3))

        s.toggleSubtask(subs[0].id, in: task.id)
        #expect(s.task(task.id)!.subtaskProgress! == (1, 3))
        s.renameSubtask(subs[2].id, in: task.id, to: "Post announcement")
        s.moveSubtask(subs[2].id, in: task.id, by: -1)
        s.moveSubtask(subs[0].id, in: task.id, by: -1) // already first: no change
        subs = s.task(task.id)!.subtasks
        #expect(subs.map(\.title) == ["Write notes", "Post announcement", "Tag release"])
        s.deleteSubtask(subs[1].id, in: task.id)
        #expect(s.task(task.id)!.subtasks.map(\.title) == ["Write notes", "Tag release"])
        #expect(TaskItem(title: "x").subtaskProgress == nil)
    }

    @Test func subtaskChangesAreUndoable() {
        let task = TaskItem(title: "Ship")
        let s = PlannerStore(url: nil)
        // Grouping off before any change: an open event group would swallow the ones below.
        s.undoManager.groupsByEvent = false
        undoable(s) { s.add(task) }
        undoable(s) { s.addSubtask("One", to: task.id) }
        let id = s.task(task.id)!.subtasks[0].id
        undoable(s) { s.toggleSubtask(id, in: task.id) }
        s.undoManager.undo()
        #expect(s.task(task.id)!.subtasks[0].done == false)
        s.undoManager.undo()
        #expect(s.task(task.id)!.subtasks.isEmpty)
    }

    @Test func oldDataWithoutSubtasksOrManualStillLoads() throws {
        let json = #"{"tasks":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Old"}],"notes":{},"sessions":[{"start":"2026-10-20T09:00:00Z","duration":600}]}"#
        let data = try JSONDecoder.planner.decode(PlannerData.self, from: Data(json.utf8))
        #expect(data.tasks[0].subtasks.isEmpty)
        #expect(data.sessions[0].manual == false)
        // And they survive a round trip.
        var task = data.tasks[0]
        task.subtasks = [Subtask(title: "a", done: true)]
        let again = try JSONDecoder.planner.decode(TaskItem.self, from: JSONEncoder.planner.encode(task))
        #expect(again.subtasks == task.subtasks)
    }
}

@Suite struct ManualLogTests {
    private let cal = Calendar.current

    private func undoable(_ store: PlannerStore, _ body: () -> Void) {
        store.undoManager.beginUndoGrouping()
        body()
        store.undoManager.endUndoGrouping()
    }
    private func yesterday(_ hour: Int, _ minute: Int = 0) -> Date {
        let day = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
        return day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    @Test func logMoveResizeDeleteAndTotals() {
        let s = PlannerStore(url: nil)
        let task = TaskItem(title: "Write report")
        s.add(task)
        s.log(FocusSession(start: yesterday(9), duration: 25 * 60, label: task.title, taskID: task.id))
        let manual = s.logManual(taskID: task.id, label: task.title, start: yesterday(14), minutes: 45)
        #expect(manual.manual)
        #expect(s.focusTime(for: task.id) == 70 * 60)
        #expect(s.sessions(on: yesterday(0)).count == 2)

        s.updateManualSession(manual.id, start: yesterday(15, 30), minutes: 60)
        let moved = s.sessions.first { $0.id == manual.id }!
        #expect(moved.start == yesterday(15, 30))
        #expect(moved.duration == 60 * 60)
        #expect(s.focusTime(for: task.id) == 85 * 60)

        // Timer sessions can't be edited or deleted through the manual API.
        let tracked = s.sessions.first { !$0.manual }!
        s.updateManualSession(tracked.id, start: yesterday(1), minutes: 5)
        s.deleteManualSession(tracked.id)
        #expect(s.sessions.first { $0.id == tracked.id }?.start == yesterday(9))

        s.deleteManualSession(manual.id)
        #expect(s.focusTime(for: task.id) == 25 * 60)
    }

    @Test func undoNeverDropsTimerSessionsLoggedMeanwhile() {
        let s = PlannerStore(url: nil)
        let task = TaskItem(title: "Write report")
        s.undoManager.groupsByEvent = false
        undoable(s) { s.add(task) }
        s.undoManager.beginUndoGrouping()
        s.logManual(taskID: task.id, label: nil, start: yesterday(14), minutes: 30)
        s.undoManager.endUndoGrouping()
        // A timer finishes after the manual log.
        s.log(FocusSession(start: Date(), duration: 25 * 60, taskID: task.id))
        s.undoManager.undo()
        #expect(s.sessions.count == 1)
        #expect(s.sessions[0].manual == false)
        s.undoManager.redo()
        #expect(s.sessions.count == 2)
    }

    @Test func completeAtAPastTime() {
        let s = PlannerStore(url: nil)
        let task = TaskItem(title: "Write report")
        s.add(task)
        s.complete(task.id, at: yesterday(16))
        #expect(s.task(task.id)?.done == true)
        #expect(s.task(task.id)?.completedAt == yesterday(16))
    }

    @Test func plannedVsActualAndPerTaskTotalsCountManualLogs() {
        let now = Date()
        var task = TaskItem(title: "Deck")
        task.estimateMinutes = 60
        task.scheduledStart = cal.startOfDay(for: now).addingTimeInterval(9 * 3600)
        let manual = FocusSession(start: cal.startOfDay(for: now).addingTimeInterval(9 * 3600), duration: 40 * 60, taskID: task.id, manual: true)
        let plan = PlannedVsActual(tasks: [task], sessions: [manual], now: now)
        #expect(plan.rows.first?.actual == TimeInterval(40 * 60))
        let summary = InsightsSummary(tasks: [task], sessions: [manual], now: now)
        #expect(summary.taskTimes.first?.duration == TimeInterval(40 * 60))
    }

    @Test func pastDayListsDoneThatDayThenOpen() {
        var done = TaskItem(title: "Done yesterday", done: true)
        done.completedAt = yesterday(11)
        var doneToday = TaskItem(title: "Done today", done: true)
        doneToday.completedAt = Date()
        let open = TaskItem(title: "Open")
        var archived = TaskItem(title: "Archived")
        archived.archivedAt = Date()
        let list = PastDay.candidates(tasks: [open, doneToday, done, archived], day: yesterday(0))
        #expect(list.map(\.title) == ["Done yesterday", "Open"])
    }
}

@Suite struct FocusTabSwitchTests {
    private func make(auto: Bool = true) -> (NotchInteraction, FocusTimer) {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "FocusTabSwitchTests-\(UUID().uuidString)")!)
        settings.autoShowsFocusTab = auto
        let focus = FocusTimer()
        let notch = NotchInteraction(settings: settings, focus: focus, agenda: AgendaModel(), geometry: .placeholder, clock: ManualClock())
        return (notch, focus)
    }

    @Test func startingAFocusShowsTheTabAndEndingGoesBack() {
        let (notch, focus) = make()
        notch.show(.day)
        focus.startPomodoro(.with(id: "classic"))
        notch.focusActivityChanged()
        #expect(notch.area == .focus)
        focus.stop()
        notch.focusActivityChanged()
        #expect(notch.area == .day)
    }

    @Test func aTabPickedDuringTheFocusIsKept() {
        let (notch, focus) = make()
        focus.startPomodoro(.with(id: "classic"))
        notch.focusActivityChanged()
        notch.show(.insights)
        focus.stop()
        notch.focusActivityChanged()
        #expect(notch.area == .insights)
    }

    @Test func settingOffLeavesTheTabAlone() {
        let (notch, focus) = make(auto: false)
        focus.startPomodoro(.with(id: "classic"))
        notch.focusActivityChanged()
        #expect(notch.area == .workspace)
        focus.stop()
    }
}
