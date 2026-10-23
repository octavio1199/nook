import Carbon.HIToolbox
import Foundation
import Testing
@testable import Nook

/// The new-task card driven from the keyboard only.
@Suite struct ComposerKeyboardTests {
    // Wednesday 2025-01-15 10:00 in Sao Paulo.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }()
    static let now = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 10))!

    private func day(_ d: Int) -> Date {
        Self.calendar.date(from: DateComponents(year: 2025, month: 1, day: d))!
    }

    private func press(_ keys: [ComposerKey], _ keyboard: inout ComposerKeyboard, _ draft: inout ComposerDraft) -> [ComposerKeyResult] {
        keys.map { keyboard.handle($0, draft: &draft, now: Self.now, calendar: Self.calendar) }
    }

    private func task(_ draft: ComposerDraft) -> TaskItem {
        draft.makeTasks(now: Self.now, calendar: Self.calendar)[0]
    }

    @Test func tabVisitsEveryStopInOrderAndWraps() {
        var keyboard = ComposerKeyboard()
        var draft = ComposerDraft()
        draft.title = "write spec"
        var seen: [ComposerField] = []
        for _ in 0..<7 {
            _ = keyboard.handle(.tab(backward: false), draft: &draft)
            seen.append(keyboard.field)
        }
        #expect(seen == [.due, .priority, .estimate, .tags, .focus, .notes, .title])
        _ = keyboard.handle(.tab(backward: true), draft: &draft)
        #expect(keyboard.field == .notes)
    }

    @Test func tabLeavesTheNotesInsteadOfTyping() {
        var keyboard = ComposerKeyboard(field: .notes)
        var draft = ComposerDraft()
        draft.title = "write spec"
        #expect(keyboard.handle(.tab(backward: false), draft: &draft) == .handled)
        #expect(keyboard.field == .title)
        #expect(draft.notes.isEmpty)
    }

    @Test func brainDumpOnlyHasTheTitle() {
        var keyboard = ComposerKeyboard()
        var draft = ComposerDraft()
        draft.title = "a; b"
        _ = keyboard.handle(.tab(backward: false), draft: &draft)
        #expect(keyboard.field == .title)
        #expect(keyboard.handle(.enter(option: true, command: false), draft: &draft) == .submit(focus: false))
    }

    @Test func returnAddsFromEverywhereButNotes() {
        var draft = ComposerDraft()
        draft.title = "write spec"
        for field in ComposerField.allCases where field != .notes {
            var keyboard = ComposerKeyboard(field: field)
            #expect(keyboard.handle(.enter(option: false, command: false), draft: &draft) == .submit(focus: false), "\(field)")
            #expect(keyboard.handle(.enter(option: true, command: false), draft: &draft) == .submit(focus: true), "\(field)")
        }
        var notes = ComposerKeyboard(field: .notes)
        #expect(notes.handle(.enter(option: false, command: false), draft: &draft) == .pass)
        #expect(notes.handle(.enter(option: false, command: true), draft: &draft) == .submit(focus: false))
        draft.startFocus = true
        var title = ComposerKeyboard()
        #expect(title.handle(.enter(option: false, command: false), draft: &draft) == .submit(focus: true))
    }

    @Test func textStopsLetKeysThrough() {
        var draft = ComposerDraft()
        for field in [ComposerField.title, .tags, .notes] {
            var keyboard = ComposerKeyboard(field: field)
            #expect(keyboard.handle(.left, draft: &draft) == .pass)
            #expect(keyboard.handle(.character("x"), draft: &draft) == .pass)
            #expect(keyboard.handle(.delete, draft: &draft) == .pass)
        }
    }

    @Test func dueArrowsAndLetters() {
        var keyboard = ComposerKeyboard(field: .due)
        var draft = ComposerDraft()
        draft.title = "write spec"
        _ = press([.right], &keyboard, &draft)
        #expect(task(draft).due == day(15))
        _ = press([.right], &keyboard, &draft)
        #expect(task(draft).due == day(16))
        _ = press([.right], &keyboard, &draft)
        #expect(task(draft).due == day(22))
        _ = press([.right], &keyboard, &draft)
        #expect(task(draft).due == nil)
        _ = press([.left], &keyboard, &draft)
        #expect(task(draft).due == day(22))
        _ = press([.up, .up], &keyboard, &draft)
        #expect(task(draft).due == day(24))
        _ = press([.character("t")], &keyboard, &draft)
        #expect(task(draft).due == day(15))
        _ = press([.down], &keyboard, &draft)
        #expect(task(draft).due == nil)
        _ = press([.character("m")], &keyboard, &draft)
        #expect(task(draft).due == day(16))
        _ = press([.delete], &keyboard, &draft)
        #expect(task(draft).due == nil)
    }

    @Test func dueKeepsTheTimeFromTheTitle() {
        var keyboard = ComposerKeyboard(field: .due)
        var draft = ComposerDraft()
        draft.title = "call Ana tomorrow 3pm"
        _ = press([.up], &keyboard, &draft)
        let t = task(draft)
        #expect(t.hasTime)
        #expect(t.due == Self.calendar.date(from: DateComponents(year: 2025, month: 1, day: 17, hour: 15)))
    }

    @Test func priorityArrowsAndLetters() {
        var keyboard = ComposerKeyboard(field: .priority)
        var draft = ComposerDraft()
        draft.title = "write spec !low"
        _ = press([.up], &keyboard, &draft)
        #expect(task(draft).priority == .medium)
        _ = press([.up, .up, .up], &keyboard, &draft)
        #expect(task(draft).priority == .high)
        _ = press([.character("l")], &keyboard, &draft)
        #expect(task(draft).priority == .low)
        _ = press([.down, .down], &keyboard, &draft)
        #expect(task(draft).priority == TaskItem.Priority.none)
        _ = press([.character("2")], &keyboard, &draft)
        #expect(task(draft).priority == .medium)
    }

    @Test func estimateTypingAndArrows() {
        var keyboard = ComposerKeyboard(field: .estimate)
        var draft = ComposerDraft()
        draft.title = "write spec"
        _ = press([.character("4"), .character("5")], &keyboard, &draft)
        #expect(task(draft).estimateMinutes == 45)
        _ = press([.delete], &keyboard, &draft)
        #expect(task(draft).estimateMinutes == 4 + 1) // "4" is below the 5 min floor
        _ = press([.up], &keyboard, &draft)
        #expect(task(draft).estimateMinutes == 10)
        _ = press([.character("2"), .character("h")], &keyboard, &draft)
        #expect(task(draft).estimateMinutes == 120)
        _ = press([.right], &keyboard, &draft)
        #expect(task(draft).estimateMinutes == 15) // past the last preset wraps to the first
        _ = press([.right, .right], &keyboard, &draft)
        #expect(task(draft).estimateMinutes == 50)
        _ = press([.left], &keyboard, &draft)
        #expect(task(draft).estimateMinutes == 25)
        _ = press([.delete], &keyboard, &draft)
        #expect(task(draft).estimateMinutes == nil)
    }

    @Test func focusToggleAndLength() {
        var keyboard = ComposerKeyboard(field: .focus)
        var draft = ComposerDraft()
        draft.title = "write spec ~50m"
        _ = press([.space], &keyboard, &draft)
        #expect(draft.startFocus)
        _ = press([.down], &keyboard, &draft)
        #expect(draft.focusMinutes == 45) // from the estimate
        _ = press([.left], &keyboard, &draft)
        #expect(draft.focusMinutes == 25)
        _ = press([.space], &keyboard, &draft)
        #expect(!draft.startFocus)
    }

    @Test func pickersSwallowStrayKeys() {
        var keyboard = ComposerKeyboard(field: .priority)
        var draft = ComposerDraft()
        draft.title = "write spec"
        #expect(keyboard.handle(.character("z"), draft: &draft) == .handled)
        #expect(draft.title == "write spec")
    }

    @Test func endToEndWithoutTheMouse() {
        var keyboard = ComposerKeyboard()
        var draft = ComposerDraft()
        draft.title = "write spec" // typed into the focused title field
        let results = press([
            .tab(backward: false), .character("m"), // due: tomorrow
            .tab(backward: false), .character("h"), // priority: high
            .tab(backward: false), .character("3"), .character("0"), // estimate: 30
            .tab(backward: false), .tab(backward: false), .space, // skip tags, focus on
            .enter(option: false, command: false),
        ], &keyboard, &draft)
        #expect(results.last == .submit(focus: true))
        let t = task(draft)
        #expect(t.due == day(16))
        #expect(t.priority == .high)
        #expect(t.estimateMinutes == 30)
        #expect(draft.focusMinutes(effectiveEstimate: t.estimateMinutes, preset: .with(id: "classic")) == 30)
    }
}

