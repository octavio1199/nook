// Adapted from Pullo (MIT, (c) 2026 Gabriel Jordan)
import AppKit

final class NotchPanelController {
    private let app: AppDependencies
    private let panel: NotchPanel
    private var notch: NotchInteraction { app.notch }
    private var hotKey: HotKey?
    private var monitors: [Any] = []

    init(app: AppDependencies) {
        self.app = app
        panel = NotchPanel(rootView: app.inject(into: NotchRootView()))
        panel.setFrame(app.notch.geometry.panelFrame, display: true)
        panel.undoProvider = { [planner = app.planner] in planner.undoManager }
        panel.orderFrontRegardless()

        notch.onStateChange = { [weak self] state in self?.stateChanged(to: state) }
        notch.onNeedsKeyFocus = { [weak panel] in panel?.makeKeyAndOrderFront(nil) }
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

    private func stateChanged(to state: NotchState) {
        updateMouseCapture()
        if state == .closed, panel.isKeyWindow {
            DispatchQueue.main.async { [panel] in
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
        }
    }

    private func toggleFromKeyboard() {
        notch.toggleFromKeyboard()
        if notch.state == .open { panel.makeKeyAndOrderFront(nil) }
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
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.notch.handleKey(event) == true }
            return handled ? nil : event
        }) {
            monitors.append(keys)
        }
    }
}
