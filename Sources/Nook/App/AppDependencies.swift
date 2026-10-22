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
    lazy var settingsWindow = SettingsWindowController(app: self)

    init(planner: PlannerStore = PlannerStore()) {
        self.planner = planner
        let geometry = NotchGeometry.notchedScreen.map(NotchGeometry.init(screen:)) ?? .placeholder
        notch = NotchInteraction(settings: settings, focus: focus, agenda: agenda, geometry: geometry)
        dueWatcher = TaskDueWatcher(planner: planner)

        let settings = settings
        focus.autoStartBreaks = { settings.autoStartBreaks }
        agenda.alertMinutes = { settings.eventAlertMinutes }

        focus.onSessionLogged = { [planner] in planner.log($0) }
        focus.onAlert = { [weak notch] in notch?.enqueue($0) }
        agenda.onAlert = { [weak notch] in notch?.enqueue($0) }
        dueWatcher.onAlert = { [weak notch] in notch?.enqueue($0) }
        notch.onFeedback = { _ in
            if settings.playsSounds { NSSound(named: "Glass")?.play() }
            if settings.haptics { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
        }
    }

    func inject(into view: some View) -> some View {
        view
            .environment(settings)
            .environment(planner)
            .environment(focus)
            .environment(agenda)
            .environment(notch)
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
