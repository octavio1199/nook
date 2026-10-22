import Foundation

/// Pure aggregation of tasks and focus sessions for the Insights tab.
nonisolated struct InsightsSummary: Equatable {
    struct Day: Identifiable, Equatable {
        var date: Date
        var focusMinutes: Int
        var tasksDone: Int
        var id: Date { date }
        var isActive: Bool { focusMinutes > 0 || tasksDone > 0 }
    }

    struct TaskTotal: Identifiable, Equatable {
        var id: UUID
        var title: String
        var duration: TimeInterval
        var sessions: Int
        var done: Bool
    }

    /// Time spent per task over the last 7 days, longest first (at most `topTaskLimit`).
    var taskTimes: [TaskTotal] = []
    static let topTaskLimit = 5

    /// Last 7 days, oldest first, ending today.
    var days: [Day] = []
    var tasksDoneToday = 0
    var focusMinutesToday = 0
    var streak = 0
    var focusMinutesThisWeek = 0
    var bestDay: Day?
    /// Hour of day (0...23) with the most focus time across all sessions.
    var mostFocusedHour: Int?

    var focusHoursThisWeek: Double { Double(focusMinutesThisWeek) / 60 }

    init(tasks: [TaskItem], sessions: [FocusSession], now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)

        var tasksByDay: [Date: Int] = [:]
        for task in tasks where task.done {
            guard let completed = task.completedAt else { continue }
            tasksByDay[calendar.startOfDay(for: completed), default: 0] += 1
        }
        var focusByDay: [Date: TimeInterval] = [:]
        var focusByHour: [Int: TimeInterval] = [:]
        for session in sessions {
            focusByDay[calendar.startOfDay(for: session.start), default: 0] += session.duration
            focusByHour[calendar.component(.hour, from: session.start), default: 0] += session.duration
        }

        days = (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return Day(
                date: date,
                focusMinutes: Int((focusByDay[date] ?? 0) / 60),
                tasksDone: tasksByDay[date] ?? 0
            )
        }
        tasksDoneToday = tasksByDay[today] ?? 0
        focusMinutesToday = Int((focusByDay[today] ?? 0) / 60)
        focusMinutesThisWeek = days.reduce(0) { $0 + $1.focusMinutes }

        // Streak: consecutive active days; today may still be empty without breaking it.
        func isActive(_ date: Date) -> Bool { (tasksByDay[date] ?? 0) > 0 || (focusByDay[date] ?? 0) > 0 }
        var cursor = today
        if !isActive(cursor), let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) { cursor = yesterday }
        var count = 0
        while isActive(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        streak = count

        bestDay = days.filter(\.isActive).max {
            ($0.focusMinutes, $0.tasksDone) < ($1.focusMinutes, $1.tasksDone)
        }

        // Time per task: sessions of the last 7 days that belong to a task, grouped by task.
        if let weekStart = days.first?.date {
            var byTask: [UUID: (duration: TimeInterval, sessions: Int, label: String?)] = [:]
            for session in sessions where session.start >= weekStart {
                guard let id = session.taskID else { continue }
                var entry = byTask[id] ?? (0, 0, nil)
                entry.duration += session.duration
                entry.sessions += 1
                entry.label = session.label ?? entry.label
                byTask[id] = entry
            }
            let titles = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            taskTimes = byTask
                .map { id, entry in
                    TaskTotal(id: id, title: titles[id]?.title ?? entry.label ?? "Deleted task",
                             duration: entry.duration, sessions: entry.sessions, done: titles[id]?.done ?? false)
                }
                .filter { $0.duration >= TaskTime.minimum }
                .sorted { ($0.duration, $1.title) > ($1.duration, $0.title) }
                .prefix(Self.topTaskLimit)
                .map { $0 }
        }
        mostFocusedHour = focusByHour.max { $0.value < $1.value }?.key
    }
}
