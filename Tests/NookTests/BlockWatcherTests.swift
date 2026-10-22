import Foundation
import Testing
@testable import Nook

@Suite struct BlockWatcherTests {
    private let cal = Calendar.current
    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: Date()))!
        return day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    private struct Rig {
        var planner = PlannerStore(url: nil)
        var focus = FocusTimer()
        var agenda = AgendaModel()
        var settings = AppSettings(defaults: UserDefaults(suiteName: "BlockWatcherTests-\(UUID().uuidString)")!)
        var watcher: BlockWatcher
        var alerts: AlertBox

        @MainActor init() {
            agenda.useDemoEvents([]) // never read the real calendar
            let box = AlertBox()
            watcher = BlockWatcher(planner: planner, focus: focus, agenda: agenda, settings: settings, autoStart: false)
            watcher.onAlert = { box.alerts.append($0) }
            alerts = box
        }
    }

    final class AlertBox {
        var alerts: [NotchAlert] = []
    }

    private func addBlock(_ rig: Rig, _ title: String, at start: Date, minutes: Int = 50) -> TaskItem {
        var task = TaskItem(title: title)
        task.scheduledStart = start
        task.estimateMinutes = minutes
        let manager = rig.planner.undoManager
        if manager.groupsByEvent { rig.planner.add(task) } else { manager.beginUndoGrouping(); rig.planner.add(task); manager.endUndoGrouping() }
        return task
    }

    // MARK: Alert timing

    @Test func asksFiveMinutesBeforeAndAtStartOnlyOnce() {
        let rig = Rig()
        let task = addBlock(rig, "Design review", at: at(14))
        rig.watcher.check(now: at(13, 54))
        #expect(rig.alerts.alerts.isEmpty)

        rig.watcher.check(now: at(13, 55))
        #expect(rig.alerts.alerts.count == 1)
        let soon = rig.alerts.alerts[0]
        #expect(soon.kind == .blockSoon)
        #expect(soon.headline == "Next: Design review")
        #expect(soon.detail?.hasSuffix("50m") == true)
        #expect(soon.taskID == task.id)
        #expect(!soon.sticky)

        rig.watcher.check(now: at(13, 57))
        #expect(rig.alerts.alerts.count == 1)

        rig.watcher.check(now: at(14))
        #expect(rig.alerts.alerts.count == 2)
        #expect(rig.alerts.alerts[1].kind == .blockStart)
        #expect(rig.alerts.alerts[1].sticky)
        #expect(rig.alerts.alerts[1].headline == "Design review")

        rig.watcher.check(now: at(14, 10))
        #expect(rig.alerts.alerts.count == 2)
    }

    @Test func nothingForFinishedOrDoneOrPastBlocks() {
        let rig = Rig()
        let done = addBlock(rig, "Done", at: at(14))
        rig.planner.toggle(done.id)
        _ = addBlock(rig, "Past", at: at(9), minutes: 30)
        rig.watcher.check(now: at(13, 58))
        rig.watcher.check(now: at(14, 1))
        #expect(rig.alerts.alerts.isEmpty)
    }

    @Test func noAlertWhileFocusingOnThatTask() {
        let rig = Rig()
        let task = addBlock(rig, "Write report", at: at(14))
        rig.focus.startPomodoro(.with(id: "classic"), label: task.title, taskID: task.id)
        rig.watcher.check(now: at(13, 56))
        rig.watcher.check(now: at(14, 1))
        #expect(rig.alerts.alerts.isEmpty)
        rig.focus.stop()
    }

    @Test func focusOnAnotherTaskStillGetsTheAlert() {
        let rig = Rig()
        _ = addBlock(rig, "Write report", at: at(14))
        rig.focus.startPomodoro(.with(id: "classic"), label: "Something else", taskID: UUID())
        rig.watcher.check(now: at(13, 56))
        #expect(rig.alerts.alerts.count == 1)
        rig.focus.stop()
    }

    // MARK: Snooze and skip

    @Test func snoozeMovesTheBlockTenMinutesAndAsksAgain() {
        let rig = Rig()
        let task = addBlock(rig, "Write report", at: at(14))
        var resolved: [UUID] = []
        rig.watcher.onResolved = { resolved.append($0) }
        rig.watcher.check(now: at(13, 55))
        rig.watcher.snooze(task.id, now: at(13, 55))
        #expect(rig.planner.task(task.id)?.scheduledStart == at(14, 10))
        #expect(resolved == [task.id])

        rig.watcher.check(now: at(14, 5)) // five minutes before the new start
        #expect(rig.alerts.alerts.map(\.kind) == [.blockSoon, .blockSoon])
    }

    @Test func snoozeAfterTheStartCountsFromNow() {
        let rig = Rig()
        let task = addBlock(rig, "Write report", at: at(14))
        rig.watcher.snooze(task.id, now: at(14, 3))
        #expect(rig.planner.task(task.id)?.scheduledStart == at(14, 13))
    }

    @Test func skipMovesToTheNextFreeSlotAfterTheBlock() {
        let rig = Rig()
        let task = addBlock(rig, "Write report", at: at(14), minutes: 60)
        _ = addBlock(rig, "Later", at: at(15), minutes: 60)
        rig.watcher.skip(task.id, now: at(14))
        // after 15:00 the free time starts at 16:00 + 5 min buffer, snapped to 16:15
        #expect(rig.planner.task(task.id)?.scheduledStart == at(16, 15))
    }

    @Test func skipRollsToTomorrowWhenTodayIsOver() {
        let rig = Rig()
        let task = addBlock(rig, "Late", at: at(17), minutes: 60)
        rig.watcher.skip(task.id, now: at(17))
        #expect(rig.planner.task(task.id)?.scheduledStart == at(9, dayOffset: 1))
    }

    @Test func snoozeAndSkipAreUndoable() {
        let rig = Rig()
        rig.planner.undoManager.groupsByEvent = false
        let task = addBlock(rig, "Write report", at: at(14))
        rig.planner.undoManager.beginUndoGrouping()
        rig.watcher.snooze(task.id, now: at(13, 55))
        rig.planner.undoManager.endUndoGrouping()
        rig.planner.undoManager.undo()
        #expect(rig.planner.task(task.id)?.scheduledStart == at(14))
    }

    @Test func pushRestShiftsLaterBlocksAsOneUndoStep() {
        let rig = Rig()
        rig.planner.undoManager.groupsByEvent = false
        let late = addBlock(rig, "Write report", at: at(9), minutes: 30)
        let next = addBlock(rig, "Design review", at: at(10))
        let after = addBlock(rig, "Email", at: at(14), minutes: 15)
        rig.planner.undoManager.beginUndoGrouping()
        // Ran 12 minutes past 09:30: later blocks move by 15 (rounded up to 5).
        rig.watcher.pushRest(from: at(9, 30), overrun: 12 * 60)
        rig.planner.undoManager.endUndoGrouping()
        #expect(rig.planner.task(late.id)?.scheduledStart == at(9))
        #expect(rig.planner.task(next.id)?.scheduledStart == at(10, 15))
        #expect(rig.planner.task(after.id)?.scheduledStart == at(14, 15))

        rig.planner.undoManager.undo()
        #expect(rig.planner.task(next.id)?.scheduledStart == at(10))
        #expect(rig.planner.task(after.id)?.scheduledStart == at(14))
    }

    // MARK: Starting

    @Test func startFocusUsesTheBlockLengthAndTiesItToTheTask() {
        let rig = Rig()
        let task = addBlock(rig, "Write report", at: at(14), minutes: 50)
        rig.watcher.startFocus(task.id)
        #expect(rig.focus.phase == .focus)
        #expect(rig.focus.duration == 50 * 60)
        #expect(rig.focus.taskID == task.id)
        #expect(rig.focus.label == "Write report")
        #expect(rig.focus.preset.shortBreak == FocusPreset.with(id: rig.settings.focusPresetID).shortBreak)
        rig.focus.stop()
    }

    // MARK: Current block and running late

    @Test func currentBlockCoversNowOnly() {
        let rig = Rig()
        let task = addBlock(rig, "Write report", at: at(14), minutes: 30)
        rig.watcher.check(now: at(13, 59))
        #expect(rig.watcher.currentBlock == nil)
        rig.watcher.check(now: at(14, 10))
        #expect(rig.watcher.currentBlock?.id == task.id)
        #expect(rig.watcher.currentBlock?.end == at(14, 30))
        rig.watcher.check(now: at(14, 30))
        #expect(rig.watcher.currentBlock == nil)
    }

    @Test func pushRestOnlyAppearsWhenTheBlockEndedAndLaterBlocksExist() {
        let rig = Rig()
        rig.planner.undoManager.groupsByEvent = false
        let task = addBlock(rig, "Write report", at: at(10), minutes: 25)
        #expect(rig.watcher.overrun(for: task, now: at(10, 40)) == nil) // nothing later
        let later = addBlock(rig, "Later", at: at(11), minutes: 30)
        #expect(rig.watcher.overrun(for: task, now: at(10, 20)) == nil) // block still running
        let late = rig.watcher.overrun(for: task, now: at(10, 37))
        #expect(late?.end == at(10, 25))
        #expect(abs((late?.overrun ?? 0) - 12 * 60) < 0.001)

        rig.planner.undoManager.beginUndoGrouping()
        rig.watcher.pushRest(from: at(10, 25), overrun: 12 * 60)
        rig.planner.undoManager.endUndoGrouping()
        #expect(rig.planner.task(later.id)?.scheduledStart == at(11, 15)) // 12 min rounds up to 15
        #expect(rig.planner.task(task.id)?.scheduledStart == at(10))
        rig.planner.undoManager.undo()
        #expect(rig.planner.task(later.id)?.scheduledStart == at(11))
    }
}
