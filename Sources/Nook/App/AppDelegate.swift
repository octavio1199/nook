import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var app: AppDependencies?
    private var panel: NotchPanelController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        let app = DemoMode.scene == nil ? AppDependencies() : AppDependencies(planner: DemoMode.makeStore())
        let panel = NotchPanelController(app: app)
        panel.startListening()
        statusItem = StatusItemController(app: app)
        self.app = app
        self.panel = panel
        if let scene = DemoMode.scene { DemoMode.run(scene, app: app, panel: panel) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        app?.planner.saveNow()
    }
}
