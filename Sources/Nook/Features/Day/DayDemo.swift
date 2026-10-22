import SwiftUI

/// Sample data for screenshots: `--demo <scene> --day-demo <mode>` (in-memory store only).
/// Modes: `day` (blocks + events), `plan` (nothing scheduled, shows the plan preview),
/// `wings` (closed notch during a block), `soon` / `start` (block peeks), `checkin` (late check-in).
enum DayDemo {
    static var mode: String? {
        guard DemoMode.scene != nil else { return nil }
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--day-demo"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    static var autoPlan: Bool { mode == "plan" }
    /// Screenshots of the day scene start at the top of the workday whatever the real time is
    /// (the plan scene scrolls to now, where its preview lands).
    static var showsMorning: Bool { mode == "day" }
    /// The night scene opens late in the evening to show blocks outside working hours.
    static var scrollHour: Int? { mode == "night" ? 18 : nil }

    static func configureIfRequested(app: AppDependencies) {
        guard let mode else { return }
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        func at(_ hour: Int, _ minute: Int = 0) -> Date { today.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60)) }
        func schedule(_ title: String, _ start: Date?, minutes: Int?) {
            guard var task = app.planner.tasks.first(where: { $0.title.lowercased().hasPrefix(title.lowercased()) }) else { return }
            task.scheduledStart = start
            if let minutes { task.estimateMinutes = minutes }
            app.planner.update(task)
        }
        func event(_ title: String, _ start: Date, _ end: Date, _ color: Color) -> AgendaEvent {
            AgendaEvent(id: title, title: title, start: start, end: end, isAllDay: false, color: color)
        }
        let quarter = TimeInterval(15 * 60)
        let floorNow = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / quarter).rounded(.down) * quarter)

        switch mode {
        case "day", "plan":
            app.agenda.useDemoEvents([
                event("Standup", at(10), at(10, 30), .blue),
                event("Product sync", at(11, 30), at(12, 15), .green),
                event("1:1 Ana", at(15), at(15, 30), .purple),
            ])
            schedule("Write release notes", nil, minutes: 45)
            schedule("Review Pullo PR", nil, minutes: 30)
            schedule("buy coffee", nil, minutes: 15)
            schedule("Draft launch post", nil, minutes: 90)
            if mode == "day" {
                schedule("Draft launch post", at(9), minutes: 60)
                schedule("Review Pullo PR", at(11), minutes: 45)
                schedule("Design review", at(14), minutes: 45)
            }
            app.notch.show(.day)
        case "night":
            schedule("Draft launch post", at(21, 30), minutes: 60)
            schedule("Review Pullo PR", at(23), minutes: 45)
            app.notch.show(.day)
        case "wings":
            schedule("Draft launch post", floorNow.addingTimeInterval(-quarter), minutes: 60)
            stopFocusSoon(app)
        case "soon":
            schedule("Draft launch post", now.addingTimeInterval(4 * 60), minutes: 50)
            stopFocusSoon(app, check: true)
        case "start":
            schedule("Draft launch post", now.addingTimeInterval(-60), minutes: 50)
            stopFocusSoon(app, check: true)
        case "checkin":
            schedule("Draft launch post", now.addingTimeInterval(-50 * 60), minutes: 25)
            schedule("Write release notes", now.addingTimeInterval(30 * 60), minutes: 30)
            schedule("Design review", now.addingTimeInterval(90 * 60), minutes: 45)
        default:
            break
        }
    }

    /// The base demo scene starts a focus; end it so the closed notch shows the block instead.
    private static func stopFocusSoon(_ app: AppDependencies, check: Bool = false) {
        Task {
            try? await Task.sleep(for: .milliseconds(1100))
            app.focus.stop()
            app.notch.dismissPeekNow()
            if check {
                app.blocks.isEnabled = true
                app.blocks.check()
            }
        }
    }
}
