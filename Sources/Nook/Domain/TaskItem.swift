import Foundation

struct TaskItem: Identifiable, Codable, Equatable, Hashable {
    enum Priority: Int, Codable, CaseIterable, Comparable {
        case none, low, medium, high

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .none: "None"
            case .low: "Low"
            case .medium: "Medium"
            case .high: "High"
            }
        }

        var shortTitle: String { self == .medium ? "Med" : title }
    }

    var id = UUID()
    var title: String
    var due: Date?
    var hasTime = false
    var priority: Priority = .none
    var tags: [String] = []
    var done = false
    var createdAt = Date()
    var completedAt: Date?
    var order: Double = 0
    /// Markdown notes attached to this task.
    var notes: String?
    /// `DayKey` of the notepad page this task was sent from with ⌘↩, if any.
    var sourceDay: String?
    /// The notepad line (without the "→ " marker) this task was sent from.
    var sourceLine: String?
    /// Set when the task is archived (soft-deleted); archived tasks can be restored.
    var archivedAt: Date?
}

extension TaskItem {
    var isOpen: Bool { !done && archivedAt == nil }

    func isDue(onOrBefore day: Date, calendar: Calendar = .current) -> Bool {
        guard let due else { return true }
        return calendar.startOfDay(for: due) <= calendar.startOfDay(for: day)
    }

    func isOverdue(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let due, !done else { return false }
        return hasTime ? due < now : calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }
}

// Tolerant decoding: older files or hand edits may miss fields.
extension TaskItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        due = try? c.decodeIfPresent(Date.self, forKey: .due)
        hasTime = (try? c.decodeIfPresent(Bool.self, forKey: .hasTime)) ?? false
        priority = (try? c.decodeIfPresent(Priority.self, forKey: .priority)) ?? .none
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        done = (try? c.decodeIfPresent(Bool.self, forKey: .done)) ?? false
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        completedAt = try? c.decodeIfPresent(Date.self, forKey: .completedAt)
        order = (try? c.decodeIfPresent(Double.self, forKey: .order)) ?? 0
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        sourceDay = try? c.decodeIfPresent(String.self, forKey: .sourceDay)
        sourceLine = try? c.decodeIfPresent(String.self, forKey: .sourceLine)
        archivedAt = try? c.decodeIfPresent(Date.self, forKey: .archivedAt)
    }
}
