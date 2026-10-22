import AppKit
import Observation
import SwiftUI

/// The time block the closed notch shows while no focus is running.
struct CurrentBlock: Equatable {
    var id: UUID
    var title: String
    var end: Date
    var priority: TaskItem.Priority
}

/// Watches the planned blocks: asks 5 minutes before one begins and when it begins. It never starts
/// anything by itself; "Start" / "Snooze" / "Skip" come from the peek (or the Day tab).
@Observable
final class BlockWatcher {
    private(set) var now = Date()
    /// Off in demo mode so screenshots stay deterministic.
    @ObservationIgnored var isEnabled = true
    @ObservationIgnored var onAlert: ((NotchAlert) -> Void)?
    /// Called when the user acted on a block, so its peek can go away.
    @ObservationIgnored var onResolved: ((UUID) -> Void)?
    @ObservationIgnored var leadMinutes = 5
    @ObservationIgnored var snoozeMinutes = 10

    @ObservationIgnored private let planner: PlannerStore
    @ObservationIgnored private let focus: FocusTimer
    @ObservationIgnored private let agenda: AgendaModel
    @ObservationIgnored private let settings: AppSettings
    /// task id -> block start already announced, so each block (and each snoozed position) alerts once.
    @ObservationIgnored private var soonAlerted: [UUID: Date] = [:]
    @ObservationIgnored private var startAlerted: [UUID: Date] = [:]
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    init(planner: PlannerStore, focus: FocusTimer, agenda: AgendaModel, settings: AppSettings, autoStart: Bool = true) {
        self.planner = planner
        self.focus = focus
        self.agenda = agenda
        self.settings = settings
        guard autoStart else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    var dayPlanner: DayPlanner {
        DayPlanner(workStart: settings.workdayStart, workEnd: settings.workdayEnd)
    }

    // MARK: - Current block

    /// The open block that covers `now`, for the closed-notch wings.
    var currentBlock: CurrentBlock? {
        for task in planner.scheduledTasks(on: now) {
            guard let start = task.scheduledStart, let end = DayPlanner.end(of: task) else { continue }
            if start <= now, end > now {
                return CurrentBlock(id: task.id, title: task.title, end: end, priority: task.priority)
            }
        }
        return nil
    }

    // MARK: - Ticking

    func check(now date: Date = Date()) {
        now = date
        guard isEnabled else { return }
        let cutoff = date.addingTimeInterval(-86_400)
        soonAlerted = soonAlerted.filter { $0.value > cutoff }
        startAlerted = startAlerted.filter { $0.value > cutoff }

        for task in planner.scheduledTasks(on: date) {
            guard let start = task.scheduledStart, let end = DayPlanner.end(of: task), end > date else { continue }
            // A focus already running on this task is the answer to the question.
            if focus.isActive, focus.taskID == task.id { continue }
            if start <= date {
                guard startAlerted[task.id] != start else { continue }
                startAlerted[task.id] = start
                soonAlerted[task.id] = start
                onAlert?(startAlert(for: task, end: end))
            } else if start.timeIntervalSince(date) <= TimeInterval(leadMinutes * 60) {
                guard soonAlerted[task.id] != start else { continue }
                soonAlerted[task.id] = start
                onAlert?(soonAlert(for: task, start: start))
            }
        }
    }

    private static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    private func soonAlert(for task: TaskItem, start: Date) -> NotchAlert {
        let length = TaskTime.text(TimeInterval(DayPlanner.minutes(for: task) * 60))
        return NotchAlert(
            kind: .blockSoon, symbol: "calendar.badge.clock", tint: .accent,
            headline: "Next: \(task.title)", detail: "\(Self.time(start)) · \(length)", taskID: task.id
        )
    }

    private func startAlert(for task: TaskItem, end: Date) -> NotchAlert {
        NotchAlert(
            kind: .blockStart, symbol: "calendar.badge.clock", tint: .accent,
            headline: task.title, detail: "Now · until \(Self.time(end))", sticky: true, taskID: task.id
        )
    }

    // MARK: - Actions

    /// Starts a focus as long as the block, tied to the task so time tracking and the check-in just work.
    func startFocus(_ id: UUID) {
        guard let task = planner.task(id), task.isOpen else { return }
        if focus.isActive { focus.stop() }
        var preset = FocusPreset.with(id: settings.focusPresetID)
        preset.focus = DayPlanner.minutes(for: task)
        focus.startPomodoro(preset, label: task.title, taskID: task.id)
        onResolved?(id)
    }

    /// Moves the block 10 minutes later (counted from now when it has already begun).
    func snooze(_ id: UUID, now date: Date = Date()) {
        guard let start = planner.task(id)?.scheduledStart else { return }
        let base = Self.floorToMinute(max(start, date))
        planner.schedule(id, at: base.addingTimeInterval(TimeInterval(snoozeMinutes * 60)))
        onResolved?(id)
    }

    /// Moves the block to the next free slot after it; with no room in the next days it goes back to the list.
    func skip(_ id: UUID, now date: Date = Date()) {
        guard let task = planner.task(id), let end = DayPlanner.end(of: task) else { return }
        let slot = dayPlanner.nextFreeSlot(
            after: max(end, date), minutes: DayPlanner.minutes(for: task),
            events: agenda.events, tasks: planner.tasks, excluding: [id]
        )
        planner.schedule(id, at: slot)
        onResolved?(id)
    }

    /// "Push rest": shifts the blocks that begin at or after `from` by the overrun, rounded up to 5 min.
    func pushRest(from: Date, overrun: TimeInterval) {
        let minutes = DayPlanner.roundedOverrun(overrun)
        let moves = dayPlanner.pushRest(on: from, tasks: planner.tasks, from: from, by: minutes)
        planner.applySchedule(moves.mapValues { Optional($0) }, action: "Push Rest of Day")
    }

    /// Whether the check-in for `task` should offer "Push rest": its block is over and later blocks exist.
    func overrun(for task: TaskItem, now date: Date = Date()) -> (end: Date, overrun: TimeInterval)? {
        guard let end = DayPlanner.end(of: task), end < date else { return nil }
        let later = planner.scheduledTasks(on: end).contains { other in
            other.id != task.id && (other.scheduledStart ?? .distantPast) >= end
        }
        return later ? (end, date.timeIntervalSince(end)) : nil
    }

    private static func floorToMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }
}
