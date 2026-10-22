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
        data.tasks.filter { !$0.done && $0.isDue(onOrBefore: now) }.sorted(by: Self.ordering)
    }

    func upcomingTasks(now: Date = Date()) -> [TaskItem] {
        data.tasks.filter { !$0.done && !$0.isDue(onOrBefore: now) }
            .sorted { ($0.due ?? .distantFuture, $0.order) < ($1.due ?? .distantFuture, $1.order) }
    }

    func doneTasks(limit: Int = 50) -> [TaskItem] {
        Array(data.tasks.filter(\.done).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }.prefix(limit))
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
        let base = (data.tasks.map(\.order).max() ?? 0) + 1
        for (offset, var task) in tasks.enumerated() {
            task.order = base + Double(offset)
            data.tasks.append(task)
        }
        scheduleSave()
    }

    func update(_ task: TaskItem) {
        guard let index = data.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        data.tasks[index] = task
        scheduleSave()
    }

    func toggle(_ id: TaskItem.ID) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[index].done.toggle()
        data.tasks[index].completedAt = data.tasks[index].done ? Date() : nil
        scheduleSave()
    }

    func delete(_ id: TaskItem.ID) {
        data.tasks.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Moves `id` so it sits right before `target` in manual ordering.
    func move(_ id: TaskItem.ID, before target: TaskItem.ID) {
        guard id != target, let targetOrder = data.tasks.first(where: { $0.id == target })?.order,
              let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        let previous = data.tasks.map(\.order).filter { $0 < targetOrder }.max() ?? (targetOrder - 1)
        data.tasks[index].order = (previous + targetOrder) / 2
        scheduleSave()
    }

    func task(_ id: TaskItem.ID?) -> TaskItem? {
        guard let id else { return nil }
        return data.tasks.first { $0.id == id }
    }

    func setNotes(_ notes: String, for id: TaskItem.ID) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
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
