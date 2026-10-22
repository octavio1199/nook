import SwiftUI

extension Notification.Name {
    /// Posted when the user taps the "From notes" link on a task. `object` is the `DayKey` string.
    static let nookShowNotesDay = Notification.Name("nookShowNotesDay")
}

/// Task mutations shared by the list rows and the detail view.
enum TaskActions {
    enum Reschedule { case today, tomorrow, nextWeek, none }

    static func reschedule(_ task: TaskItem, to target: Reschedule, in planner: PlannerStore) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        var updated = task
        updated.hasTime = false
        switch target {
        case .today: updated.due = start
        case .tomorrow: updated.due = cal.date(byAdding: .day, value: 1, to: start)
        case .nextWeek: updated.due = cal.date(byAdding: .day, value: 7, to: start)
        case .none: updated.due = nil
        }
        withAnimation(Motion.navigate) { planner.update(updated) }
    }

    static func setPriority(_ task: TaskItem, _ priority: TaskItem.Priority, in planner: PlannerStore) {
        var updated = task
        updated.priority = priority
        planner.update(updated)
    }

    static func setEstimate(_ task: TaskItem, _ minutes: Int?, in planner: PlannerStore) {
        var updated = task
        updated.estimateMinutes = minutes
        planner.update(updated)
    }

    static func rename(_ task: TaskItem, to raw: String, planner: PlannerStore, focus: FocusTimer) {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != task.title else { return }
        var updated = task
        updated.title = title
        planner.update(updated)
        if focus.isActive, focus.taskID == task.id { focus.focus(on: updated) }
    }

    /// Starts a pomodoro on the task, or re-points the running session at it.
    static func focus(on task: TaskItem, timer: FocusTimer, settings: AppSettings) {
        if timer.isActive {
            timer.focus(on: task)
        } else {
            timer.startPomodoro(.with(id: settings.focusPresetID), label: task.title, taskID: task.id)
        }
    }

    static func focusTimeText(_ interval: TimeInterval) -> String? {
        let minutes = Int((interval / 60).rounded())
        guard minutes > 0 else { return nil }
        let h = minutes / 60, m = minutes % 60
        let text = h > 0 ? (m > 0 ? "\(h)h \(m)m" : "\(h)h") : "\(m)m"
        return "\(text) focused"
    }

    /// "Thu 22 Oct" for a `DayKey` string.
    static func dayText(_ key: String) -> String? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: key) else { return nil }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).replacingOccurrences(of: ",", with: "")
    }
}

/// Editor for task notes, backed by `MarkdownEditor`.
struct TaskNotesEditor: View {
    @Binding var text: String

    var body: some View {
        MarkdownEditor(text: $text, placeholder: "Notes — markdown supported")
    }
}
