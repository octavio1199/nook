import Foundation
import Testing
@testable import Nook

@Suite struct TaskCheckInTests {
    private func setup() -> (FocusTimer, PlannerStore, TaskItem, [NotchAlert]) {
        let timer = FocusTimer()
        let planner = PlannerStore(url: nil)
        let task = TaskItem(title: "Write report")
        planner.add(task)
        timer.onSessionLogged = { planner.log($0) }
        timer.onTaskFinished = { planner.toggle($0) }
        return (timer, planner, task, [])
    }

    @Test func focusOnTaskAsksInsteadOfStartingTheBreak() {
        let (timer, _, task, _) = setup()
        var alerts: [NotchAlert] = []
        timer.onAlert = { alerts.append($0) }
        timer.startPomodoro(.with(id: "classic"), label: task.title, taskID: task.id)
        timer.tick(at: timer.now.addingTimeInterval(25 * 60 + 1))
        #expect(timer.awaitingDecision)
        #expect(!timer.isActive)
        #expect(alerts.last?.kind == .taskCheckIn)
        #expect(alerts.last?.sticky == true)
        #expect(alerts.last?.taskID == task.id)
    }

    @Test func extendAddsASessionToTheSameTask() {
        let (timer, planner, task, _) = setup()
        timer.startPomodoro(.with(id: "classic"), label: task.title, taskID: task.id)
        timer.tick(at: timer.now.addingTimeInterval(25 * 60 + 1))
        timer.extend(minutes: 5)
        #expect(timer.phase == .focus)
        #expect(timer.duration == 300)
        #expect(timer.taskID == task.id)
        timer.tick(at: timer.now.addingTimeInterval(5 * 60 + 1))
        #expect(planner.focusTime(for: task.id) >= 30 * 60)
        #expect(timer.awaitingDecision)
    }

    @Test func finishTaskMarksItDoneAndStartsTheBreak() {
        let (timer, planner, task, _) = setup()
        timer.startPomodoro(.with(id: "classic"), label: task.title, taskID: task.id)
        timer.tick(at: timer.now.addingTimeInterval(25 * 60 + 1))
        timer.finishTask()
        #expect(planner.task(task.id)?.done == true)
        #expect(timer.phase == .shortBreak)
        #expect(timer.taskID == nil)
        #expect(!timer.awaitingDecision)
    }

    @Test func breakThenContinueOffersTheTaskWhenTheBreakEnds() {
        let (timer, _, task, _) = setup()
        var alerts: [NotchAlert] = []
        timer.onAlert = { alerts.append($0) }
        timer.startPomodoro(.with(id: "classic"), label: task.title, taskID: task.id)
        timer.tick(at: timer.now.addingTimeInterval(25 * 60 + 1))
        timer.breakThenContinue()
        timer.tick(at: timer.now.addingTimeInterval(5 * 60 + 1))
        #expect(alerts.last?.kind == .breakFinished)
        #expect(alerts.last?.taskID == task.id)
        #expect(alerts.last?.detail?.contains("Write report") == true)
    }

    @Test func focusWithoutTaskStillAutoStartsTheBreak() {
        let timer = FocusTimer()
        timer.startPomodoro(.with(id: "classic"))
        timer.tick(at: timer.now.addingTimeInterval(25 * 60 + 1))
        #expect(timer.phase == .shortBreak)
        #expect(!timer.awaitingDecision)
    }
}
