import Foundation
import Testing
@testable import Nook

@Suite struct FocusTimerTests {
    private func makeTimer() -> (FocusTimer, Recorder) {
        let timer = FocusTimer()
        let rec = Recorder()
        timer.onAlert = { rec.alerts.append($0) }
        timer.onSessionLogged = { rec.sessions.append($0) }
        return (timer, rec)
    }

    final class Recorder {
        var alerts: [NotchAlert] = []
        var sessions: [FocusSession] = []
    }

    @Test func countdownFinishesAndFiresOneAlert() {
        let (timer, rec) = makeTimer()
        timer.startCountdown(minutes: 1)
        let t0 = timer.now
        timer.tick(at: t0.addingTimeInterval(59))
        #expect(timer.isActive)
        #expect(rec.alerts.isEmpty)
        timer.tick(at: t0.addingTimeInterval(61))
        #expect(!timer.isActive)
        #expect(rec.alerts.count == 1)
        #expect(rec.alerts.first?.kind == .focusFinished)
        timer.tick(at: t0.addingTimeInterval(120))
        #expect(rec.alerts.count == 1)
    }

    @Test func focusFlowsIntoShortBreakWithAutoStart() {
        let (timer, rec) = makeTimer()
        timer.autoStartBreaks = { true }
        let preset = FocusPreset(id: "t", name: "T", focus: 1, shortBreak: 2, longBreak: 3, sessionsBeforeLongBreak: 4)
        timer.startPomodoro(preset)
        timer.tick(at: timer.now.addingTimeInterval(61))
        #expect(timer.phase == .shortBreak)
        #expect(timer.duration == 120)
        #expect(timer.completedInCycle == 1)
        #expect(rec.alerts.count == 1)
        #expect(rec.sessions.count == 1)
    }

    @Test func focusStopsWithoutAutoStartBreaks() {
        let (timer, rec) = makeTimer()
        timer.autoStartBreaks = { false }
        timer.startPomodoro(FocusPreset(id: "t", name: "T", focus: 1, shortBreak: 2, longBreak: 3, sessionsBeforeLongBreak: 4))
        timer.tick(at: timer.now.addingTimeInterval(61))
        #expect(!timer.isActive)
        #expect(rec.alerts.count == 1)
    }

    @Test func finalFocusOfCycleStartsLongBreak() {
        // The cycle counter only advances within one pomodoro run, so a
        // one-session cycle is the reachable way to exercise the long break.
        let (timer, _) = makeTimer()
        timer.startPomodoro(FocusPreset(id: "t", name: "T", focus: 1, shortBreak: 2, longBreak: 7, sessionsBeforeLongBreak: 1))
        timer.tick(at: timer.now.addingTimeInterval(61))
        #expect(timer.phase == .longBreak)
        #expect(timer.duration == 420)
    }

    @Test func breakEndFiresBreakFinishedAndResets() {
        let (timer, rec) = makeTimer()
        timer.startPomodoro(FocusPreset(id: "t", name: "T", focus: 1, shortBreak: 1, longBreak: 2, sessionsBeforeLongBreak: 4))
        timer.tick(at: timer.now.addingTimeInterval(61))
        timer.tick(at: timer.now.addingTimeInterval(61))
        #expect(!timer.isActive)
        #expect(rec.alerts.map(\.kind) == [.focusFinished, .breakFinished])
        #expect(rec.sessions.count == 1)
    }

    @Test func pauseFreezesElapsed() {
        let (timer, rec) = makeTimer()
        timer.startCountdown(minutes: 1)
        timer.pause()
        #expect(timer.isPaused)
        let frozen = timer.elapsed
        timer.tick(at: Date().addingTimeInterval(1000))
        #expect(timer.elapsed == frozen)
        #expect(timer.isActive)
        #expect(rec.alerts.isEmpty)
        timer.resume()
        timer.tick(at: timer.now.addingTimeInterval(30))
        #expect(timer.elapsed >= frozen + 29.9)
        timer.stop()
    }

    @Test func addFiveMinutesExtends() {
        let (timer, rec) = makeTimer()
        timer.startCountdown(minutes: 1)
        let t0 = timer.now
        timer.addFiveMinutes()
        #expect(timer.duration == 360)
        timer.tick(at: t0.addingTimeInterval(61))
        #expect(timer.isActive)
        timer.tick(at: t0.addingTimeInterval(361))
        #expect(!timer.isActive)
        #expect(rec.alerts.count == 1)
    }

    @Test func stopLogsElapsedFocusTime() {
        let (timer, rec) = makeTimer()
        timer.startCountdown(minutes: 5, label: "Write")
        timer.tick(at: timer.now.addingTimeInterval(120))
        timer.stop()
        #expect(!timer.isActive)
        #expect(rec.sessions.count == 1)
        #expect(rec.sessions.first?.duration == 120)
        #expect(rec.sessions.first?.label == "Write")
        #expect(rec.alerts.isEmpty)
    }

    @Test func stoppingABreakLogsNothing() {
        let (timer, rec) = makeTimer()
        timer.startPomodoro(FocusPreset(id: "t", name: "T", focus: 1, shortBreak: 5, longBreak: 9, sessionsBeforeLongBreak: 4))
        timer.tick(at: timer.now.addingTimeInterval(61))
        rec.sessions.removeAll()
        timer.stop()
        #expect(rec.sessions.isEmpty)
    }

    @Test func stopwatchCountsUpAndNeverFinishes() {
        let (timer, rec) = makeTimer()
        timer.startStopwatch()
        timer.tick(at: timer.now.addingTimeInterval(3600))
        #expect(timer.isActive)
        #expect(timer.remaining >= 3600)
        #expect(rec.alerts.isEmpty)
        timer.stop()
    }
}
