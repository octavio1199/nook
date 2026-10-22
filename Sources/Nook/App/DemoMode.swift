import AppKit

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
        store.add(CaptureParser.parse("Review Pullo PR #work !high; call Ana tomorrow 3pm; buy coffee #home; write release notes !med #work"))
        store.add(TaskItem(title: "Design review", due: today3pm, hasTime: true, priority: .medium, tags: ["design"]))
        var done = TaskItem(title: "Ship v0.1", done: true)
        done.completedAt = now
        store.add(done)
        store.log(FocusSession(start: now.addingTimeInterval(-3 * 3600), duration: 47 * 60, label: done.title, taskID: done.id))
        let launch = TaskItem(title: "Draft launch post", due: cal.startOfDay(for: now), priority: .high, tags: ["work"])
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
            default:
                app.focus.startPomodoro(.with(id: "classic"), label: "Write release notes")
                app.notch.open()
                app.notch.isPinned = true
            }
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) {
                try? await Task.sleep(for: .seconds(2))
                panel.snapshot(to: URL(fileURLWithPath: args[index + 1]))
                NSApp.terminate(nil)
            }
        }
    }
}
