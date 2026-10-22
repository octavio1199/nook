import Foundation

/// What the user has typed into the task composer. Lives in `WorkspaceState`, so it survives the panel closing.
/// Everything that turns the draft into tasks / a focus session is a pure function so it can be tested.
struct ComposerDraft: Equatable {
    /// Due date chosen with the chips. `.auto` leaves whatever the parser found in the title.
    enum Due: Equatable {
        case auto, none, today, tomorrow
        case date(Date)
    }

    var title = ""
    var notes = ""
    var due: Due = .auto
    /// nil: keep what the title says (`!high`).
    var priority: TaskItem.Priority?
    /// nil: keep what the title says (`~25m`).
    var estimateMinutes: Int?
    /// Comma separated, merged with `#tags` from the title.
    var tagsText = ""
    var startFocus = false
    /// nil: default to the estimate, then to the user's preset.
    var focusMinutes: Int?

    static let estimatePresets = [15, 25, 50, 60, 90]
    static let focusPresets = [15, 25, 50]
    static let focusRange = 5...180
    static let estimateRange = 5...480

    // MARK: Parsing

    func parsedTasks(now: Date = Date(), calendar: Calendar = .current) -> [TaskItem] {
        CaptureParser.parse(title, now: now, calendar: calendar)
    }

    /// Several lines or `;`: every line becomes its own task and the notes, chips and focus are ignored.
    func isBrainDump(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        parsedTasks(now: now, calendar: calendar).count > 1
    }

    /// True once anything besides the title has been touched.
    var hasExtras: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || due != .auto || priority != nil
            || estimateMinutes != nil || !tagsText.trimmingCharacters(in: .whitespaces).isEmpty || startFocus
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasExtras
    }

    // MARK: Draft -> tasks

    /// The tasks to create. A brain dump returns the parsed lines untouched; a single task gets the
    /// chip overrides and notes applied on top of what the parser found.
    func makeTasks(now: Date = Date(), calendar: Calendar = .current) -> [TaskItem] {
        let tasks = parsedTasks(now: now, calendar: calendar)
        guard tasks.count == 1, let task = tasks.first else { return tasks }
        return [applying(to: task, now: now, calendar: calendar)]
    }

    /// The draft's chip overrides and notes laid over a parsed task. Also drives the live chips,
    /// with a blank task when the title is still empty.
    func applying(to parsed: TaskItem, now: Date = Date(), calendar: Calendar = .current) -> TaskItem {
        var task = parsed
        switch due {
        case .auto: break
        case .none:
            task.due = nil
            task.hasTime = false
        case .today: task.due = Self.moving(task, toDayOf: now, calendar: calendar)
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            task.due = Self.moving(task, toDayOf: tomorrow, calendar: calendar)
        case .date(let day): task.due = Self.moving(task, toDayOf: day, calendar: calendar)
        }
        if let priority { task.priority = priority }
        if let estimateMinutes { task.estimateMinutes = estimateMinutes }
        for tag in Self.tags(from: tagsText) where !task.tags.contains(tag) { task.tags.append(tag) }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.notes = trimmed.isEmpty ? nil : trimmed
        return task
    }

    /// Moves the task's due date to `day`, keeping a time of day that came from the title ("3pm").
    private static func moving(_ task: TaskItem, toDayOf day: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        guard task.hasTime, let due = task.due else { return start }
        let time = calendar.dateComponents([.hour, .minute], from: due)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: start) ?? start
    }

    static func tags(from text: String) -> [String] {
        var seen: [String] = []
        for raw in text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" }) {
            let tag = raw.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces)).lowercased()
            if !tag.isEmpty, !seen.contains(tag) { seen.append(tag) }
        }
        return seen
    }

    // MARK: Focus

    /// Minutes the focus session would run: the picked length, else the estimate, else the user's preset.
    func focusMinutes(effectiveEstimate: Int?, preset: FocusPreset) -> Int {
        Self.focusMinutes(picked: focusMinutes, estimate: effectiveEstimate, preset: preset)
    }

    static func focusMinutes(picked: Int?, estimate: Int?, preset: FocusPreset) -> Int {
        let minutes = picked ?? estimate ?? preset.focus
        return min(max(minutes, focusRange.lowerBound), focusRange.upperBound)
    }

    /// The user's preset with the focus length replaced, so breaks and the check-in still work.
    static func focusPreset(base: FocusPreset, minutes: Int) -> FocusPreset {
        var copy = base
        copy.focus = minutes
        return copy
    }
}

