// State machine adapted from Pullo (MIT, (c) 2026 Gabriel Jordan)
import AppKit
import Observation
import SwiftUI

@Observable
final class NotchInteraction {
    private(set) var state: NotchState = .closed {
        didSet { onStateChange?(state) }
    }

    private(set) var peekAlert: NotchAlert?
    private(set) var area: PanelArea = .workspace
    /// Bumped whenever the capture field should take keyboard focus.
    private(set) var captureRequest = 0
    /// While pinned, the open panel ignores pointer exits and outside clicks.
    var isPinned = false

    /// Context menus and pickers draw outside the panel; while one is open, leaving the
    /// panel's area must not close it.
    @ObservationIgnored private var menuDepth = 0
    /// After a menu closes the pointer is usually still outside the panel (where the menu was),
    /// so stay open until the pointer comes back over the panel.
    @ObservationIgnored private(set) var holdUntilPointerReturns = false
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    /// Safety valve: the hold can't outlive this even if the pointer never returns.
    static let holdTimeout: Duration = .seconds(8)
    static let maxQueuedAlerts = 3
    /// True when the last capture request came from an explicit command (⌘N, hotkey), which
    /// should also leave an open task detail; false for the "first click" focus.
    @ObservationIgnored private(set) var captureLeavesDetail = true
    @ObservationIgnored private var pendingCapture = false
    var geometry: NotchGeometry

    private let settings: AppSettings
    private let focus: FocusTimer
    private let agenda: AgendaModel
    private let clock: any Clock<Duration>

    @ObservationIgnored var onStateChange: ((NotchState) -> Void)?
    @ObservationIgnored var onNeedsKeyFocus: (() -> Void)?
    @ObservationIgnored var onFeedback: ((NotchAlert) -> Void)?

    /// Alerts waiting for the notch to be free (they arrived while open, or behind another peek).
    @ObservationIgnored private(set) var queuedAlerts: [NotchAlert] = []
    @ObservationIgnored private var overflow = 0
    @ObservationIgnored private var lastBaseDetail: String?
    @ObservationIgnored private var peekTask: Task<Void, Never>?
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var waitingForPointerExit = false
    @ObservationIgnored private var holdingPeek = false
    @ObservationIgnored private var pointer: NSPoint?
    @ObservationIgnored private var buttonHeld = false

    init(settings: AppSettings, focus: FocusTimer, agenda: AgendaModel, geometry: NotchGeometry, clock: any Clock<Duration> = ContinuousClock()) {
        self.settings = settings
        self.focus = focus
        self.agenda = agenda
        self.geometry = geometry
        self.clock = clock
    }

    var layout: NotchLayout {
        NotchLayout(geometry: geometry, closedWings: wingWidth)
    }

    var wingWidth: CGFloat {
        switch liveActivity {
        case nil: 0
        case .focus:
            focus.phase?.isBreak == true || focus.label?.isEmpty == false ? NotchLayout.labeledWingWidth : NotchLayout.wingWidth
        case .event: NotchLayout.wingWidth
        }
    }

    /// What the closed notch shows beside the camera, if anything.
    var liveActivity: LiveActivity? {
        guard geometry.hasNotch, settings.showsLiveActivity else { return nil }
        if focus.isActive { return .focus }
        if let event = agenda.startingSoon { return .event(event) }
        return nil
    }

    // MARK: - Pointer

    func mouseMoved(to point: NSPoint, buttonHeld: Bool = false) {
        pointer = point
        self.buttonHeld = buttonHeld
        let inside = layout.hitRect(for: state).contains(point)

        if waitingForPointerExit {
            if !inside { waitingForPointerExit = false }
            return
        }

        switch state {
        case .peek:
            if inside {
                guard !holdingPeek else { return }
                holdingPeek = true
                peekTask?.cancel()
            } else if holdingPeek {
                holdingPeek = false
                dismissPeek(after: .seconds(1.5))
            }
        case .closed:
            guard inside, settings.openMode == .hover else { return cancelHover() }
            scheduleHover(after: .milliseconds(80)) { notch in
                if notch.isPointerOver(notch.state) { notch.open() }
            }
        case .open:
            if holdUntilPointerReturns {
                if inside { endHold() }
                return cancelHover()
            }
            guard !inside, !buttonHeld, !isPinned, menuDepth == 0 else { return cancelHover() }
            scheduleHover(after: .milliseconds(220)) { notch in
                if !notch.isPointerOver(.open), !notch.buttonHeld { notch.close() }
            }
        }
    }

    /// Only menus that begin while the panel is open matter (context menus, pickers); menus tracked
    /// while closed (status item, other apps) are ignored.
    func menuDidBeginTracking() {
        guard state == .open else { return }
        menuDepth += 1
        cancelHover()
    }

    func menuDidEndTracking() {
        guard menuDepth > 0 else { return }
        menuDepth -= 1
        if state == .open, menuDepth == 0 { beginHold() }
    }

