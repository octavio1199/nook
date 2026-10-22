import Foundation
import Testing
@testable import Nook

@Suite struct ArchiveUndoTests {
    @Test func archiveHidesTaskAndRestoreBringsItBack() {
        let store = PlannerStore(url: nil)
        let task = TaskItem(title: "x")
        store.add(task)
        store.archive(task.id)
        #expect(store.todayTasks().isEmpty)
        #expect(store.archivedTasks().map(\.id) == [task.id])
        store.unarchive(task.id)
        #expect(store.todayTasks().map(\.id) == [task.id])
        #expect(store.archivedTasks().isEmpty)
    }

    @Test func undoRestoresArchivedTaskAndRedoArchivesAgain() {
        let store = PlannerStore(url: nil)
        store.undoManager.groupsByEvent = false
        let task = TaskItem(title: "x")
        store.undoManager.beginUndoGrouping(); store.add(task); store.undoManager.endUndoGrouping()
        store.undoManager.beginUndoGrouping(); store.archive(task.id); store.undoManager.endUndoGrouping()
        #expect(store.undoManager.undoActionName == "Archive Task")
        store.undoManager.undo()
        #expect(store.todayTasks().map(\.id) == [task.id])
        store.undoManager.redo()
        #expect(store.todayTasks().isEmpty)
    }

    @Test func undoDeleteForever() {
        let store = PlannerStore(url: nil)
        store.undoManager.groupsByEvent = false
        let task = TaskItem(title: "x")
        store.undoManager.beginUndoGrouping(); store.add(task); store.undoManager.endUndoGrouping()
        store.undoManager.beginUndoGrouping(); store.delete(task.id); store.undoManager.endUndoGrouping()
        #expect(store.tasks.isEmpty)
        store.undoManager.undo()
        #expect(store.tasks.map(\.id) == [task.id])
    }

    @Test func sentLineDisappearsWhenItsTaskIsDoneAndComesBackOnUndo() {
        let store = PlannerStore(url: nil)
        store.undoManager.groupsByEvent = false
        let day = Date()
        let key = DayKey.string(for: day)
        store.setNote("# Plan\n→ call Ana\nkeep this", for: day)
        let task = TaskItem(title: "call Ana", sourceDay: key, sourceLine: "call Ana")
        store.undoManager.beginUndoGrouping(); store.add(task); store.undoManager.endUndoGrouping()
        #expect(store.note(for: day).contains("→ call Ana"))
        store.undoManager.beginUndoGrouping(); store.toggle(task.id); store.undoManager.endUndoGrouping()
        #expect(store.note(for: day) == "# Plan\nkeep this")
        store.undoManager.undo()
        #expect(store.note(for: day).contains("→ call Ana"))
    }

    @Test func sentLineStaysWhileAnotherTaskFromTheSameLineIsOpen() {
        let store = PlannerStore(url: nil)
        let day = Date()
        let key = DayKey.string(for: day)
        store.setNote("→ a; b", for: day)
        let a = TaskItem(title: "a", sourceDay: key, sourceLine: "a; b")
        let b = TaskItem(title: "b", sourceDay: key, sourceLine: "a; b")
        store.add([a, b])
        store.archive(a.id)
        #expect(store.note(for: day) == "→ a; b")
        store.toggle(b.id)
        #expect(store.note(for: day).isEmpty)
    }
}