extension TaskActions {
    /// Starts focusing on a task that was just created from the composer. A timer that is already
    /// running is pointed at the task instead of being replaced (replacing would drop its session).
    static func startComposerFocus(task: TaskItem, minutes: Int, timer: FocusTimer, settings: AppSettings) {
        if timer.isActive {
            timer.focus(on: task)
        } else {
            let preset = ComposerDraft.focusPreset(base: .with(id: settings.focusPresetID), minutes: minutes)
            timer.startPomodoro(preset, label: task.title, taskID: task.id)
        }
    }

    /// Focus logged against a task, plus the session that is running right now.
    static func trackedTime(for id: UUID, planner: PlannerStore, focus: FocusTimer) -> TimeInterval {
        var total = planner.focusTime(for: id)
        if focus.isActive, focus.taskID == id, focus.phase?.countsAsFocus == true { total += focus.elapsed }
        return total
    }
}

// MARK: - Keyboard

/// The composer's stops for Tab / Shift-Tab, in order. Title, tags and notes are text fields;
/// the others are pickers driven by arrows and typing.
enum ComposerField: Int, CaseIterable {
    case title, due, priority, estimate, tags, focus, notes

    var isText: Bool { self == .title || self == .tags || self == .notes }

    /// Next stop (wrapping). A brain dump only has the title.
    func moved(forward: Bool, brainDump: Bool) -> ComposerField {
        guard !brainDump else { return .title }
        let all = Self.allCases
        let index = (rawValue + (forward ? 1 : all.count - 1)) % all.count
        return all[index]
    }
}

/// A key press, already stripped of AppKit, so the composer's keyboard rules can be tested.
enum ComposerKey: Equatable {
    case tab(backward: Bool)
    case left, right, up, down
    case enter(option: Bool, command: Bool)
    case delete, space
    case character(Character)
}

enum ComposerKeyResult: Equatable {
    /// Not ours: let the focused text field (or the panel) have it.
    case pass
    case handled
    case submit(focus: Bool)
}

/// Keyboard rules for the composer. Pickers change the draft in place; `typed` collects the digits
/// typed into the estimate (and is cleared on every other key).
struct ComposerKeyboard: Equatable {
    var field: ComposerField = .title
    var typed = ""

    mutating func handle(_ key: ComposerKey, draft: inout ComposerDraft, now: Date = Date(), calendar: Calendar = .current) -> ComposerKeyResult {
        let brainDump = draft.isBrainDump(now: now, calendar: calendar)
        if case .tab(let backward) = key {
            typed = ""
            field = field.moved(forward: !backward, brainDump: brainDump)
            return .handled
        }
        if brainDump, field != .title { field = .title }
        if case .enter(let option, let command) = key {
            typed = ""
            // Return makes a new line in the notes; ⌘↩ / ⌥↩ still add from there.
            if field == .notes, !option, !command { return .pass }
            if brainDump { return .submit(focus: false) }
            return .submit(focus: option || draft.startFocus)
        }
        guard !field.isText else { return .pass }

        if case .character(let c) = key, c.isNumber, field == .estimate {
            typeDigit(c, draft: &draft, now: now, calendar: calendar)
            return .handled
        }
        if case .character(let c) = key, field == .estimate, c == "h", let hours = Int(typed) {
            draft.estimateMinutes = clamp(hours * 60, ComposerDraft.estimateRange)
            typed = ""
            return .handled
        }
        if key == .delete, field == .estimate, !typed.isEmpty {
            typed.removeLast()
            draft.estimateMinutes = Int(typed).map { clamp($0, ComposerDraft.estimateRange) }
            return .handled
        }
        typed = ""
        let effective = draft.applying(to: draft.parsedTasks(now: now, calendar: calendar).first ?? TaskItem(title: ""), now: now, calendar: calendar)
        switch field {
        case .due: handleDue(key, effective: effective, draft: &draft, now: now, calendar: calendar)
        case .priority: handlePriority(key, current: effective.priority, draft: &draft)
        case .estimate: handleEstimate(key, current: effective.estimateMinutes, draft: &draft)
        case .focus: handleFocus(key, estimate: effective.estimateMinutes, draft: &draft)
        case .title, .tags, .notes: return .pass
        }
        // Every key is swallowed on a picker, so nothing leaks into a text field behind it.
        return .handled
    }

