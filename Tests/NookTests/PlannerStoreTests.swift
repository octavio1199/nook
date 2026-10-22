import Foundation
import Testing
@testable import Nook

@Suite struct PlannerStoreTests {
    @Test func todayIncludesUndatedAndOverdue() {
        let store = PlannerStore(url: nil)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        store.add([TaskItem(title: "a"), TaskItem(title: "b", due: yesterday), TaskItem(title: "c", due: nextWeek)])
        #expect(store.todayTasks().map(\.title).sorted() == ["a", "b"])
        #expect(store.upcomingTasks().map(\.title) == ["c"])
    }

    @Test func toggleMovesToDone() {
        let store = PlannerStore(url: nil)
        let task = TaskItem(title: "x")
        store.add(task)
        store.toggle(task.id)
        #expect(store.doneTasks().map(\.id) == [task.id])
        #expect(store.todayTasks().isEmpty)
    }

    @Test func shortSessionsAreNotLogged() {
        let store = PlannerStore(url: nil)
        store.log(FocusSession(start: Date(), duration: 30))
        store.log(FocusSession(start: Date(), duration: 600))
        #expect(store.sessions.count == 1)
    }
}
