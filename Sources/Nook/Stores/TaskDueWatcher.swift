import Foundation

/// Fires a peek when a task with a time becomes due.
final class TaskDueWatcher {
    var onAlert: ((NotchAlert) -> Void)?

    private let planner: PlannerStore
    private var lastCheck = Date()
    private var ticker: Timer?

    init(planner: PlannerStore) {
        self.planner = planner
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func check(now: Date = Date()) {
        defer { lastCheck = now }
        for task in planner.tasks where !task.done && task.hasTime {
            guard let due = task.due, due > lastCheck, due <= now else { continue }
            onAlert?(NotchAlert(kind: .taskDue, symbol: "bell.fill", tint: .accent, headline: task.title, detail: "Due now"))
        }
    }
}
