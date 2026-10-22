import AppKit
import SwiftUI

/// Composition root: builds every store once and wires their callbacks.
final class AppDependencies {
    let settings = AppSettings()
    let planner: PlannerStore
    let focus = FocusTimer()
    let agenda = AgendaModel()
    let notch: NotchInteraction
    let dueWatcher: TaskDueWatcher
    let blocks: BlockWatcher
    let workspace = WorkspaceState()
    let notifier: SystemNotifier
    /// The status item's menu; its tracking must not hold the open panel.
    weak var statusMenu: NSMenu?
    private var dayObservers: [NSObjectProtocol] = []
    lazy var settingsWindow = SettingsWindowController(app: self)

    init(planner: PlannerStore = PlannerStore()) {
        self.planner = planner
        let geometry = NotchGeometry.notchedScreen.map(NotchGeometry.init(screen:)) ?? .placeholder
        notch = NotchInteraction(settings: settings, focus: focus, agenda: agenda, geometry: geometry)
        dueWatcher = TaskDueWatcher(planner: planner)
        notifier = SystemNotifier(settings: settings, focus: focus, planner: planner, agenda: agenda, notch: notch)
        notifier.isEnabled = DemoMode.scene == nil
        blocks = BlockWatcher(planner: planner, focus: focus, agenda: agenda, settings: settings)
        blocks.isEnabled = DemoMode.scene == nil
        notch.blocks = blocks

        let settings = settings
        focus.autoStartBreaks = { settings.autoStartBreaks }
        agenda.alertMinutes = { settings.eventAlertMinutes }

        focus.onSessionLogged = { [planner] in planner.log($0) }
        focus.onTaskFinished = { [planner] id in
            if planner.task(id)?.done == false { planner.toggle(id) }
        }
        focus.onAlert = { [weak notch] in notch?.enqueue($0) }
        agenda.onAlert = { [weak notch] in notch?.enqueue($0) }
        dueWatcher.onAlert = { [weak notch] in notch?.enqueue($0) }
        blocks.onAlert = { [weak notch] in notch?.enqueue($0) }
        blocks.onResolved = { [weak notch] in notch?.withdrawBlockAlerts(for: $0) }
        notch.onFeedback = { [notifier] alert in
            notifier.post(alert)
            if settings.playsSounds { NSSound(named: "Glass")?.play() }
            if settings.haptics { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
        }
        observeDayChanges()
        DayDemo.configureIfRequested(app: self)
    }

    /// Midnight rollover and wake from sleep (timers don't fire while asleep).
    private func observeDayChanges() {
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.dayMayHaveChanged() }
        }
        dayObservers = [
            NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: refresh),
            NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main, using: refresh),
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh),
        ]
    }

    func dayMayHaveChanged() {
        // Notepad edits are written to the store on every keystroke; flush before the notepad switches day.
        planner.saveNow()
        workspace.refreshToday()
    }

    func inject(into view: some View) -> some View {
        view
            .environment(settings)
            .environment(planner)
            .environment(focus)
            .environment(agenda)
            .environment(notch)
            .environment(blocks)
            .environment(workspace)
            .environment(notifier)
            .environment(\.openSettings, OpenNookSettings { [weak self] in self?.openSettings() })
    }

    func openSettings() {
        notch.close()
        settingsWindow.show()
    }
}

struct OpenNookSettings {
    var action: () -> Void
    func callAsFunction() { action() }
}

private struct OpenNookSettingsKey: EnvironmentKey {
    static let defaultValue = OpenNookSettings {}
}

extension EnvironmentValues {
    var openSettings: OpenNookSettings {
        get { self[OpenNookSettingsKey.self] }
        set { self[OpenNookSettingsKey.self] = newValue }
    }
}
