import Foundation
import Testing
@testable import Nook

@Suite struct StoreFixesTests {
    // MARK: Agenda

    @Test func occurrenceIDsDifferPerStart() {
        let a = AgendaModel.occurrenceID("evt", start: Date(timeIntervalSince1970: 1_000_000))
        let b = AgendaModel.occurrenceID("evt", start: Date(timeIntervalSince1970: 1_086_400))
        #expect(a != b)
        #expect(a == AgendaModel.occurrenceID("evt", start: Date(timeIntervalSince1970: 1_000_000)))
    }

    @Test func meetingLinkDetection() {
        #expect(AgendaEvent.meetingLink(in: [nil, "Room 4", "Join: https://us02web.zoom.us/j/123456"])?.host == "us02web.zoom.us")
        #expect(AgendaEvent.meetingLink(in: ["https://meet.google.com/abc-defg-hij"]) != nil)
        #expect(AgendaEvent.meetingLink(in: ["https://teams.microsoft.com/l/meetup-join/xyz"]) != nil)
        #expect(AgendaEvent.meetingLink(in: ["http://zoom.us/j/1"]) == nil)
        #expect(AgendaEvent.meetingLink(in: ["https://evil.com/zoom.us"]) == nil)
        #expect(AgendaEvent.meetingLink(in: ["https://notzoom.us/j/1"]) == nil)
    }

    // MARK: TaskDueWatcher

    private func watcher(_ tasks: [TaskItem], startedAt: Date) -> (TaskDueWatcher, [NotchAlert]) {
        let planner = PlannerStore(url: nil)
        planner.add(tasks)
        return (TaskDueWatcher(planner: planner, startedAt: startedAt), [])
    }

    @Test func dueWatcherFiresPerTaskNormally() {
        let t0 = Date()
        let (w, _) = watcher([
            TaskItem(title: "A", due: t0.addingTimeInterval(10), hasTime: true),
            TaskItem(title: "B", due: t0.addingTimeInterval(15), hasTime: true),
        ], startedAt: t0)
        var alerts: [NotchAlert] = []
        w.onAlert = { alerts.append($0) }
        w.check(now: t0.addingTimeInterval(20))
        #expect(alerts.map(\.headline).sorted() == ["A", "B"])
    }

    @Test func dueWatcherSkipsArchivedAndDone() {
        let t0 = Date()
        var archived = TaskItem(title: "Old", due: t0.addingTimeInterval(10), hasTime: true)
        archived.archivedAt = t0
        var done = TaskItem(title: "Done", due: t0.addingTimeInterval(10), hasTime: true)
        done.done = true
        let (w, _) = watcher([archived, done], startedAt: t0)
        var alerts: [NotchAlert] = []
        w.onAlert = { alerts.append($0) }
        w.check(now: t0.addingTimeInterval(20))
        #expect(alerts.isEmpty)
    }

    @Test func dueWatcherCoalescesAfterGap() {
        let t0 = Date()
        let (w, _) = watcher([
            TaskItem(title: "A", due: t0.addingTimeInterval(100), hasTime: true),
            TaskItem(title: "B", due: t0.addingTimeInterval(200), hasTime: true),
            TaskItem(title: "C", due: t0.addingTimeInterval(300), hasTime: true),
        ], startedAt: t0)
        var alerts: [NotchAlert] = []
        w.onAlert = { alerts.append($0) }
        w.check(now: t0.addingTimeInterval(3600)) // woke up an hour later
        #expect(alerts.count == 1)
        #expect(alerts.first?.headline == "3 tasks became due")
    }

    @Test func dueWatcherSingleStaleTaskUsesItsTitle() {
        let t0 = Date()
        let (w, _) = watcher([TaskItem(title: "Call Ana", due: t0.addingTimeInterval(100), hasTime: true)], startedAt: t0)
        var alerts: [NotchAlert] = []
        w.onAlert = { alerts.append($0) }
        w.check(now: t0.addingTimeInterval(3600))
        #expect(alerts.map(\.headline) == ["Call Ana"])
    }

    // MARK: Reorder

    private func order(_ store: PlannerStore) -> [String] {
        store.todayTasks().map(\.title)
    }

    @Test func dropAboveHigherPriorityAdoptsIt() {
        let store = PlannerStore(url: nil)
        store.undoManager.groupsByEvent = false
        store.undoManager.beginUndoGrouping()
        store.add([
            TaskItem(title: "H1", priority: .high), TaskItem(title: "H2", priority: .high),
            TaskItem(title: "Low", priority: .low),
        ])
        store.undoManager.endUndoGrouping()
        let ids = Dictionary(uniqueKeysWithValues: store.tasks.map { ($0.title, $0.id) })
        store.undoManager.beginUndoGrouping()
        store.move(ids["Low"]!, before: ids["H2"]!)
        store.undoManager.endUndoGrouping()
        #expect(order(store) == ["H1", "Low", "H2"])
        #expect(store.task(ids["Low"])?.priority == .high)
        store.undoManager.undo()
        #expect(order(store) == ["H1", "H2", "Low"])
        #expect(store.task(ids["Low"])?.priority == .low)
    }

    @Test func dropWithinSamePriorityKeepsPriority() {
        let store = PlannerStore(url: nil)
        store.add([TaskItem(title: "A"), TaskItem(title: "B"), TaskItem(title: "C")])
        let ids = Dictionary(uniqueKeysWithValues: store.tasks.map { ($0.title, $0.id) })
        store.move(ids["C"]!, before: ids["A"]!)
        #expect(order(store) == ["C", "A", "B"])
        #expect(store.task(ids["C"])?.priority == TaskItem.Priority.none)
    }

    @Test func repeatedMovesRenormalizeOrders() {
        let store = PlannerStore(url: nil)
        store.add([TaskItem(title: "A"), TaskItem(title: "B"), TaskItem(title: "C")])
        let ids = Dictionary(uniqueKeysWithValues: store.tasks.map { ($0.title, $0.id) })
        // Keep dropping C and B before A: the gap before A halves each time.
        for _ in 0..<60 {
            store.move(ids["C"]!, before: ids["A"]!)
            store.move(ids["B"]!, before: ids["A"]!)
        }
        #expect(order(store) == ["B", "A", "C"] || order(store) == ["C", "B", "A"] || order(store).count == 3)
        let orders = store.tasks.map(\.order).sorted()
        #expect(Set(orders).count == 3)
        store.move(ids["C"]!, before: ids["A"]!)
        let titles = order(store)
        #expect(titles.firstIndex(of: "C")! < titles.firstIndex(of: "A")!)
    }

    @Test func renormalizeKeepsRelativeOrder() {
        var tasks = [TaskItem(title: "x", order: 0.5), TaskItem(title: "y", order: 0.1), TaskItem(title: "z", order: 7)]
        PlannerStore.renormalizeOrders(&tasks)
        #expect(tasks.map(\.order) == [2, 1, 3])
    }
}
