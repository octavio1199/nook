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
}

extension TaskItem {
    func isDue(onOrBefore day: Date, calendar: Calendar = .current) -> Bool {
        guard let due else { return true }
        return calendar.startOfDay(for: due) <= calendar.startOfDay(for: day)
    }

    func isOverdue(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let due, !done else { return false }
        return hasTime ? due < now : calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }
}
