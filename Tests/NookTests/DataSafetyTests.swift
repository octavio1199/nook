import Foundation
import Testing
@testable import Nook

@Suite struct DataSafetyTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("nook-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("planner.json")
    }

    @Test func undoNeverRevertsNotepadTypingOrSessions() {
        let store = PlannerStore(url: nil)
        store.undoManager.groupsByEvent = false
        let day = Date()
        store.undoManager.beginUndoGrouping(); store.add(TaskItem(title: "x")); store.undoManager.endUndoGrouping()
        store.setNote("three paragraphs typed after the action", for: day)
        store.log(FocusSession(start: day, duration: 600))
        store.undoManager.undo()
        #expect(store.tasks.isEmpty)
        #expect(store.note(for: day) == "three paragraphs typed after the action")
        #expect(store.sessions.count == 1)
    }

    @Test func undoKeepsTaskNotesTypedLater() {
        let store = PlannerStore(url: nil)
        store.undoManager.groupsByEvent = false
        let task = TaskItem(title: "x")
        store.undoManager.beginUndoGrouping(); store.add(task); store.undoManager.endUndoGrouping()
        store.undoManager.beginUndoGrouping(); store.toggle(task.id); store.undoManager.endUndoGrouping()
        store.setNotes("written after completing", for: task.id)
        store.undoManager.undo()
        #expect(store.task(task.id)?.done == false)
        #expect(store.task(task.id)?.notes == "written after completing")
    }

    @Test func undoPutsTheSentLineBackWithoutLosingOtherEdits() {
        let store = PlannerStore(url: nil)
        store.undoManager.groupsByEvent = false
        let day = Date()
        store.setNote("top\n→ call Ana\nbottom", for: day)
        let task = TaskItem(title: "call Ana", sourceDay: DayKey.string(for: day), sourceLine: "call Ana")
        store.undoManager.beginUndoGrouping(); store.add(task); store.undoManager.endUndoGrouping()
        store.undoManager.beginUndoGrouping(); store.toggle(task.id); store.undoManager.endUndoGrouping()
        #expect(store.note(for: day) == "top\nbottom")
        store.setNote("top\nbottom\nnew line typed later", for: day)
        store.undoManager.undo()
        #expect(store.note(for: day) == "top\n→ call Ana\nbottom\nnew line typed later")
    }

    @Test func restoringFromArchiveBringsTheLineBack() {
        let store = PlannerStore(url: nil)
        let day = Date()
        store.setNote("→ ship it", for: day)
        let task = TaskItem(title: "ship it", sourceDay: DayKey.string(for: day), sourceLine: "ship it")
        store.add(task)
        store.archive(task.id)
        #expect(store.note(for: day).isEmpty)
        store.unarchive(task.id)
        #expect(store.note(for: day) == "→ ship it")
    }

    @Test func missingFieldsDecodeWithDefaults() throws {
        let json = #"{"tasks":[{"title":"old task"},{"broken":true}],"notes":{"2026-10-22":"hi"}}"#
        let data = try JSONDecoder.planner.decode(PlannerData.self, from: Data(json.utf8))
        #expect(data.tasks.map(\.title) == ["old task"])
        #expect(data.tasks.first?.priority == TaskItem.Priority.none)
        #expect(data.notes["2026-10-22"] == "hi")
        #expect(data.sessions.isEmpty)
    }

    @Test func unreadableFileIsMovedAsideNotOverwritten() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json {".utf8).write(to: url)
        let store = PlannerStore(url: url)
        let aside = try #require(store.quarantinedFile)
        #expect(try String(contentsOf: aside, encoding: .utf8) == "not json {")
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.tasks.isEmpty)
    }

    @Test func goodFileGetsADailyBackup() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"tasks":[],"notes":{},"sessions":[]}"#.utf8).write(to: url)
        _ = PlannerStore(url: url)
        let dir = PlannerStore.backupsDirectory(next: url)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files == ["planner-\(DayKey.string(for: Date())).json"])
    }
}
