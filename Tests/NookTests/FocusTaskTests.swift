import Foundation
import Testing
@testable import Nook

@Suite struct FocusTaskTests {
    private func wire() -> (FocusTimer, PlannerStore) {
        let timer = FocusTimer()
        let planner = PlannerStore(url: nil)
        timer.onSessionLogged = { planner.log($0) }
        timer.autoStartBreaks = { true }
        return (timer, planner)
    }

    private let preset = FocusPreset(id: "t", name: "T", focus: 25, shortBreak: 5, longBreak: 15, sessionsBeforeLongBreak: 4)

    @Test func sessionIsLoggedWithTaskID() {
        let (timer, planner) = wire()
        let task = TaskItem(title: "Write spec")
        planner.add(task)
        timer.startPomodoro(preset, label: task.title, taskID: task.id)
        timer.tick(at: timer.now.addingTimeInterval(5 * 60))
        timer.stop()
        #expect(planner.sessions.count == 1)
        #expect(planner.sessions.first?.taskID == task.id)
        #expect(planner.sessions.first?.label == "Write spec")
    }

    @Test func focusTimeSumsOnlyThatTask() {
        let planner = PlannerStore(url: nil)
        let a = UUID(), b = UUID()
        planner.log(FocusSession(start: .now, duration: 600, label: nil, taskID: a))
        planner.log(FocusSession(start: .now, duration: 900, label: nil, taskID: a))
        planner.log(FocusSession(start: .now, duration: 1200, label: nil, taskID: b))
        planner.log(FocusSession(start: .now, duration: 1200, label: nil, taskID: nil))
        #expect(planner.focusTime(for: a) == 1500)
        #expect(planner.focusTime(for: b) == 1200)
        #expect(planner.focusTime(for: UUID()) == 0)
    }

    @Test func focusOnUpdatesLabelAndTask() {
        let timer = FocusTimer()
        let task = TaskItem(title: "Review PR")
        timer.focus(on: task)
        #expect(timer.label == "Review PR")
        #expect(timer.taskID == task.id)
        timer.focus(on: nil)
        #expect(timer.label == nil)
        #expect(timer.taskID == nil)
    }

    @Test func labelPersistsAfterStop() {
        let (timer, _) = wire()
        let task = TaskItem(title: "Deep thing")
        timer.startPomodoro(preset, label: task.title, taskID: task.id)
        timer.stop()
        #expect(!timer.isActive)
        #expect(timer.label == "Deep thing")
        #expect(timer.taskID == task.id)
    }

    @Test func startNextFocusKeepsTask() {
        let (timer, planner) = wire()
        let task = TaskItem(title: "Keep going")
        planner.add(task)
        timer.startPomodoro(preset, label: task.title, taskID: task.id)
        timer.tick(at: timer.now.addingTimeInterval(25 * 60 + 1))
        #expect(timer.phase == .shortBreak)
        timer.startNextFocus()
        #expect(timer.phase == .focus)
        #expect(timer.taskID == task.id)
        #expect(timer.label == "Keep going")
        #expect(planner.focusTime(for: task.id) > 0)
    }
}