@Suite struct ShortcutTests {
    private func settings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "ShortcutTests-\(UUID().uuidString)")!)
    }

    @Test func symbolsUseMenuOrder() {
        let s = Shortcut(keyCode: kVK_ANSI_K, modifiers: cmdKey | shiftKey | optionKey | controlKey, key: "K")
        #expect(s.symbols == "⌃⌥⇧⌘K")
    }

    @Test func recordingNeedsARealModifier() {
        #expect(Shortcut(keyCode: kVK_ANSI_K, flags: [.shift], characters: "k") == nil)
        #expect(Shortcut(keyCode: kVK_ANSI_K, flags: [], characters: "k") == nil)
        #expect(Shortcut(keyCode: kVK_Escape, flags: [.command], characters: "\u{1b}") == nil)
        #expect(Shortcut(keyCode: kVK_ANSI_K, flags: [.control, .option], characters: "k")?.symbols == "⌃⌥K")
        #expect(Shortcut(keyCode: kVK_Space, flags: [.command, .option], characters: " ")?.symbols == "⌥⌘Space")
    }

    @Test func defaultsAreDistinct() {
        let all = GlobalAction.allCases.map(\.defaultShortcut)
        #expect(Set(all).count == all.count)
        #expect(GlobalAction.newTask.defaultShortcut.symbols == "⌥⌘N")
    }

    @Test func rebindPersistsAndConflictsAreRefused() {
        let defaults = UserDefaults(suiteName: "ShortcutTests-\(UUID().uuidString)")!
        let s = AppSettings(defaults: defaults)
        let custom = Shortcut(keyCode: kVK_ANSI_J, modifiers: controlKey | optionKey, key: "J")
        #expect(s.setShortcut(custom, for: .toggle) == nil)
        #expect(s.shortcut(for: .toggle) == custom)
        #expect(AppSettings(defaults: defaults).shortcut(for: .toggle) == custom)

        #expect(s.setShortcut(custom, for: .pin) == .toggle)
        #expect(s.shortcut(for: .pin) == GlobalAction.pin.defaultShortcut)

        s.resetShortcut(for: .toggle)
        #expect(s.shortcut(for: .toggle) == GlobalAction.toggle.defaultShortcut)
        #expect(AppSettings(defaults: defaults).shortcut(for: .toggle) == GlobalAction.toggle.defaultShortcut)
        _ = settings()
    }
}

