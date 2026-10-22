import AppKit
import Observation
import SwiftUI

struct FocusPreset: Identifiable, Hashable {
    var id: String
    var name: String
    var focus: Int
    var shortBreak: Int
    var longBreak: Int
    var sessionsBeforeLongBreak: Int

    static let all = [
        FocusPreset(id: "classic", name: "Classic", focus: 25, shortBreak: 5, longBreak: 15, sessionsBeforeLongBreak: 4),
        FocusPreset(id: "deep", name: "Deep work", focus: 50, shortBreak: 10, longBreak: 20, sessionsBeforeLongBreak: 3),
        FocusPreset(id: "sprint", name: "Sprint", focus: 15, shortBreak: 3, longBreak: 10, sessionsBeforeLongBreak: 4),
    ]

    static func with(id: String) -> FocusPreset { all.first { $0.id == id } ?? all[0] }
}

@Observable
final class FocusTimer {
    enum Phase: Equatable {
        case focus, shortBreak, longBreak, countdown, stopwatch

        var isBreak: Bool { self == .shortBreak || self == .longBreak }
        var countsAsFocus: Bool { !isBreak }

        var title: String {
            switch self {
            case .focus: "Focus"
            case .shortBreak: "Break"
            case .longBreak: "Long break"
            case .countdown: "Timer"
            case .stopwatch: "Stopwatch"
            }
        }

        var tint: Color { isBreak ? .rest : .focus }
    }

    private(set) var phase: Phase?
    private(set) var isPaused = false
    private(set) var label: String?
    /// The task being focused on, if one was picked. `label` mirrors its title.
    private(set) var taskID: UUID?
    private(set) var duration: TimeInterval = 0
    private(set) var completedInCycle = 0
    private(set) var now = Date()
    private(set) var preset = FocusPreset.all[0]
    /// A focus on a task ended and is waiting for the user: +5 min, break then continue, or done.
    private(set) var awaitingDecision = false
    /// After the current break, offer to continue with the same task.
    private(set) var continuesTaskAfterBreak = false

