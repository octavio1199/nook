import Foundation
import CoreGraphics
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
    /// The task composer's draft (title, notes, chips, focus). Survives the panel closing.
    var composer = ComposerDraft()
    private(set) var isComposerOpen = false
    /// Which composer stop has the keyboard (Tab order) and the digits typed into the estimate.
    var composerKeys = ComposerKeyboard()
    /// The "start a focus" task picker (global shortcut).
    private(set) var isFocusPickerOpen = false
    var focusQuery = ""
    var focusSelection = 0
    /// Tasks column share of the Tasks + Notepad width (nil = the default split). Kept across launches.
    private(set) var tasksFraction: Double? {
        didSet { defaults?.set(tasksFraction, forKey: Self.tasksFractionKey) }
    }
    /// Last `NotchInteraction.captureRequest` the Tasks column acted on.
    @ObservationIgnored var seenCaptureRequest = 0
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
    @ObservationIgnored private let defaults: UserDefaults?
    private static let tasksFractionKey = "tasksColumnFraction"

    /// `defaults: nil` keeps the column width in memory only (tests, demo screenshots).
    init(now: Date = Date(), calendar: Calendar = .current, defaults: UserDefaults? = nil) {
        self.calendar = calendar
        self.defaults = defaults
        tasksFraction = defaults?.object(forKey: Self.tasksFractionKey) as? Double
        let start = calendar.startOfDay(for: now)
        today = start
        notesDay = start
    }

    /// The composer's title text (the old inline capture field's draft).
    var captureDraft: String {
        get { composer.title }
        set { composer.title = newValue }
    }

    func openComposer() {
        isFocusPickerOpen = false
        composerKeys = ComposerKeyboard()
        isComposerOpen = true
    }

    /// Esc / backdrop click: hides the composer but keeps the draft.
    func closeComposer() { isComposerOpen = false }

    /// After adding: forget the draft and hide the composer.
    func finishComposer() {
        composer = ComposerDraft()
        isComposerOpen = false
    }

    /// Esc handler for the panel: true when it closed the composer, so the panel itself stays open.
    @discardableResult
    func dismissComposerIfOpen() -> Bool {
        guard isComposerOpen else { return false }
        isComposerOpen = false
        return true
    }

    /// Esc: closes whichever overlay is up (composer or focus picker). True when it closed one.
    @discardableResult
    func dismissOverlayIfOpen() -> Bool {
        if dismissComposerIfOpen() { return true }
        guard isFocusPickerOpen else { return false }
        isFocusPickerOpen = false
        return true
    }

    // MARK: Focus picker

    func openFocusPicker() {
        isComposerOpen = false
        focusQuery = ""
        focusSelection = 0
        isFocusPickerOpen = true
    }

    func closeFocusPicker() { isFocusPickerOpen = false }

    /// Moves the highlighted row, staying inside `count` rows.
    func moveFocusSelection(by delta: Int, count: Int) {
        guard count > 0 else { focusSelection = 0; return }
        focusSelection = min(max(focusSelection + delta, 0), count - 1)
    }

    // MARK: Column widths

    static let minTasksWidth: CGFloat = 200
    static let minNotesWidth: CGFloat = 230
    /// Default Notepad width: enough for its full toolbar (the layout before columns were resizable).
    static let defaultNotesWidth: CGFloat = 296

    /// Tasks column width for `available` points shared by Tasks and Notepad.
    func tasksWidth(available: CGFloat) -> CGFloat {
        let width = tasksFraction.map { available * CGFloat($0) } ?? available - Self.defaultNotesWidth
        return Self.clampTasks(width.rounded(), available: available)
    }

    /// Divider drag: remembers the width as a fraction so a different panel width keeps the split.
    func setTasksWidth(_ width: CGFloat, available: CGFloat) {
        guard available > 0 else { return }
        tasksFraction = Double(Self.clampTasks(width, available: available) / available)
    }

    /// Double-click on the divider: back to the default split.
    func resetColumns() { tasksFraction = nil }

    private static func clampTasks(_ width: CGFloat, available: CGFloat) -> CGFloat {
        let upper = max(available - minNotesWidth, minTasksWidth)
        return min(max(width, minTasksWidth), upper)
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
