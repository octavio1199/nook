import Foundation
import Observation

enum TaskScope: String, CaseIterable, Identifiable {
    case today, upcoming, done, archive
    var id: Self { self }

    /// Short labels so four segments fit a ~250pt column.
    var label: String {
        switch self {
        case .today: "Today"
        case .upcoming: "Next"
        case .done: "Done"
        case .archive: ""
        }
    }
}

/// UI state that must outlive the workspace views (they are destroyed whenever the panel isn't `.open`).
@Observable
final class WorkspaceState {
    var captureDraft = ""
    var taskScope: TaskScope = .today
    var detailTaskID: UUID?
    /// Day shown in the notepad (always a start-of-day date).
    private(set) var notesDay: Date
    /// True while the notepad shows today; it then moves along with the calendar at midnight.
    private(set) var notesFollowsToday = true
    /// Start of the current day, refreshed on day change / wake so views don't compute "today" once.
    private(set) var today: Date
    /// Shared so a toast survives closing and reopening the panel.
    @ObservationIgnored let toaster = UndoToaster()

    @ObservationIgnored private let calendar: Calendar

    init(now: Date = Date(), calendar: Calendar = .current) {
        self.calendar = calendar
        let start = calendar.startOfDay(for: now)
        today = start
        notesDay = start
    }

    var notesDayIsToday: Bool { calendar.isDate(notesDay, inSameDayAs: today) }

    /// Shows `date` in the notepad; landing on today re-arms midnight following.
    func selectNotesDay(_ date: Date) {
        let day = min(calendar.startOfDay(for: date), today)
        notesDay = day
        notesFollowsToday = calendar.isDate(day, inSameDayAs: today)
    }

    /// Call on `NSCalendarDayChanged`, wake, and panel open. Returns true when the day changed.
    @discardableResult
    func refreshToday(now: Date = Date()) -> Bool {
        let start = calendar.startOfDay(for: now)
        guard start != today else { return false }
        today = start
        if notesFollowsToday { notesDay = start }
        return true
    }
}