    @ObservationIgnored var onAlert: ((NotchAlert) -> Void)?
    @ObservationIgnored var onSessionLogged: ((FocusSession) -> Void)?
    @ObservationIgnored var autoStartBreaks: () -> Bool = { true }
    /// Called with the task id when the user marks the focused task done from the check-in.
    @ObservationIgnored var onTaskFinished: ((UUID) -> Void)?

    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var resumedAt: Date?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var observers: [(center: NotificationCenter, token: Any)] = []
    /// True when the system (sleep / lock) paused the timer, not the user.
    @ObservationIgnored private var pausedBySystem = false
    @ObservationIgnored private var screenLocked = false

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observe(workspace, NSWorkspace.willSleepNotification) { $0.systemPause() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.systemPause() }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true; $0.systemPause() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.systemWake() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.systemWake() }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false; $0.systemWake() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor @Sendable (FocusTimer) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { handler(self) } }
        }
        observers.append((center, token))
    }

    /// Pauses because the Mac slept or locked; remembered so we can tell the user on return.
    func systemPause() {
        guard isRunning else { return }
        pause()
        pausedBySystem = true
    }

    /// On wake / unlock: if the system (not the user) paused the timer, say so, with a Resume pill.
    func systemWake() {
        guard pausedBySystem, isPaused, !screenLocked else { return }
        pausedBySystem = false
        onAlert?(NotchAlert(
            kind: .focusPaused, symbol: "pause.circle.fill", tint: phase?.tint ?? .focus,
            headline: "Focus paused while you were away", detail: label
        ))
    }

    var isActive: Bool { phase != nil }
    var isRunning: Bool { isActive && !isPaused }

    var elapsed: TimeInterval {
        accumulated + (resumedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    var remaining: TimeInterval {
        phase == .stopwatch ? elapsed : max(duration - elapsed, 0)
    }

    var progress: Double {
        guard phase != .stopwatch, duration > 0 else { return 0 }
        return min(elapsed / duration, 1)
    }

    var displayText: String { Self.format(remaining) }

    static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    // MARK: - Starting

    func startPomodoro(_ preset: FocusPreset, label: String? = nil, taskID: UUID? = nil) {
        self.preset = preset
        completedInCycle = 0
        begin(.focus, minutes: preset.focus, label: label, taskID: taskID)
    }

    /// Points the running (or next) session at a task, e.g. picked from the task list.
    func focus(on task: TaskItem?) {
        taskID = task?.id
        label = task?.title
    }

    /// Continues the current pomodoro cycle (keeps the long-break count).
    func startNextFocus(label: String? = nil) {
        begin(.focus, minutes: preset.focus, label: label ?? self.label, taskID: taskID)
    }

    // MARK: - Task check-in

    /// Keep going on the same task for a few more minutes (a new session, same task).
    func extend(minutes: Int = 5) {
        awaitingDecision = false
        continuesTaskAfterBreak = false
        begin(.focus, minutes: minutes, label: label, taskID: taskID)
    }

    /// Take the break now and come back to the same task afterwards.
    func breakThenContinue() {
        awaitingDecision = false
        startBreak()
        continuesTaskAfterBreak = taskID != nil
    }

    /// The task is done: mark it, forget it, and take the break (if breaks auto-start).
    func finishTask() {
        awaitingDecision = false
        continuesTaskAfterBreak = false
        if let taskID { onTaskFinished?(taskID) }
        taskID = nil
        label = nil
        if autoStartBreaks() { startBreak() }
    }

    func dismissCheckIn() {
        awaitingDecision = false
    }

    /// Starts the break that follows the last finished focus session.
    func startBreak() {
        let long = completedInCycle > 0 && completedInCycle % preset.sessionsBeforeLongBreak == 0
        begin(long ? .longBreak : .shortBreak, minutes: long ? preset.longBreak : preset.shortBreak, label: label, taskID: taskID)
    }

    func startCountdown(minutes: Int, label: String? = nil, taskID: UUID? = nil) {
        begin(.countdown, minutes: minutes, label: label, taskID: taskID)
    }

    func startStopwatch(label: String? = nil, taskID: UUID? = nil) {
        begin(.stopwatch, minutes: 0, label: label, taskID: taskID)
    }

    private func begin(_ phase: Phase, minutes: Int, label: String?, taskID: UUID? = nil) {
        if !phase.isBreak { awaitingDecision = false; continuesTaskAfterBreak = false }
        self.phase = phase
        self.label = label
        self.taskID = taskID
        duration = TimeInterval(minutes * 60)
        accumulated = 0
        now = Date()
        startedAt = now
        resumedAt = now
        isPaused = false
        startTicking()
    }

    // MARK: - Controls

    func pause() {
        guard isRunning else { return }
        now = Date()
        accumulated = elapsed
        resumedAt = nil
        isPaused = true
        pausedBySystem = false
        stopTicking()
    }

    func resume() {
        guard isActive, isPaused else { return }
        now = Date()
        resumedAt = now
        isPaused = false
        pausedBySystem = false
        startTicking()
    }

    func togglePause() {
        isPaused ? resume() : pause()
    }

    func addFiveMinutes() {
        guard isActive, phase != .stopwatch else { return }
        duration += 300
    }

    func stop() {
        logIfFocus()
        reset()
    }

    func skip() {
        guard isActive else { return }
        // Skipping a focus phase early doesn't earn a completed session in the cycle.
        let counted = phase != .focus || (duration > 0 && elapsed >= duration / 2)
        finishPhase(announce: false, countsTowardCycle: counted)
    }

    private func reset() {
        stopTicking()
        phase = nil
        isPaused = false
        pausedBySystem = false
        duration = 0
        accumulated = 0
        resumedAt = nil
        startedAt = nil
    }

    // MARK: - Ticking

    private func startTicking() {
        stopTicking()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    func tick(at date: Date = Date()) {
        now = date
        guard let phase, phase != .stopwatch, !isPaused, elapsed >= duration else { return }
        finishPhase(announce: true, countsTowardCycle: true)
    }

    private func finishPhase(announce: Bool, countsTowardCycle: Bool) {
        guard let phase else { return }
        logIfFocus()
        switch phase {
        case .focus:
            if countsTowardCycle { completedInCycle += 1 }
            let long = completedInCycle > 0 && completedInCycle % preset.sessionsBeforeLongBreak == 0
            if announce, let taskID {
                // Focusing on a task: don't assume it's finished; ask.
                reset()
                awaitingDecision = true
                onAlert?(NotchAlert(
                    kind: .taskCheckIn, symbol: "timer", tint: .focus,
                    headline: label ?? "Focus done", detail: "Time's up. Need more time?", sticky: true, taskID: taskID
                ))
                return
            }
            if announce {
                onAlert?(NotchAlert(
                    kind: .focusFinished, symbol: "checkmark.circle.fill", tint: .focus,
                    headline: "Focus done", detail: long ? "Take a long break · \(preset.longBreak) min" : "Take a break · \(preset.shortBreak) min"
                ))
            }
            if autoStartBreaks() {
                begin(long ? .longBreak : .shortBreak, minutes: long ? preset.longBreak : preset.shortBreak, label: label, taskID: taskID)
            } else {
                reset()
            }
        case .shortBreak, .longBreak:
            if announce {
                let resume = continuesTaskAfterBreak ? label : nil
                onAlert?(NotchAlert(
                    kind: .breakFinished, symbol: "cup.and.saucer.fill", tint: .rest, headline: "Break over",
                    detail: resume.map { "Continue “\($0)”?" } ?? "Ready for the next round?", taskID: resume == nil ? nil : taskID
                ))
            }
            continuesTaskAfterBreak = false
            reset()
        case .countdown:
            if announce {
                onAlert?(NotchAlert(kind: .focusFinished, symbol: "timer", tint: .accent, headline: "Time's up", detail: label))
            }
            reset()
        case .stopwatch:
            reset()
        }
    }

    private func logIfFocus() {
        guard let phase, phase.countsAsFocus, let startedAt else { return }
        onSessionLogged?(FocusSession(start: startedAt, duration: elapsed, label: label, taskID: taskID))
    }
}
