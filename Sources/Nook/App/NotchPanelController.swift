// Adapted from Pullo (MIT, (c) 2026 Gabriel Jordan)
import AppKit

final class NotchPanelController {
    private let app: AppDependencies
    private let panel: NotchPanel
    private var notch: NotchInteraction { app.notch }
    private var hotKey: HotKey?
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
        hotKey = HotKey(.togglePanel) { [weak self] in
            MainActor.assumeIsolated { self?.toggleFromKeyboard() }
        }
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

    private func screensChanged() {
        guard let screen = NotchGeometry.notchedScreen else { return }
        let target = NotchGeometry(screen: screen)
        guard target != notch.geometry else { return }
        if target.screenFrame != notch.geometry.screenFrame { notch.close() }
        notch.geometry = target
        panel.setFrame(target.panelFrame, display: true)
    }

    private func pointerChanged(_ event: NSEvent) {
        let buttonHeld = event.type == .leftMouseDragged
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