@Suite struct FocusPickerTests {
    private func task(_ title: String, tags: [String] = [], estimate: Int? = nil) -> TaskItem {
        var t = TaskItem(title: title, tags: tags)
        t.estimateMinutes = estimate
        return t
    }

    @Test func emptyQueryListsTodayAfterNoTask() {
        let a = task("Write report"), b = task("Email")
        let items = FocusPicker.items(today: [a, b], upcoming: [task("Later")], query: "  ")
        #expect(items == [.noTask, .task(a), .task(b)])
    }

    @Test func queryMatchesWordsInTitleAndTagsAcrossTodayAndUpcoming() {
        let a = task("Revisão do relatório", tags: ["work"])
        let b = task("Email Ana")
        let later = task("Report deck", tags: ["work"])
        #expect(FocusPicker.items(today: [a, b], upcoming: [later], query: "revisao") == [.task(a)])
        #expect(FocusPicker.items(today: [a, b], upcoming: [later], query: "work") == [.task(a), .task(later)])
        #expect(FocusPicker.items(today: [a, b], upcoming: [later], query: "work deck") == [.task(later)])
        #expect(FocusPicker.items(today: [a, b], upcoming: [later], query: "zzz").isEmpty)
    }

    @Test func lengthIsTheEstimateElseThePreset() {
        let classic = FocusPreset.with(id: "classic")
        #expect(FocusPicker.minutes(for: .task(task("a", estimate: 50)), preset: classic) == 50)
        #expect(FocusPicker.minutes(for: .task(task("a")), preset: classic) == classic.focus)
        #expect(FocusPicker.minutes(for: .noTask, preset: classic) == classic.focus)
    }

    @Test func startingPicksTheTaskOrRetargets() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "FocusPickerTests-\(UUID().uuidString)")!)
        let timer = FocusTimer()
        let a = task("Write report", estimate: 40)
        FocusPicker.start(.task(a), timer: timer, settings: settings)
        #expect(timer.taskID == a.id)
        #expect(timer.duration == 40 * 60)
        let b = task("Email")
        FocusPicker.start(.task(b), timer: timer, settings: settings)
        #expect(timer.taskID == b.id)
        #expect(timer.duration == 40 * 60) // same session, now on b
        FocusPicker.start(.noTask, timer: timer, settings: settings)
        #expect(timer.taskID == b.id) // "just focus" never interrupts a running session
        timer.stop()
    }
}

