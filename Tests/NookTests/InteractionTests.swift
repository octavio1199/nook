import Foundation
import Testing
@testable import Nook

/// A clock that only moves when the test advances it.
nonisolated final class ManualClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (a: Instant, b: Instant) -> Bool { a.offset < b.offset }
    }

    private struct Waiter {
        let id: UInt64
        let deadline: Instant
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var waiters: [Waiter] = []
    private var nextID: UInt64 = 0

    var now: Instant { lock.withLock { current } }
    var minimumResolution: Duration { .nanoseconds(1) }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = lock.withLock { nextID += 1; return nextID }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if deadline <= current {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiters.append(Waiter(id: id, deadline: deadline, continuation: continuation))
                    lock.unlock()
                }
            }
        } onCancel: {
            lock.lock()
            let hit = waiters.first { $0.id == id }
            waiters.removeAll { $0.id == id }
            lock.unlock()
            hit?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        lock.lock()
        current = current.advanced(by: duration)
        let due = waiters.filter { $0.deadline <= current }
        waiters.removeAll { $0.deadline <= current }
        lock.unlock()
        due.forEach { $0.continuation.resume() }
    }
}

@Suite struct InteractionTests {
    private func makeNotch(focus: FocusTimer = FocusTimer()) -> (NotchInteraction, ManualClock) {
        let clock = ManualClock()
        let defaults = UserDefaults(suiteName: "InteractionTests-\(UUID().uuidString)")!
        let notch = NotchInteraction(
            settings: AppSettings(defaults: defaults),
            focus: focus,
            agenda: AgendaModel(),
            geometry: .placeholder,
            clock: clock
        )
        return (notch, clock)
    }

    private func alert(_ headline: String, detail: String? = nil) -> NotchAlert {
        NotchAlert(kind: .info, symbol: "bell", tint: .red, headline: headline, detail: detail)
    }

    /// Lets unstructured tasks woken by the clock run.
    private func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    private let far = NSPoint(x: -9_000, y: -9_000)

    @Test func alertWhileOpenGivesFeedbackNowAndPeeksAfterClose() async {
        let (notch, clock) = makeNotch()
        var feedback = 0
        notch.onFeedback = { _ in feedback += 1 }
        notch.open()
        notch.enqueue(alert("Focus done"))
        #expect(feedback == 1)
        #expect(notch.state == .open)
        #expect(notch.queuedAlerts.count == 1)

        notch.close()
        #expect(notch.state == .closed)
        await settle()
        clock.advance(by: .milliseconds(600))
        await settle()
        #expect(notch.state == .peek)
        #expect(notch.peekAlert?.headline == "Focus done")
        #expect(notch.queuedAlerts.isEmpty)
    }

    // MARK: Task check-in (sticky peek)

    /// A focus on a task whose time just ran out, wired to the notch like AppDependencies does.
    private func awaitingCheckIn() -> (NotchInteraction, ManualClock, FocusTimer) {
        let focus = FocusTimer()
        let (notch, clock) = makeNotch(focus: focus)
        focus.onAlert = { notch.enqueue($0) }
        focus.startPomodoro(.with(id: "classic"), label: "Write report", taskID: UUID())
        focus.tick(at: focus.now.addingTimeInterval(25 * 60 + 1))
        return (notch, clock, focus)
    }

    @Test func stickyCheckInStaysUntilTheDecisionIsMade() async {
        let (notch, clock, focus) = awaitingCheckIn()
        #expect(focus.awaitingDecision)
        #expect(notch.state == .peek)
        #expect(notch.peekAlert?.kind == .taskCheckIn)
        #expect(notch.liveActivity == nil || notch.liveActivity == .checkIn)

        await settle()
        clock.advance(by: .seconds(60))
        await settle()
        #expect(notch.state == .peek)

        // Hovering in and out doesn't start the dismiss timer either.
        let rect = notch.layout.hitRect(for: .peek)
        notch.mouseMoved(to: NSPoint(x: rect.midX, y: rect.midY))
        notch.mouseMoved(to: far)
        await settle()
        clock.advance(by: .seconds(10))
        await settle()
        #expect(notch.state == .peek)

        focus.extend(minutes: 5)
        await settle()
        #expect(notch.state == .closed)
        #expect(notch.pendingCheckIn == nil)
    }

    @Test func plainPeekStillAutoDismisses() async {
        let (notch, clock) = makeNotch()
        notch.enqueue(alert("Hello"))
        #expect(notch.state == .peek)
        await settle()
        clock.advance(by: .seconds(5))
        await settle()
        #expect(notch.state == .closed)
    }

