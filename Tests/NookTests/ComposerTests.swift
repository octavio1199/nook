import Foundation
import Testing
@testable import Nook

@Suite struct ComposerTests {
    // Wednesday 2025-01-15 10:00 in Sao Paulo.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        c.firstWeekday = 2
        return c
    }()
    static let now = calendar.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 10, minute: 0))!

    private func date(_ d: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        Self.calendar.date(from: DateComponents(year: 2025, month: 1, day: d, hour: h, minute: m))!
    }

    private func make(_ draft: ComposerDraft) -> [TaskItem] {
        draft.makeTasks(now: Self.now, calendar: Self.calendar)
    }

    private let classic = FocusPreset.with(id: "classic")

    // MARK: Draft -> task

    @Test func titleOnlyMatchesTheParser() {
        var draft = ComposerDraft()
        draft.title = "call Ana tomorrow 3pm !high #work ~25m"
        let tasks = make(draft)
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "call Ana")
        #expect(tasks[0].due == date(16, 15))
        #expect(tasks[0].hasTime)
        #expect(tasks[0].priority == .high)
        #expect(tasks[0].tags == ["work"])
        #expect(tasks[0].estimateMinutes == 25)
        #expect(tasks[0].notes == nil)
        #expect(!draft.hasExtras)
    }

    @Test func chipsOverrideTheTitle() {
        var draft = ComposerDraft()
        draft.title = "write spec !low ~25m"
        draft.priority = .high
        draft.estimateMinutes = 90
        draft.due = .tomorrow
        draft.notes = "  - outline\n- review  \n"
        draft.tagsText = "Work, #docs  work"
        let t = make(draft)[0]
        #expect(t.title == "write spec")
        #expect(t.priority == .high)
        #expect(t.estimateMinutes == 90)
        #expect(t.due == date(16))
        #expect(!t.hasTime)
        #expect(t.notes == "- outline\n- review")
        #expect(t.tags == ["work", "docs"])
        #expect(draft.hasExtras)
    }

    @Test func dueOverrideKeepsTimeFromTitle() {
        var draft = ComposerDraft()
        draft.title = "call Ana today 3pm"
        draft.due = .tomorrow
        #expect(make(draft)[0].due == date(16, 15))
        draft.due = .date(date(20, 0))
        #expect(make(draft)[0].due == date(20, 15))
        draft.due = .none
        let none = make(draft)[0]
        #expect(none.due == nil)
        #expect(!none.hasTime)
    }

    @Test func dueChipsWithoutTime() {
        var draft = ComposerDraft()
        draft.title = "pay rent"
        draft.due = .today
        #expect(make(draft)[0].due == date(15))
        draft.due = .date(date(22, 13, 45))
        #expect(make(draft)[0].due == date(22))
    }

    @Test func tagsMergeWithoutDuplicates() {
        var draft = ComposerDraft()
        draft.title = "x #home"
        draft.tagsText = "home, errands"
        #expect(make(draft)[0].tags == ["home", "errands"])
        #expect(ComposerDraft.tags(from: " , ;") == [])
    }

    @Test func brainDumpIgnoresNotesAndChips() {
        var draft = ComposerDraft()
        draft.title = "buy milk ~10m; call Ana tomorrow"
        draft.notes = "not for anyone"
        draft.priority = .high
        draft.estimateMinutes = 90
        draft.startFocus = true
        #expect(draft.isBrainDump(now: Self.now, calendar: Self.calendar))
        let tasks = make(draft)
        #expect(tasks.count == 2)
        #expect(tasks.allSatisfy { $0.notes == nil && $0.priority == .none })
        #expect(tasks.map(\.estimateMinutes) == [10, nil])
    }

    @Test func emptyTitleMakesNothing() {
        var draft = ComposerDraft()
        #expect(make(draft).isEmpty)
        draft.notes = "just notes"
        #expect(make(draft).isEmpty)
        #expect(!draft.isEmpty)
        #expect(ComposerDraft().isEmpty)
    }

    @Test func previewOfBlankDraftShowsOverrides() {
        var draft = ComposerDraft()
        draft.estimateMinutes = 25
        let preview = draft.applying(to: TaskItem(title: ""), now: Self.now, calendar: Self.calendar)
        #expect(preview.estimateMinutes == 25)
    }

    // MARK: Focus duration

    @Test func focusDefaultsToEstimateThenPreset() {
        #expect(ComposerDraft.focusMinutes(picked: nil, estimate: 40, preset: classic) == 40)
        #expect(ComposerDraft.focusMinutes(picked: nil, estimate: nil, preset: classic) == 25)
        #expect(ComposerDraft.focusMinutes(picked: 15, estimate: 40, preset: classic) == 15)
        #expect(ComposerDraft.focusMinutes(picked: nil, estimate: nil, preset: .with(id: "deep")) == 50)
    }

    @Test func focusMinutesAreClamped() {
        #expect(ComposerDraft.focusMinutes(picked: nil, estimate: 400, preset: classic) == 180)
        #expect(ComposerDraft.focusMinutes(picked: 1, estimate: nil, preset: classic) == 5)
    }

    @Test func draftFocusUsesEffectiveEstimate() {
        var draft = ComposerDraft()
        draft.title = "write ~50m"
        let estimate = make(draft)[0].estimateMinutes
        #expect(draft.focusMinutes(effectiveEstimate: estimate, preset: classic) == 50)
        draft.focusMinutes = 25
        #expect(draft.focusMinutes(effectiveEstimate: estimate, preset: classic) == 25)
    }

    @Test func focusPresetKeepsBreaks() {
        let preset = ComposerDraft.focusPreset(base: .with(id: "deep"), minutes: 35)
        #expect(preset.focus == 35)
        #expect(preset.id == "deep")
        #expect(preset.shortBreak == 10)
        #expect(preset.sessionsBeforeLongBreak == 3)
    }

    @Test func startingFocusRunsAPomodoroOnTheTask() {
        let timer = FocusTimer()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "composer-\(UUID().uuidString)")!)
        settings.focusPresetID = "deep"
        let task = TaskItem(title: "Write spec")
        TaskActions.startComposerFocus(task: task, minutes: 35, timer: timer, settings: settings)
        #expect(timer.phase == .focus)
        #expect(timer.taskID == task.id)
        #expect(timer.label == "Write spec")
        #expect(timer.duration == 35 * 60)
        #expect(timer.preset.shortBreak == 10)
        timer.stop()
    }

    @Test func startingFocusWhileRunningRetargetsInsteadOfRestarting() {
        let timer = FocusTimer()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "composer-\(UUID().uuidString)")!)
        timer.startPomodoro(.with(id: "classic"), label: "Old")
        let task = TaskItem(title: "New")
        TaskActions.startComposerFocus(task: task, minutes: 50, timer: timer, settings: settings)
        #expect(timer.duration == 25 * 60)
        #expect(timer.taskID == task.id)
        timer.stop()
    }

    // MARK: Estimates in the UI

    @Test func estimateFormatting() {
        #expect(TaskTime.estimateText(25) == "25m")
        #expect(TaskTime.estimateText(60) == "1h")
        #expect(TaskTime.estimateText(90) == "1h30")
        #expect(TaskTime.estimateText(125) == "2h05")
        #expect(TaskTime.progressText(tracked: 20 * 60, estimate: 50) == "20/50m")
        #expect(TaskTime.progressText(tracked: 65 * 60, estimate: 120) == "1h05/2h")
        #expect(TaskTime.ofText(tracked: 20 * 60, estimate: 50) == "20 of 50m")
    }

    @Test func overEstimateAndFraction() {
        #expect(TaskTime.fraction(tracked: 25 * 60, estimate: 50) == 0.5)
        #expect(TaskTime.fraction(tracked: 90 * 60, estimate: 50) == 1)
        #expect(!TaskTime.isOver(tracked: 50 * 60, estimate: 50))
        #expect(TaskTime.isOver(tracked: 50 * 60 + 1, estimate: 50))
        #expect(!TaskTime.isOver(tracked: 100, estimate: 0))
    }

    @Test func trackedTimeIncludesTheRunningSession() {
        let planner = PlannerStore(url: nil)
        let timer = FocusTimer()
        let task = TaskItem(title: "A")
        planner.add(task)
        planner.log(FocusSession(start: .now, duration: 600, label: nil, taskID: task.id))
        #expect(TaskActions.trackedTime(for: task.id, planner: planner, focus: timer) == 600)
        timer.startPomodoro(.with(id: "classic"), label: task.title, taskID: task.id)
        timer.tick(at: timer.now.addingTimeInterval(120))
        #expect(TaskActions.trackedTime(for: task.id, planner: planner, focus: timer) >= 720 - 1)
        timer.stop()
    }

    // MARK: Workspace state

    @Test func draftSurvivesClosingAndClearsOnFinish() {
        let state = WorkspaceState()
        state.composer.title = "call Ana"
        state.composer.notes = "bring the contract"
        state.openComposer()
        #expect(state.isComposerOpen)
        #expect(state.dismissComposerIfOpen())
        #expect(!state.isComposerOpen)
        #expect(!state.dismissComposerIfOpen())
        #expect(state.composer.title == "call Ana")
        #expect(state.captureDraft == "call Ana")
        state.openComposer()
        state.finishComposer()
        #expect(!state.isComposerOpen)
        #expect(state.composer.isEmpty)
    }
}
