import AppKit

final class StatusItemController: NSObject {
    private let app: AppDependencies
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(app: AppDependencies) {
        self.app = app
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Nook")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Nook  \(Shortcut.togglePanel.symbols)", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quick capture", action: #selector(capture), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Nook", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        app.statusMenu = menu
    }

    @objc private func openPanel() { app.notch.open() }
    @objc private func capture() { app.notch.open(capturing: true) }
    @objc private func openSettings() { app.openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
