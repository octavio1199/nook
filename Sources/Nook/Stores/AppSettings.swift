import Foundation
import Observation
import ServiceManagement

enum OpenMode: String, CaseIterable, Identifiable {
    case hover, click

    var id: Self { self }
    var title: String { self == .hover ? "Hover" : "Click" }
}

enum SystemNotificationPolicy: String, CaseIterable, Identifiable {
    case off, whenAway, always

    var id: Self { self }
    var title: String {
        switch self {
        case .off: "Off"
        case .whenAway: "When I'm away"
        case .always: "Always"
        }
    }
}

@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var openMode: OpenMode { didSet { defaults.set(openMode.rawValue, forKey: "openMode") } }
    var panelStyle: PanelStyle { didSet { defaults.set(panelStyle.rawValue, forKey: "panelStyle") } }
    var showsLiveActivity: Bool { didSet { defaults.set(showsLiveActivity, forKey: "showsLiveActivity") } }
    var playsSounds: Bool { didSet { defaults.set(playsSounds, forKey: "playsSounds") } }
    var haptics: Bool { didSet { defaults.set(haptics, forKey: "haptics") } }
    var focusPresetID: String { didSet { defaults.set(focusPresetID, forKey: "focusPresetID") } }
    var autoStartBreaks: Bool { didSet { defaults.set(autoStartBreaks, forKey: "autoStartBreaks") } }
    var eventAlertMinutes: Int { didSet { defaults.set(eventAlertMinutes, forKey: "eventAlertMinutes") } }
    var systemNotifications: SystemNotificationPolicy { didSet { defaults.set(systemNotifications.rawValue, forKey: "systemNotifications") } }
    var showsAgenda: Bool { didSet { defaults.set(showsAgenda, forKey: "showsAgenda") } }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        openMode = OpenMode(rawValue: defaults.string(forKey: "openMode") ?? "") ?? .hover
        panelStyle = PanelStyle(rawValue: defaults.string(forKey: "panelStyle") ?? "") ?? .solid
        showsLiveActivity = defaults.object(forKey: "showsLiveActivity") as? Bool ?? true
        playsSounds = defaults.object(forKey: "playsSounds") as? Bool ?? true
        haptics = defaults.object(forKey: "haptics") as? Bool ?? true
        focusPresetID = defaults.string(forKey: "focusPresetID") ?? "classic"
        autoStartBreaks = defaults.object(forKey: "autoStartBreaks") as? Bool ?? true
        eventAlertMinutes = defaults.object(forKey: "eventAlertMinutes") as? Int ?? 5
        systemNotifications = SystemNotificationPolicy(rawValue: defaults.string(forKey: "systemNotifications") ?? "") ?? .whenAway
        showsAgenda = defaults.object(forKey: "showsAgenda") as? Bool ?? true
    }
}
