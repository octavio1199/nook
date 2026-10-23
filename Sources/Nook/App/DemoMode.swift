import AppKit
import SwiftUI

/// `--demo [open|peek|live|insights|checkin|checkin-open|checkin-wings]` runs Nook on an in-memory store with sample data, for screenshots.
enum DemoMode {
    static var scene: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--demo") else { return nil }
        return args.indices.contains(index + 1) ? args[index + 1] : "open"
    }

    static func makeStore() -> PlannerStore {
        let store = PlannerStore(url: nil)
        let now = Date()
        let cal = Calendar.current
        let today3pm = cal.date(bySettingHour: 15, minute: 0, second: 0, of: now)
        store.add(CaptureParser.parse("Review Pullo PR #work !high ~30m; call Ana tomorrow 3pm ~15m; buy coffee #home; write release notes !med #work ~1h30"))
        if let review = store.tasks.first(where: { $0.title == "Review Pullo PR" }) {
            store.log(FocusSession(start: now.addingTimeInterval(-5 * 3600), duration: 40 * 60, label: review.title, taskID: review.id))
        }
        store.add(TaskItem(title: "Design review", due: today3pm, hasTime: true, priority: .medium, tags: ["design"]))
        var done = TaskItem(title: "Ship v0.1", done: true)
        done.completedAt = now
        store.add(done)
        store.log(FocusSession(start: now.addingTimeInterval(-3 * 3600), duration: 47 * 60, label: done.title, taskID: done.id))
        var launch = TaskItem(title: "Draft launch post", due: cal.startOfDay(for: now), priority: .high, tags: ["work"])
        launch.estimateMinutes = 50
        launch.subtasks = [
            Subtask(title: "Outline the three headline features", done: true),
            Subtask(title: "Write the intro paragraph", done: true),
            Subtask(title: "Screenshots of the Day tab"),
            Subtask(title: "Proofread and schedule"),
        ]
        launch.notes = "**Angle:** a planner that lives in the notch.\n- link the GitHub repo\n- mention it's free and local-only"
        store.add(launch)
        store.log(FocusSession(start: now.addingTimeInterval(-26 * 3600), duration: 25 * 60, label: launch.title, taskID: launch.id))
        store.log(FocusSession(start: now.addingTimeInterval(-2 * 3600), duration: 5 * 60, label: launch.title, taskID: launch.id))
        store.setNote("# Ideas for Nook\n- [x] **Markdown** notepad\n- [ ] drag files onto the notch\n- [ ] Reminders sync\n> ship `v0.2` this week\nSee https://github.com/octavio1199/nook", for: now)
        for day in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: -day, to: now) else { continue }
            store.log(FocusSession(start: date, duration: TimeInterval((25 * (1 + day % 3)) * 60)))
        }
        return store
    }

    static func run(_ scene: String, app: AppDependencies, panel: NotchPanelController) {
        // `--demo-screen external|builtin`: the first display without / with a notch.
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--demo-screen"), args.indices.contains(index + 1),
           let screen = NSScreen.screens.first(where: { ($0.safeAreaInsets.top > 0) == (args[index + 1] == "builtin") }) {
            panel.place(on: screen)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            switch scene {
            case "peek":
                app.notch.enqueue(NotchAlert(kind: .focusFinished, symbol: "checkmark.circle.fill", tint: .focus, headline: "Focus done", detail: "Take a break · 5 min"))
            case "break":
                app.focus.startPomodoro(.with(id: "classic"))
                app.focus.skip()
            case "live":
                app.focus.startPomodoro(.with(id: "classic"), label: "Write release notes")
            case "checkin", "checkin-open", "checkin-wings":
                // Run a 25-min focus on the demo task past its end, as if the time just ran out.
                guard let task = app.planner.tasks.first(where: { $0.title == "Draft launch post" }) else { break }
                app.focus.startPomodoro(.with(id: "classic"), label: task.title, taskID: task.id)
                if scene == "checkin-wings" { app.focus.onAlert = nil }
                app.focus.tick(at: Date().addingTimeInterval(25 * 60 + 1))
                if scene == "checkin-open" {
                    app.notch.open()
                    app.notch.isPinned = true
                }
            case "insights":
                app.notch.open()
                app.notch.isPinned = true
                app.notch.show(.insights)
            case "composer":
                app.notch.open()
                app.notch.isPinned = true
                var draft = ComposerDraft()
                draft.title = "Write launch checklist tomorrow 9am !high #work ~50m"
                draft.notes = "- [ ] copy review\n- [ ] screenshots\nSee **Draft launch post**"
                draft.startFocus = true
                app.workspace.composer = draft
                app.workspace.openComposer()
            case "composer-keys":
                app.notch.open()
                app.notch.isPinned = true
                var draft = ComposerDraft()
                draft.title = "Prepare board deck"
                draft.due = .tomorrow
                draft.priority = .high
                draft.estimateMinutes = 90
                draft.tagsText = "work"
                app.workspace.composer = draft
                app.workspace.openComposer()
                // After the card's appear (which puts the cursor in the title), as if Tab was pressed.
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    app.workspace.composerKeys.field = .estimate
                }
            case "focus-picker":
                app.notch.open()
                app.notch.isPinned = true
                app.workspace.openFocusPicker()
                app.workspace.focusSelection = 2
            case "detail":
                app.notch.open()
                app.notch.isPinned = true
                app.workspace.detailTaskID = app.planner.tasks.first { $0.title == "Draft launch post" }?.id
            case "columns":
                app.notch.open()
                app.notch.isPinned = true
                app.workspace.setTasksWidth(560, available: 760)
            case "settings":
                renderSettings(app: app)
            case "composer-dump":
                app.notch.open()
                app.notch.isPinned = true
                var draft = ComposerDraft()
                draft.title = "buy coffee ~10m; call Ana tomorrow 3pm; write release notes ~1h"
                app.workspace.composer = draft
                app.workspace.openComposer()
            case "focus-idle":
                app.notch.open()
                app.notch.isPinned = true
                app.notch.show(.focus)
            default:
                if let launch = app.planner.tasks.first(where: { $0.title == "Draft launch post" }) {
                    app.focus.startPomodoro(.with(id: "classic"), label: launch.title, taskID: launch.id)
                } else {
                    app.focus.startPomodoro(.with(id: "classic"), label: "Write release notes")
                }
                app.notch.open()
                app.notch.isPinned = true
                // "focus" stays on the Focus tab the timer switched to; the other scenes go back to Workspace.
                try? await Task.sleep(for: .milliseconds(200))
                if scene != "focus" { app.notch.show(DayDemo.mode == nil ? .workspace : .day) }
            }
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) {
                try? await Task.sleep(for: .seconds(2))
                panel.snapshot(to: URL(fileURLWithPath: args[index + 1]))
                NSApp.terminate(nil)
            }
        }
    }

    /// The Settings window isn't part of the panel: renders every section to `<snapshot>.<section>.png`.
    private static func renderSettings(app: AppDependencies) {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) else { return }
        let size = SettingsView.minSize
        for section in SettingsSection.allCases {
            let view = NSHostingView(rootView: app.inject(into: SettingsView(fixedSection: section)).frame(width: size.width, height: size.height))
            view.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            window.appearance = NSAppearance(named: .darkAqua)
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[index + 1] + ".\(section.rawValue).png"))
        }
    }
}
