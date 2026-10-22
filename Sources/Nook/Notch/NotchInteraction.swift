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
    var geometry: NotchGeometry

    private let settings: AppSettings
    private let focus: FocusTimer
    private let agenda: AgendaModel
    private let clock: any Clock<Duration>

    @ObservationIgnored var onStateChange: ((NotchState) -> Void)?
    @ObservationIgnored var onNeedsKeyFocus: (() -> Void)?
    @ObservationIgnored var onFeedback: ((NotchAlert) -> Void)?

    @ObservationIgnored private var alerts: [NotchAlert] = []
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
            guard !inside, !buttonHeld, !isPinned else { return cancelHover() }
            scheduleHover(after: .milliseconds(220)) { notch in
                if !notch.isPointerOver(.open), !notch.buttonHeld { notch.close() }
            }
        }
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
        alerts.removeAll()
        withAnimation(Motion.open) {
            state = .open
            peekAlert = nil
        }
        if capturing {
            area = .workspace
            onNeedsKeyFocus?()
            captureRequest += 1
        }
    }

    func toggleFromKeyboard() {
        if state == .open { close() } else { open(capturing: true) }
    }

    func close(pointerStaysOver: Bool = false) {
        cancelHover()
        peekTask?.cancel()
        holdingPeek = false
        isPinned = false
        waitingForPointerExit = pointerStaysOver
        withAnimation(Motion.close) { state = .closed }
    }

    func show(_ area: PanelArea) {
        guard area != self.area else { return }
        withAnimation(Motion.navigate) { self.area = area }
    }

    func requestCapture() {
        area = .workspace
        onNeedsKeyFocus?()
        captureRequest += 1
    }

    // MARK: - Alerts

    func enqueue(_ alert: NotchAlert) {
        onFeedback?(alert)
        guard state != .open else { return }
        alerts.append(alert)
        if state == .closed { showNextPeek() }
    }

    func tapPeek(_ alert: NotchAlert) {
        open()
    }

    private func showNextPeek() {
        guard state == .closed, !alerts.isEmpty else { return }
        let alert = alerts.removeFirst()
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
