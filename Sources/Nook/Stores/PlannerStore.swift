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

    @ObservationIgnored let undoManager = UndoManager()
    @ObservationIgnored private let url: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Nook", isDirectory: true).appendingPathComponent("planner.json")
    }

    /// Pass `url: nil` for an in-memory store (tests, previews).
    init(url: URL? = PlannerStore.defaultURL) {
        self.url = url
        if let url, let raw = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder.planner.decode(PlannerData.self, from: raw) {
            data = decoded
        } else {
            data = PlannerData()
        }
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

    /// Every task mutation snapshots the whole store, so ⌘Z restores exactly what was there,
    /// including notepad lines that were cleaned up as a side effect.
    private func mutate(_ action: String, _ body: (inout PlannerData) -> Void) {
        let before = data
        body(&data)
        removeSentLines(resolvedSince: before)
        registerUndo(restoring: before, action: action)
        scheduleSave()
    }

    private func registerUndo(restoring snapshot: PlannerData, action: String) {
        let current = data
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                store.data = snapshot
                store.scheduleSave()
                store.registerUndo(restoring: current, action: action)
            }
        }
        undoManager.setActionName(action)
    }

    /// When every task sent from a notepad line (⌘↩) is done, archived or deleted,
    /// the "→ line" marker is removed from that day's note.
    private func removeSentLines(resolvedSince before: PlannerData) {
        let open = Set(data.tasks.filter { !$0.done && $0.archivedAt == nil }.compactMap(Self.sentLineKey))
        let candidates = Set(before.tasks.compactMap(Self.sentLineKey)).subtracting(open)
        for key in candidates {
            guard var note = data.notes[key.day] else { continue }
            var lines = note.components(separatedBy: "\n")
            guard let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "→ " + key.line }) else { continue }
            lines.remove(at: index)
            note = lines.joined(separator: "\n")
            if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { data.notes.removeValue(forKey: key.day) } else { data.notes[key.day] = note }
        }
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
