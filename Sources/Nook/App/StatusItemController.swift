import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private let app: AppDependencies
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(app: AppDependencies) {
        self.app = app
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Nook")
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Open Nook", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "New task", action: #selector(capture), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Nook", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        app.statusMenu = menu
    }

    /// Titles carry the current (possibly rebound) global shortcuts.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items[0].title = "Open Nook  \(app.settings.shortcut(for: .toggle).symbols)"
        menu.items[1].title = "New task  \(app.settings.shortcut(for: .newTask).symbols)"
    }

    @objc private func openPanel() { app.notch.open() }
    @objc private func capture() { app.notch.open(capturing: true) }
    @objc private func openSettings() { app.openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
