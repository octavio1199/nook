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
    private(set) var duration: TimeInterval = 0
    private(set) var completedInCycle = 0
    private(set) var now = Date()
    private(set) var preset = FocusPreset.all[0]

    @ObservationIgnored var onAlert: ((NotchAlert) -> Void)?
    @ObservationIgnored var onSessionLogged: ((FocusSession) -> Void)?
    @ObservationIgnored var autoStartBreaks: () -> Bool = { true }

    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var resumedAt: Date?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var sleepObserver: Any?

    init() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
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

    func startPomodoro(_ preset: FocusPreset, label: String? = nil) {
        self.preset = preset
        completedInCycle = 0
        begin(.focus, minutes: preset.focus, label: label)
    }

    /// Continues the current pomodoro cycle (keeps the long-break count).
    func startNextFocus(label: String? = nil) {
        begin(.focus, minutes: preset.focus, label: label)
    }

    /// Starts the break that follows the last finished focus session.
    func startBreak() {
        let long = completedInCycle > 0 && completedInCycle % preset.sessionsBeforeLongBreak == 0
        begin(long ? .longBreak : .shortBreak, minutes: long ? preset.longBreak : preset.shortBreak, label: nil)
    }

    func startCountdown(minutes: Int, label: String? = nil) {
        begin(.countdown, minutes: minutes, label: label)
    }

    func startStopwatch(label: String? = nil) {
        begin(.stopwatch, minutes: 0, label: label)
    }

    private func begin(_ phase: Phase, minutes: Int, label: String?) {
        self.phase = phase
        self.label = label
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
        stopTicking()
    }

    func resume() {
        guard isActive, isPaused else { return }
        now = Date()
        resumedAt = now
        isPaused = false
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
        finishPhase(announce: false)
    }

    private func reset() {
        stopTicking()
        phase = nil
        label = nil
        isPaused = false
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
        finishPhase(announce: true)
    }

    private func finishPhase(announce: Bool) {
        guard let phase else { return }
        logIfFocus()
        switch phase {
        case .focus:
            completedInCycle += 1
            let long = completedInCycle % preset.sessionsBeforeLongBreak == 0
            if announce {
                onAlert?(NotchAlert(
                    kind: .focusFinished, symbol: "checkmark.circle.fill", tint: .focus,
                    headline: "Focus done", detail: long ? "Take a long break · \(preset.longBreak) min" : "Take a break · \(preset.shortBreak) min"
                ))
            }
            if autoStartBreaks() {
                let label = label
                begin(long ? .longBreak : .shortBreak, minutes: long ? preset.longBreak : preset.shortBreak, label: label)
            } else {
                reset()
            }
        case .shortBreak, .longBreak:
            if announce {
                onAlert?(NotchAlert(kind: .breakFinished, symbol: "cup.and.saucer.fill", tint: .rest, headline: "Break over", detail: "Ready for the next round?"))
            }
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
        onSessionLogged?(FocusSession(start: startedAt, duration: elapsed, label: label))
    }
}
