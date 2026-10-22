import Foundation

final class TaskDueWatcher {
    var onAlert: ((NotchAlert) -> Void)?

    /// A longer silence than this between checks means the Mac slept (or the app was frozen).
    static let staleGap: TimeInterval = 120

    private let planner: PlannerStore
    private(set) var lastCheck: Date
    private var ticker: Timer?

    init(planner: PlannerStore, startedAt: Date = Date()) {
        self.planner = planner
        lastCheck = startedAt
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func check(now: Date = Date()) {
        let previous = lastCheck
        lastCheck = now
        let due = planner.tasks.filter { task in
            guard task.isOpen, task.hasTime, let when = task.due else { return false }
            return when > previous && when <= now
        }
        guard !due.isEmpty else { return }

        // After a wake (or any long gap) don't fire one peek per stale task.
        if now.timeIntervalSince(previous) > Self.staleGap {
            if due.count == 1, let task = due.first {
                onAlert?(NotchAlert(kind: .taskDue, symbol: "bell.fill", tint: .accent, headline: task.title, detail: "Became due while you were away"))
            } else {
                onAlert?(NotchAlert(kind: .taskDue, symbol: "bell.fill", tint: .accent, headline: "\(due.count) tasks became due", detail: nil))
            }
            return
        }
        for task in due {
            onAlert?(NotchAlert(kind: .taskDue, symbol: "bell.fill", tint: .accent, headline: task.title, detail: "Due now"))
        }
    }
}