    private func beginHold() {
        holdUntilPointerReturns = true
        holdTask?.cancel()
        let clock = clock
        holdTask = Task { [weak self] in
            try? await clock.sleep(for: Self.holdTimeout)
            guard let self, !Task.isCancelled, holdUntilPointerReturns else { return }
            holdTask = nil
            holdUntilPointerReturns = false
            if state == .open, let pointer { mouseMoved(to: pointer, buttonHeld: buttonHeld) }
        }
    }

    private func endHold() {
        holdUntilPointerReturns = false
        holdTask?.cancel()
        holdTask = nil
    }

    func mouseDown(at point: NSPoint) {
        switch state {
        case .open:
            if !isPinned, !layout.hitRect(for: .open).contains(point) { close() }
        case .closed:
            if settings.openMode == .click, layout.hitRect(for: .closed).contains(point) { open() }
        case .peek:
            break
        }
    }

    private func scheduleHover(after delay: Duration, _ action: @escaping (NotchInteraction) -> Void) {
        guard hoverTask == nil else { return }
        let clock = clock
        hoverTask = Task { [weak self] in
            try? await clock.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            hoverTask = nil
            action(self)
        }
    }

    private func isPointerOver(_ state: NotchState) -> Bool {
        pointer.map(layout.hitRect(for: state).contains) ?? false
    }

    private func cancelHover() {
        hoverTask?.cancel()
        hoverTask = nil
    }

    // MARK: - Transitions

    func open(capturing: Bool = false) {
        peekTask?.cancel()
        holdingPeek = false
        queuedAlerts.removeAll()
        overflow = 0
        withAnimation(Motion.open) {
            state = .open
            peekAlert = nil
        }
        if capturing {
            area = .workspace
            pendingCapture = true
            captureLeavesDetail = true
            onNeedsKeyFocus?()
            captureRequest += 1
        }
    }

    /// The workspace view appears after `open(capturing:)` returns, so it misses the `captureRequest`
    /// change; it asks here once on appear instead.
    func takePendingCapture() -> Bool {
        defer { pendingCapture = false }
        return pendingCapture && state == .open
    }

    func toggleFromKeyboard() {
        if state == .open { close() } else { open(capturing: true) }
    }

    func close(pointerStaysOver: Bool = false) {
        cancelHover()
        peekTask?.cancel()
        holdingPeek = false
        isPinned = false
        endHold()
        menuDepth = 0
        pendingCapture = false
        waitingForPointerExit = pointerStaysOver
        withAnimation(Motion.close) { state = .closed }
        showQueuedPeekAfterClose()
    }

    /// Alerts that arrived while the panel was open get their peek once it has finished closing.
    private func showQueuedPeekAfterClose() {
        guard !queuedAlerts.isEmpty else { return }
        let clock = clock
        peekTask = Task { [weak self] in
            try? await clock.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            showNextPeek()
        }
    }

    func show(_ area: PanelArea) {
        guard area != self.area else { return }
        withAnimation(Motion.navigate) { self.area = area }
    }

    func requestCapture(leavingDetail: Bool = true) {
        area = .workspace
        captureLeavesDetail = leavingDetail
        onNeedsKeyFocus?()
        captureRequest += 1
    }

    // MARK: - Alerts

    func enqueue(_ alert: NotchAlert) {
        onFeedback?(alert)
        queue(alert)
        if state == .closed { showNextPeek() }
    }

    /// Keeps at most `maxQueuedAlerts`; extras are folded into the last one as "+N more".
    private func queue(_ alert: NotchAlert) {
        guard queuedAlerts.count >= Self.maxQueuedAlerts else {
            queuedAlerts.append(alert)
            overflow = 0
            return
        }
        if overflow == 0 { lastBaseDetail = queuedAlerts[queuedAlerts.count - 1].detail }
        overflow += 1
        queuedAlerts[queuedAlerts.count - 1].detail = [lastBaseDetail, "+\(overflow) more"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    func tapPeek(_ alert: NotchAlert) {
        open()
    }

    private func showNextPeek() {
        guard state == .closed, !queuedAlerts.isEmpty else { return }
        let alert = queuedAlerts.removeFirst()
        if queuedAlerts.isEmpty { overflow = 0 }
        withAnimation(Motion.peek) {
            peekAlert = alert
            state = .peek
        }
        dismissPeek(after: .seconds(4.5))
    }

    private func dismissPeek(after delay: Duration) {
        peekTask?.cancel()
        let clock = clock
        peekTask = Task { [weak self] in
            try? await clock.sleep(for: delay)
            guard let self, !Task.isCancelled, state == .peek else { return }
            withAnimation(Motion.close) { self.state = .closed }
            try? await clock.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            showNextPeek()
        }
    }

    // MARK: - Keyboard

    func handleKey(_ event: NSEvent) -> Bool {
        guard state == .open else { return false }
        let command = event.modifierFlags.contains(.command)
        switch (Int(event.keyCode), command, event.charactersIgnoringModifiers ?? "") {
        case (53, _, _):
            close()
        case (_, true, "1"):
            show(.workspace)
        case (_, true, "2"):
            show(.insights)
        case (_, true, "n"):
            requestCapture()
        default:
            return false
        }
        return true
    }
}

enum LiveActivity: Equatable {
    case focus
    case event(AgendaEvent)
}