    @Test func checkInPeeksAgainWhenThePanelClosesWhileStillAwaiting() async {
        let (notch, clock, focus) = awaitingCheckIn()
        notch.open()
        #expect(notch.state == .open)
        notch.close()
        await settle()
        clock.advance(by: .milliseconds(600))
        await settle()
        #expect(notch.state == .peek)
        #expect(notch.peekAlert?.kind == .taskCheckIn)

        // Deciding while the panel is open means nothing comes back after closing.
        notch.open()
        focus.finishTask()
        await settle()
        notch.close()
        await settle()
        clock.advance(by: .milliseconds(600))
        await settle()
        #expect(notch.state == .closed)
    }

    @Test func checkInPeekIsWiderForItsActions() {
        let (notch, _, _) = awaitingCheckIn()
        let plain = NotchLayout(geometry: notch.geometry).size(for: .peek)
        #expect(notch.layout.size(for: .peek).width > plain.width)
        #expect(notch.layout.size(for: .peek).height == plain.height)
    }

    @Test func queueKeepsThreeAndCoalescesExtras() {
        let (notch, _) = makeNotch()
        notch.open()
        for index in 1...6 { notch.enqueue(alert("A\(index)", detail: "d\(index)")) }
        #expect(notch.queuedAlerts.map(\.headline) == ["A1", "A2", "A3"])
        #expect(notch.queuedAlerts.last?.detail == "d3 · +3 more")
    }

    @Test func menuTrackingWhileClosedIsIgnored() {
        let (notch, _) = makeNotch()
        notch.menuDidBeginTracking()
        notch.menuDidEndTracking()
        notch.open()
        notch.menuDidEndTracking()
        #expect(!notch.holdUntilPointerReturns)
    }

    @Test func holdExpiresAfterEightSeconds() async {
        let (notch, clock) = makeNotch()
        notch.open()
        notch.mouseMoved(to: far)
        notch.menuDidBeginTracking()
        notch.menuDidEndTracking()
        #expect(notch.holdUntilPointerReturns)

        await settle()
        clock.advance(by: .seconds(7))
        await settle()
        #expect(notch.holdUntilPointerReturns)
        #expect(notch.state == .open)

        clock.advance(by: .seconds(2))
        await settle()
        #expect(!notch.holdUntilPointerReturns)
        // Expiry re-evaluates the pointer, which is still outside: the usual close delay applies.
        await settle()
        clock.advance(by: .milliseconds(300))
        await settle()
        #expect(notch.state == .closed)
    }

    @Test func openingWithCaptureLeavesPendingRequest() {
        let (notch, _) = makeNotch()
        notch.open(capturing: true)
        #expect(notch.takePendingCapture())
        #expect(!notch.takePendingCapture())
    }
}

@Suite struct WorkspaceStateTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test func draftScopeAndDetailSurviveViewLifetime() {
        let state = WorkspaceState()
        let id = UUID()
        state.captureDraft = "call Ana tomorrow"
        state.taskScope = .done
        state.detailTaskID = id
        // Views come and go; the object is untouched.
        #expect(state.captureDraft == "call Ana tomorrow")
        #expect(state.taskScope == .done)
        #expect(state.detailTaskID == id)
    }

    @Test func notesDayFollowsMidnightOnlyWhenOnToday() {
        let state = WorkspaceState(now: date("2026-03-10T23:50:00Z"), calendar: calendar)
        #expect(state.notesDayIsToday)
        #expect(state.refreshToday(now: date("2026-03-11T00:01:00Z")))
        #expect(state.notesDay == calendar.startOfDay(for: date("2026-03-11T12:00:00Z")))
        #expect(state.notesFollowsToday)

        state.selectNotesDay(date("2026-03-09T12:00:00Z"))
        #expect(!state.notesFollowsToday)
        #expect(state.refreshToday(now: date("2026-03-12T00:01:00Z")))
        #expect(state.notesDay == calendar.startOfDay(for: date("2026-03-09T00:00:00Z")))
        #expect(!state.notesDayIsToday)

        state.selectNotesDay(state.today)
        #expect(state.notesFollowsToday)
    }

    @Test func refreshOnSameDayIsANoOp() {
        let state = WorkspaceState(now: date("2026-03-10T08:00:00Z"), calendar: calendar)
        #expect(!state.refreshToday(now: date("2026-03-10T20:00:00Z")))
    }

    @Test func futureNotesDayIsClampedToToday() {
        let state = WorkspaceState(now: date("2026-03-10T08:00:00Z"), calendar: calendar)
        state.selectNotesDay(date("2026-03-20T08:00:00Z"))
        #expect(state.notesDay == state.today)
    }
}
