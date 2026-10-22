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

    /// Moves `id` so it sits right before `target` in manual ordering.
    func move(_ id: TaskItem.ID, before target: TaskItem.ID) {
        guard id != target, let targetOrder = data.tasks.first(where: { $0.id == target })?.order,
              let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        let previous = data.tasks.map(\.order).filter { $0 < targetOrder }.max() ?? (targetOrder - 1)
        mutate("Move Task") { $0.tasks[index].order = (previous + targetOrder) / 2 }
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
