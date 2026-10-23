import Foundation
import Observation

struct PlannerData: Codable {
    var tasks: [TaskItem] = []
    var notes: [String: String] = [:]
    var sessions: [FocusSession] = []
}

@Observable
final class PlannerStore {
    private(set) var data: PlannerData

    @ObservationIgnored let undoManager: UndoManager = {
        let manager = UndoManager()
        manager.levelsOfUndo = 100
        return manager
    }()
    @ObservationIgnored private var removedLineIndex: [SentLineKey: Int] = [:]
    @ObservationIgnored private let url: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Nook", isDirectory: true).appendingPathComponent("planner.json")
    }

    /// Set when planner.json existed but couldn't be read; the file was moved here untouched.
    @ObservationIgnored private(set) var quarantinedFile: URL?

    /// Pass `url: nil` for an in-memory store (tests, previews).
    init(url: URL? = PlannerStore.defaultURL) {
        self.url = url
        guard let url, let raw = try? Data(contentsOf: url) else {
            data = PlannerData()
            return
        }
        if let decoded = try? JSONDecoder.planner.decode(PlannerData.self, from: raw) {
            data = decoded
            Self.writeDailyBackup(raw, next: url)
        } else {
            // Never overwrite a file we can't read: move it aside so nothing is lost.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = url.deletingLastPathComponent().appendingPathComponent("planner.unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            quarantinedFile = aside
            data = PlannerData()
        }
    }

    static func backupsDirectory(next url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
    }

    /// One copy per day of the last good file, keeping the most recent 14.
    private static func writeDailyBackup(_ raw: Data, next url: URL) {
        let dir = backupsDirectory(next: url)
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("planner-\(DayKey.string(for: Date())).json")
        if !fm.fileExists(atPath: file.path) { try? raw.write(to: file, options: .atomic) }
        let backups = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix("planner-") }.sorted()
        for old in backups.dropLast(14) { try? fm.removeItem(at: dir.appendingPathComponent(old)) }
    }

    var tasks: [TaskItem] { data.tasks }
    var sessions: [FocusSession] { data.sessions }

    // MARK: - Task views

    func todayTasks(now: Date = Date()) -> [TaskItem] {
        data.tasks.filter { !$0.done && $0.archivedAt == nil && $0.isDue(onOrBefore: now) }.sorted(by: Self.ordering)
    }

    func upcomingTasks(now: Date = Date()) -> [TaskItem] {
        data.tasks.filter { !$0.done && $0.archivedAt == nil && !$0.isDue(onOrBefore: now) }
            .sorted { ($0.due ?? .distantFuture, $0.order) < ($1.due ?? .distantFuture, $1.order) }
    }

    func doneTasks(limit: Int = 50) -> [TaskItem] {
        Array(data.tasks.filter { $0.done && $0.archivedAt == nil }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }.prefix(limit))
    }

    private static func ordering(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.priority != b.priority { return a.priority > b.priority }
        if a.hasTime != b.hasTime { return a.hasTime }
        if a.hasTime, let da = a.due, let db = b.due, da != db { return da < db }
        return a.order < b.order
    }

    // MARK: - Task mutations

    func add(_ task: TaskItem) {
        add([task])
    }

    func add(_ tasks: [TaskItem]) {
        guard !tasks.isEmpty else { return }
        mutate(tasks.count == 1 ? "Add Task" : "Add Tasks") { data in
            let base = (data.tasks.map(\.order).max() ?? 0) + 1
            for (offset, var task) in tasks.enumerated() {
                task.order = base + Double(offset)
                data.tasks.append(task)
            }
        }
    }

    func update(_ task: TaskItem) {
        guard let index = data.tasks.firstIndex(where: { $0.id == task.id }), data.tasks[index] != task else { return }
        mutate("Edit Task") { $0.tasks[index] = task }
    }

    func toggle(_ id: TaskItem.ID) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate(data.tasks[index].done ? "Reopen Task" : "Complete Task") { data in
            data.tasks[index].done.toggle()
            data.tasks[index].completedAt = data.tasks[index].done ? Date() : nil
        }
    }

    /// Soft delete: the task moves to the archive, where it can be restored.
    func archive(_ id: TaskItem.ID) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate("Archive Task") { $0.tasks[index].archivedAt = Date() }
    }

    func unarchive(_ id: TaskItem.ID) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate("Restore Task") { $0.tasks[index].archivedAt = nil }
    }

    /// Archives every completed task at once.
    func archiveDone() {
        let now = Date()
        mutate("Archive Done Tasks") { data in
            for index in data.tasks.indices where data.tasks[index].done && data.tasks[index].archivedAt == nil {
                data.tasks[index].archivedAt = now
            }
        }
    }

    /// Permanent delete (from the archive). Still undoable with ⌘Z while the app runs.
    func delete(_ id: TaskItem.ID) {
        mutate("Delete Task") { $0.tasks.removeAll { $0.id == id } }
    }

    /// Moves `id` so it sits right before `target`. The list sorts by priority first, so a task
    /// dropped among a different priority adopts the target's priority to land where it was put.
    /// (Timed vs. untimed is decided by the due date, which a drag never edits.)
    func move(_ id: TaskItem.ID, before target: TaskItem.ID) {
        guard id != target, data.tasks.contains(where: { $0.id == target }), data.tasks.contains(where: { $0.id == id }) else { return }
        mutate("Move Task") { data in
            guard let targetIndex = data.tasks.firstIndex(where: { $0.id == target }),
                  let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
            data.tasks[index].priority = data.tasks[targetIndex].priority
            let priority = data.tasks[targetIndex].priority

            func neighbours() -> (previous: Double, target: Double, tied: Bool) {
                let t = data.tasks[targetIndex].order
                let group = data.tasks.indices.filter { $0 != index && data.tasks[$0].priority == priority }
                let previous = group.map { data.tasks[$0].order }.filter { $0 < t }.max() ?? (t - 1)
                let tied = group.contains { $0 != targetIndex && data.tasks[$0].order == t }
                return (previous, t, tied)
            }
            var n = neighbours()
            if n.target - n.previous < Self.minOrderGap || n.tied {
                Self.renormalizeOrders(&data.tasks)
                n = neighbours()
            }
            data.tasks[index].order = (n.previous + n.target) / 2
        }
    }

    static let minOrderGap = 1e-6

    /// Rewrites `order` as 1, 2, 3... keeping the current relative order (ties keep array order).
    static func renormalizeOrders(_ tasks: inout [TaskItem]) {
        let ranked = tasks.indices.sorted { (tasks[$0].order, $0) < (tasks[$1].order, $1) }
        for (rank, index) in ranked.enumerated() { tasks[index].order = Double(rank + 1) }
    }

    // MARK: - Time blocking

    /// Places a task on the timeline (or removes it with `start: nil`). `minutes` also updates the estimate.
    func schedule(_ id: TaskItem.ID, at start: Date?, minutes: Int? = nil) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate(start == nil ? "Unschedule Task" : "Schedule Task") { data in
            data.tasks[index].scheduledStart = start
            if let minutes { data.tasks[index].estimateMinutes = max(minutes, 5) }
        }
    }

    /// Applies many block moves as one undoable step ("Plan my day", "Push rest of day").
    func applySchedule(_ starts: [TaskItem.ID: Date?], action: String) {
        guard !starts.isEmpty else { return }
        mutate(action) { data in
            for index in data.tasks.indices {
                if let start = starts[data.tasks[index].id] { data.tasks[index].scheduledStart = start }
            }
        }
    }

    func setEstimate(_ minutes: Int?, for id: TaskItem.ID) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate("Change Estimate") { $0.tasks[index].estimateMinutes = minutes.map { max($0, 5) } }
    }

    /// Open tasks with a block on the given day, in time order.
    func scheduledTasks(on day: Date, calendar: Calendar = .current) -> [TaskItem] {
        data.tasks
            .filter { $0.isOpen && $0.scheduledStart.map { calendar.isDate($0, inSameDayAs: day) } == true }
            .sorted { ($0.scheduledStart ?? .distantPast) < ($1.scheduledStart ?? .distantPast) }
    }

    func archivedTasks() -> [TaskItem] {
        data.tasks.filter { $0.archivedAt != nil }.sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    // MARK: - Undo

    /// Task mutations snapshot only `tasks`. Notes and focus sessions are never rolled back by
    /// ⌘Z, so typing in the notepad or a task's notes after an action can't be lost by undoing it.
    /// Notepad "→ line" markers are reconciled from the task change in both directions.
    private func mutate(_ action: String, _ body: (inout PlannerData) -> Void) {
        let before = data.tasks
        body(&data)
        reconcileSentLines(from: before)
        registerUndo(restoring: before, action: action)
        scheduleSave()
    }

    private func registerUndo(restoring tasks: [TaskItem], action: String) {
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                let current = store.data.tasks
                store.restore(tasks)
                store.reconcileSentLines(from: current)
                store.scheduleSave()
                store.registerUndo(restoring: current, action: action)
            }
        }
        undoManager.setActionName(action)
    }

    /// Puts back a tasks snapshot but keeps each task's current notes (they have their own text undo).
    private func restore(_ tasks: [TaskItem]) {
        let notes = Dictionary(data.tasks.map { ($0.id, $0.notes) }, uniquingKeysWith: { first, _ in first })
        data.tasks = tasks.map { task in
            var task = task
            if let current = notes[task.id] { task.notes = current }
            return task
        }
    }

    /// When every task sent from a notepad line (⌘↩) is done, archived or deleted, the
    /// "→ line" marker leaves that day's note; when one becomes open again (undo, restore,
    /// reopen) the marker comes back where it was.
    private func reconcileSentLines(from before: [TaskItem]) {
        let openNow = Set(data.tasks.filter(\.isOpen).compactMap(Self.sentLineKey))
        let openBefore = Set(before.filter(\.isOpen).compactMap(Self.sentLineKey))
        let existedBefore = Set(before.map(\.id))
        let reopened = Set(data.tasks.filter { $0.isOpen && existedBefore.contains($0.id) }.compactMap(Self.sentLineKey))
            .subtracting(openBefore)

        for key in Set(before.compactMap(Self.sentLineKey)).subtracting(openNow) {
            var lines = (data.notes[key.day] ?? "").components(separatedBy: "\n")
            guard let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "→ " + key.line }) else { continue }
            lines.remove(at: index)
            removedLineIndex[key] = index
            setNoteText(lines.joined(separator: "\n"), key: key.day)
        }
        for key in reopened {
            var lines = (data.notes[key.day] ?? "").components(separatedBy: "\n")
            guard !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "→ " + key.line }) else { continue }
            if lines == [""] { lines = [] }
            lines.insert("→ " + key.line, at: min(removedLineIndex[key] ?? lines.count, lines.count))
            setNoteText(lines.joined(separator: "\n"), key: key.day)
        }
    }

    private func setNoteText(_ text: String, key: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { data.notes.removeValue(forKey: key) } else { data.notes[key] = text }
    }

    private struct SentLineKey: Hashable {
        var day: String
        var line: String
    }

    private static func sentLineKey(_ task: TaskItem) -> SentLineKey? {
        guard let day = task.sourceDay, let line = task.sourceLine else { return nil }
        return SentLineKey(day: day, line: line.trimmingCharacters(in: .whitespaces))
    }

    func task(_ id: TaskItem.ID?) -> TaskItem? {
        guard let id else { return nil }
        return data.tasks.first { $0.id == id }
    }

    func setNotes(_ notes: String, for id: TaskItem.ID) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        // Typing in a task's notes has its own text undo, so this bypasses the store's undo.
        data.tasks[index].notes = notes.isEmpty ? nil : notes
        scheduleSave()
    }

    /// Total focus logged against a task.
    func focusTime(for id: TaskItem.ID) -> TimeInterval {
        data.sessions.filter { $0.taskID == id }.reduce(0) { $0 + $1.duration }
    }

    // MARK: - Notes

    func note(for day: Date) -> String {
        data.notes[DayKey.string(for: day)] ?? ""
    }

    func setNote(_ text: String, for day: Date) {
        let key = DayKey.string(for: day)
        if text.isEmpty { data.notes.removeValue(forKey: key) } else { data.notes[key] = text }
        scheduleSave()
    }

    // MARK: - Focus log

    func log(_ session: FocusSession) {
        guard session.duration >= 60 else { return }
        data.sessions.append(session)
        scheduleSave()
    }

    // MARK: - Manual focus logs (Day tab, past days)

    func sessions(on day: Date, calendar: Calendar = .current) -> [FocusSession] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return data.sessions.filter { $0.end > start && $0.start < end }.sorted { $0.start < $1.start }
    }

    /// Time that wasn't tracked, added by hand. Undoable.
    @discardableResult
    func logManual(taskID: TaskItem.ID?, label: String?, start: Date, minutes: Int) -> FocusSession {
        let session = FocusSession(start: start, duration: TimeInterval(max(minutes, 5) * 60), label: label, taskID: taskID, manual: true)
        mutateManualSessions("Log Time") { $0.append(session) }
        return session
    }

    func updateManualSession(_ id: FocusSession.ID, start: Date, minutes: Int) {
        mutateManualSessions("Change Logged Time") { sessions in
            guard let index = sessions.firstIndex(where: { $0.id == id && $0.manual }) else { return }
            sessions[index].start = start
            sessions[index].duration = TimeInterval(max(minutes, 5) * 60)
        }
    }

    func deleteManualSession(_ id: FocusSession.ID) {
        mutateManualSessions("Delete Logged Time") { $0.removeAll { $0.id == id && $0.manual } }
    }

    /// Marks a task done at a given moment (the end of a logged block), not now.
    func complete(_ id: TaskItem.ID, at date: Date) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate("Mark Done") { data in
            data.tasks[index].done = true
            data.tasks[index].completedAt = date
        }
    }

    /// Undo for hand-made logs snapshots only the manual sessions, so ⌘Z never drops time a timer
    /// logged in between.
    private func mutateManualSessions(_ action: String, _ body: (inout [FocusSession]) -> Void) {
        let before = data.sessions.filter(\.manual)
        body(&data.sessions)
        registerManualUndo(restoring: before, action: action)
        scheduleSave()
    }

    private func registerManualUndo(restoring manual: [FocusSession], action: String) {
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                let current = store.data.sessions.filter(\.manual)
                store.data.sessions = store.data.sessions.filter { !$0.manual } + manual
                store.scheduleSave()
                store.registerManualUndo(restoring: current, action: action)
            }
        }
        undoManager.setActionName(action)
    }

    // MARK: - Sub-tasks

    func addSubtask(_ title: String, to id: TaskItem.ID) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate("Add Sub-task") { $0.tasks[index].subtasks.append(Subtask(title: trimmed)) }
    }

    func toggleSubtask(_ subtask: Subtask.ID, in id: TaskItem.ID) {
        editSubtasks(of: id, action: "Check Sub-task") { list in
            guard let i = list.firstIndex(where: { $0.id == subtask }) else { return }
            list[i].done.toggle()
        }
    }

    func renameSubtask(_ subtask: Subtask.ID, in id: TaskItem.ID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        editSubtasks(of: id, action: "Rename Sub-task") { list in
            guard let i = list.firstIndex(where: { $0.id == subtask }), list[i].title != trimmed else { return }
            list[i].title = trimmed
        }
    }

    func deleteSubtask(_ subtask: Subtask.ID, in id: TaskItem.ID) {
        editSubtasks(of: id, action: "Delete Sub-task") { $0.removeAll { $0.id == subtask } }
    }

    /// Moves a sub-task one step up (-1) or down (+1).
    func moveSubtask(_ subtask: Subtask.ID, in id: TaskItem.ID, by offset: Int) {
        editSubtasks(of: id, action: "Move Sub-task") { list in
            guard let i = list.firstIndex(where: { $0.id == subtask }) else { return }
            let j = i + offset
            guard list.indices.contains(j) else { return }
            list.swapAt(i, j)
        }
    }

    private func editSubtasks(of id: TaskItem.ID, action: String, _ body: (inout [Subtask]) -> Void) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        var list = data.tasks[index].subtasks
        body(&list)
        guard list != data.tasks[index].subtasks else { return }
        mutate(action) { $0.tasks[index].subtasks = list }
    }

    // MARK: - Persistence

    func exportJSON() throws -> Data {
        try JSONEncoder.planner.encode(data)
    }

    private func scheduleSave() {
        guard url != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            saveNow()
        }
    }

    func saveNow() {
        guard let url, let raw = try? JSONEncoder.planner.encode(data) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? raw.write(to: url, options: .atomic)
    }
}

extension JSONEncoder {
    static var planner: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var planner: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// Tolerant decoding: a missing field falls back to its default instead of failing the file.
extension PlannerData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = (try? c.decodeIfPresent([Lossy<TaskItem>].self, forKey: .tasks))?.compactMap { $0.value } ?? []
        notes = (try? c.decodeIfPresent([String: String].self, forKey: .notes)) ?? [:]
        sessions = (try? c.decodeIfPresent([Lossy<FocusSession>].self, forKey: .sessions))?.compactMap { $0.value } ?? []
    }
}

/// Decodes an element if it can, so one bad entry doesn't drop the whole array.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
