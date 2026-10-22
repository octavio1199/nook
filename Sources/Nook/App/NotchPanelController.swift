// Adapted from Pullo (MIT, (c) 2026 Gabriel Jordan)
import AppKit

final class NotchPanelController {
    private let app: AppDependencies
    private let panel: NotchPanel
    private var notch: NotchInteraction { app.notch }
    private var monitors: [Any] = []
    /// The app that was frontmost when the panel became key, so focus can go back to it.
    private var previousApp: NSRunningApplication?

    init(app: AppDependencies) {
        self.app = app
        panel = NotchPanel(rootView: app.inject(into: NotchRootView()))
        panel.setFrame(app.notch.geometry.panelFrame, display: true)
        panel.undoProvider = { [planner = app.planner] in planner.undoManager }
        panel.orderFrontRegardless()

        notch.onStateChange = { [weak self] state in self?.stateChanged(to: state) }
        notch.onNeedsKeyFocus = { [weak self] in self?.becomeKey() }
    }

    func startListening() {
        app.hotKeys.handlers = [
            .toggle: { [weak self] in self?.toggleFromKeyboard() },
            .newTask: { [weak self] in self?.newTaskFromKeyboard() },
            .pin: { [weak self] in self?.pinFromKeyboard() },
            .focus: { [weak self] in self?.focusFromKeyboard() },
            .moveHere: { [weak self] in self?.moveToPointerScreen() },
        ]
        observeDisplayChoice()
        if DemoMode.scene == nil { app.hotKeys.apply(app.settings) }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] note in
            let menuID = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, !self.isStatusMenu(menuID) else { return }
                self.notch.menuDidBeginTracking()
            }
        }
        NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] note in
            let menuID = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, !self.isStatusMenu(menuID) else { return }
                self.notch.menuDidEndTracking()
            }
        }
        installEventMonitors()
        updateMouseCapture()
    }

    /// Renders the panel's own view hierarchy to a PNG (no Screen Recording permission needed).
    func snapshot(to url: URL) {
        guard let view = panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private func isStatusMenu(_ id: ObjectIdentifier?) -> Bool {
        guard let id, let status = app.statusMenu else { return false }
        return id == ObjectIdentifier(status)
    }

    private func stateChanged(to state: NotchState) {
        updateMouseCapture()
        if state == .open { app.workspace.refreshToday() }
        if state == .closed, panel.isKeyWindow {
            let previous = previousApp
            previousApp = nil
            DispatchQueue.main.async { [panel] in
                panel.orderOut(nil)
                panel.orderFrontRegardless()
                Self.restoreFocus(to: previous)
            }
        } else if state == .closed {
            previousApp = nil
        }
    }

    /// Hands keyboard focus back to the app that had it. Skipped when Nook itself is frontmost
    /// (e.g. its Settings window just opened) or the user already moved on to another app.
    private static func restoreFocus(to previous: NSRunningApplication?) {
        guard let previous, !previous.isTerminated else { return }
        guard let current = NSWorkspace.shared.frontmostApplication,
              current.processIdentifier == previous.processIdentifier,
              current.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        previous.activate(options: [])
    }

    /// Makes the panel key without activating Nook, remembering who had focus.
    private func becomeKey() {
        if !panel.isKeyWindow {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func toggleFromKeyboard() {
        notch.toggleFromKeyboard()
        if notch.state == .open { becomeKey() }
    }

    private func newTaskFromKeyboard() {
        notch.newTaskFromKeyboard(composerOpen: app.workspace.isComposerOpen)
        if notch.state == .open { becomeKey() }
    }

    private func pinFromKeyboard() {
        notch.togglePinFromKeyboard()
        if notch.state == .open { becomeKey() }
    }

    /// Opens the workspace with the focus picker; pressing it again while the picker shows closes it.
    private func focusFromKeyboard() {
        if notch.state == .open, app.workspace.isFocusPickerOpen {
            app.workspace.closeFocusPicker()
            return
        }
        notch.openForFocusPicker()
        app.workspace.openFocusPicker()
        becomeKey()
    }

    /// First click inside the open panel: take key status (hover never does), and unless the click
    /// landed in something that takes text input, put the cursor in the task capture field.
    private func panelMouseDown(_ event: NSEvent) {
        guard notch.state == .open, event.window === panel, !panel.isKeyWindow else { return }
        becomeKey()
        DispatchQueue.main.async { [weak self] in
            guard let self, notch.state == .open, notch.area == .workspace else { return }
            if panel.firstResponder is NSText { return }
            notch.requestCapture(leavingDetail: false)
        }
    }

    /// Displays plugged in or out, resolution or arrangement changed, lid opened or closed.
    private func screensChanged() {
        relocate()
    }

    /// Puts the panel on the display the settings ask for (a disconnected display falls back to the
    /// built-in or main one; the choice is kept for when it comes back).
    private func relocate(force: Bool = true) {
        guard let screen = NSScreen.nook(for: app.settings.displayChoice) else { return }
        let target = NotchGeometry(screen: screen)
        guard target != notch.geometry else { return }
        if target.screenFrame != notch.geometry.screenFrame {
            // "Follow the mouse" never yanks an open panel or a peek away from under the user.
            guard force || notch.state == .closed else { return }
            notch.close()
        }
        notch.geometry = target
        panel.setFrame(target.panelFrame, display: true)
        updateMouseCapture()
    }

    /// Re-arms after each change (observation fires once).
    private func observeDisplayChoice() {
        withObservationTracking {
            _ = app.settings.displayChoice
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.relocate()
                self?.observeDisplayChoice()
            }
        }
    }

    /// Demo screenshots: puts the panel on `screen` without touching the saved choice.
    func place(on screen: NSScreen) {
        let target = NotchGeometry(screen: screen)
        notch.geometry = target
        panel.setFrame(target.panelFrame, display: true)
    }

    /// Global shortcut: pins Nook to the display the pointer is on.
    private func moveToPointerScreen() {
        guard let screen = NSScreen.nook(for: .followMouse) else { return }
        app.settings.displayChoice = .display(screen.displayUUID)
    }

    private func pointerChanged(_ event: NSEvent) {
        let buttonHeld = event.type == .leftMouseDragged
        if app.settings.displayChoice == .followMouse, !buttonHeld,
           !notch.geometry.screenFrame.contains(NSEvent.mouseLocation) {
            relocate(force: false)
        }
        notch.mouseMoved(to: NSEvent.mouseLocation, buttonHeld: buttonHeld)
        if notch.state == .open, buttonHeld { return }
        updateMouseCapture()
    }

    private func updateMouseCapture() {
        let state = notch.state
        let over = notch.layout.hitRect(for: state).contains(NSEvent.mouseLocation)
        let ignores = state == .closed || !over
        if panel.ignoresMouseEvents != ignores { panel.ignoresMouseEvents = ignores }
    }

    private func installEventMonitors() {
        let pointer: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: pointer.union(.leftMouseDown), handler: { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .leftMouseDown {
                    self?.notch.mouseDown(at: NSEvent.mouseLocation)
                    self?.updateMouseCapture()
                } else {
                    self?.pointerChanged(event)
                }
            }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: pointer, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerChanged(event) }
            return event
        }) {
            monitors.append(local)
        }
        if let clicks = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.panelMouseDown(event) }
            return event
        }) {
            monitors.append(clicks)
        }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.notch.handleKey(event) == true }
            return handled ? nil : event
        }) {
            monitors.append(keys)
        }
    }
}
