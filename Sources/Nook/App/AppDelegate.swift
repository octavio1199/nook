import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var app: AppDependencies?
    private var panel: NotchPanelController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        let app = DemoMode.scene == nil ? AppDependencies() : AppDependencies(planner: DemoMode.makeStore())
        app.notifier.activate() // delegate must be set before launch ends so action taps are delivered
        let panel = NotchPanelController(app: app)
        panel.startListening()
        statusItem = StatusItemController(app: app)
        self.app = app
        self.panel = panel
        installTerminationSignals(saving: app.planner)
        if let aside = app.planner.quarantinedFile { warnUnreadable(aside) }
        if let scene = DemoMode.scene { DemoMode.run(scene, app: app, panel: panel) }
    }

    private var signalSources: [DispatchSourceSignal] = []

    /// `kill`, logout and installers send SIGTERM, which skips applicationWillTerminate;
    /// flush the debounced save first.
    private func installTerminationSignals(saving planner: PlannerStore) {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { planner.saveNow() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func warnUnreadable(_ aside: URL) {
        let alert = NSAlert()
        alert.messageText = "Nook couldn't read its data file"
        alert.informativeText = "It was moved aside untouched as \(aside.lastPathComponent). Daily backups are in the Backups folder next to it."
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.activateFileViewerSelecting([aside]) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        app?.planner.saveNow()
    }
}