    private mutating func typeDigit(_ c: Character, draft: inout ComposerDraft, now: Date, calendar: Calendar) {
        var next = typed + String(c)
        if let value = Int(next), value > ComposerDraft.estimateRange.upperBound { next = String(c) }
        typed = next
        let value = Int(typed) ?? 0
        draft.estimateMinutes = value == 0 ? nil : clamp(value, ComposerDraft.estimateRange)
    }

    // MARK: Pickers

    /// Days from today of the presets ←/→ cycle through (nil = no date).
    static let duePresets: [Int?] = [nil, 0, 1, 7]

    private func handleDue(_ key: ComposerKey, effective: TaskItem, draft: inout ComposerDraft, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        let offset = effective.due.map { calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: $0)).day ?? 0 }
        func set(_ days: Int?) {
            switch days {
            case nil: draft.due = .none
            case 0: draft.due = .today
            case 1: draft.due = .tomorrow
            case let days?: draft.due = .date(calendar.date(byAdding: .day, value: days, to: today) ?? today)
            }
        }
        switch key {
        case .right, .left:
            let presets = Self.duePresets
            let rank = offset ?? Int.min
            if key == .right {
                set(presets.first { ($0 ?? Int.min) > rank } ?? presets[0])
            } else {
                set(presets.last { ($0 ?? Int.min) < rank } ?? presets[presets.count - 1])
            }
        case .up: set((offset ?? -1) + 1)
        // Below today there is only "no date".
        case .down: set(offset.flatMap { $0 > 0 ? $0 - 1 : nil })
        case .delete: set(nil)
        case .character(let c):
            switch c.lowercased() {
            case "t": set(0)
            case "m": set(1)
            case "w": set(7)
            case "n": set(nil)
            default: break
            }
        default: break
        }
    }

    private func handlePriority(_ key: ComposerKey, current: TaskItem.Priority, draft: inout ComposerDraft) {
        let all = TaskItem.Priority.allCases
        func step(_ delta: Int) {
            draft.priority = all[min(max(current.rawValue + delta, 0), all.count - 1)]
        }
        switch key {
        case .up, .right: step(1)
        case .down, .left: step(-1)
        case .delete: draft.priority = TaskItem.Priority.none
        case .character(let c):
            switch c.lowercased() {
            case "h", "3": draft.priority = .high
            case "m", "2": draft.priority = .medium
            case "l", "1": draft.priority = .low
            case "n", "0": draft.priority = TaskItem.Priority.none
            default: break
            }
        default: break
        }
    }

    private func handleEstimate(_ key: ComposerKey, current: Int?, draft: inout ComposerDraft) {
        let presets = ComposerDraft.estimatePresets
        switch key {
        case .up: draft.estimateMinutes = clamp((current ?? 25) + 5, ComposerDraft.estimateRange)
        case .down: draft.estimateMinutes = clamp((current ?? 35) - 5, ComposerDraft.estimateRange)
        case .right: draft.estimateMinutes = presets.first { $0 > (current ?? 0) } ?? presets[0]
        case .left: draft.estimateMinutes = presets.last { $0 < (current ?? Int.max) } ?? presets[presets.count - 1]
        case .delete: draft.estimateMinutes = nil
        default: break
        }
    }

    private func handleFocus(_ key: ComposerKey, estimate: Int?, draft: inout ComposerDraft) {
        let presets = ComposerDraft.focusPresets
        let current = draft.focusMinutes ?? estimate
        switch key {
        case .space: draft.startFocus.toggle()
        case .up:
            draft.startFocus = true
            draft.focusMinutes = clamp((current ?? 25) + 5, ComposerDraft.focusRange)
        case .down:
            draft.startFocus = true
            draft.focusMinutes = clamp((current ?? 25) - 5, ComposerDraft.focusRange)
        case .right:
            draft.startFocus = true
            draft.focusMinutes = presets.first { $0 > (current ?? 0) } ?? presets[0]
        case .left:
            draft.startFocus = true
            draft.focusMinutes = presets.last { $0 < (current ?? Int.max) } ?? presets[presets.count - 1]
        case .delete: draft.startFocus = false
        default: break
        }
    }

    private func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