@Suite struct WorkspaceLayoutTests {
    @Test func tasksWidthStartsAtTheDefaultAndIsClamped() {
        let state = WorkspaceState()
        #expect(state.tasksWidth(available: 800) == 800 - WorkspaceState.defaultNotesWidth)
        // A narrow panel still leaves Tasks its minimum.
        #expect(state.tasksWidth(available: 400) == WorkspaceState.minTasksWidth)
        state.setTasksWidth(100, available: 800)
        #expect(state.tasksWidth(available: 800) == WorkspaceState.minTasksWidth)
        state.setTasksWidth(790, available: 800)
        #expect(state.tasksWidth(available: 800) == 800 - WorkspaceState.minNotesWidth)
        state.setTasksWidth(480, available: 800)
        #expect(state.tasksWidth(available: 800) == 480)
        // A wider panel keeps the proportion.
        #expect(state.tasksWidth(available: 1000) == 600)
        state.resetColumns()
        #expect(state.tasksWidth(available: 800) == 800 - WorkspaceState.defaultNotesWidth)
    }

    @Test func widthSurvivesRelaunchOnlyWithDefaults() {
        let defaults = UserDefaults(suiteName: "WorkspaceLayoutTests-\(UUID().uuidString)")!
        WorkspaceState(defaults: defaults).setTasksWidth(500, available: 800)
        #expect(WorkspaceState(defaults: defaults).tasksWidth(available: 800) == 500)
        #expect(WorkspaceState().tasksWidth(available: 800) == 800 - WorkspaceState.defaultNotesWidth)
    }

    @Test func overlaysExcludeEachOtherAndEscClosesThem() {
        let state = WorkspaceState()
        state.openComposer()
        state.openFocusPicker()
        #expect(!state.isComposerOpen)
        #expect(state.isFocusPickerOpen)
        state.moveFocusSelection(by: 5, count: 3)
        #expect(state.focusSelection == 2)
        state.moveFocusSelection(by: -9, count: 3)
        #expect(state.focusSelection == 0)
        #expect(state.dismissOverlayIfOpen())
        #expect(!state.isFocusPickerOpen)
        #expect(!state.dismissOverlayIfOpen())
        state.composerKeys.field = .notes
        state.openComposer()
        #expect(state.composerKeys.field == .title)
    }

    @Test func dayTimelineCoversTheWholeDay() {
        #expect(DayTimeline.hours == 0..<24)
    }
}

@Suite struct GlobalShortcutActionTests {
    private func makeNotch() -> NotchInteraction {
        NotchInteraction(
            settings: AppSettings(defaults: UserDefaults(suiteName: "GlobalShortcutActionTests-\(UUID().uuidString)")!),
            focus: FocusTimer(), agenda: AgendaModel(), geometry: .placeholder, clock: ManualClock()
        )
    }

    @Test func toggleOpensWithoutTheComposerAndCloses() {
        let notch = makeNotch()
        notch.toggleFromKeyboard()
        #expect(notch.state == .open)
        #expect(notch.captureRequest == 0)
        notch.toggleFromKeyboard()
        #expect(notch.state == .closed)
    }

    @Test func newTaskOpensTheComposerAndASecondPressCloses() {
        let notch = makeNotch()
        notch.newTaskFromKeyboard(composerOpen: false)
        #expect(notch.state == .open)
        #expect(notch.captureRequest == 1)
        notch.newTaskFromKeyboard(composerOpen: false)
        #expect(notch.state == .open)
        #expect(notch.captureRequest == 2)
        notch.newTaskFromKeyboard(composerOpen: true)
        #expect(notch.state == .closed)
    }

    @Test func pinOpensPinnedThenFlips() {
        let notch = makeNotch()
        notch.togglePinFromKeyboard()
        #expect(notch.state == .open)
        #expect(notch.isPinned)
        notch.togglePinFromKeyboard()
        #expect(notch.state == .open)
        #expect(!notch.isPinned)
    }

    @Test func focusPickerOpensTheFocusTab() {
        let notch = makeNotch()
        notch.show(.insights)
        notch.openForFocusPicker()
        #expect(notch.state == .open)
        #expect(notch.area == .focus)
    }
}
