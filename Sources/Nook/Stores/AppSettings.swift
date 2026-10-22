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
    /// Working hours for auto-planning, in minutes since midnight (default 09:00 to 18:00).
    var workdayStart: Int { didSet { defaults.set(workdayStart, forKey: "workdayStart") } }
    var workdayEnd: Int { didSet { defaults.set(workdayEnd, forKey: "workdayEnd") } }
    /// The display Nook lives on.
    var displayChoice: DisplayChoice { didSet { defaults.set(displayChoice.storageValue, forKey: "displayChoice") } }
    /// Global shortcuts the user rebound; the rest use `GlobalAction.defaultShortcut`.
    private(set) var customShortcuts: [GlobalAction: Shortcut] {
        didSet {
            let stored = Dictionary(uniqueKeysWithValues: customShortcuts.map { ($0.key.rawValue, $0.value) })
            defaults.set(try? JSONEncoder().encode(stored), forKey: "shortcuts")
        }
    }

    func shortcut(for action: GlobalAction) -> Shortcut {
        customShortcuts[action] ?? action.defaultShortcut
    }

    /// The action already using `shortcut`, other than `action` itself.
    func conflict(for shortcut: Shortcut, excluding action: GlobalAction) -> GlobalAction? {
        GlobalAction.allCases.first { $0 != action && self.shortcut(for: $0) == shortcut }
    }

    /// Rebinds `action`. Refused (returns the other action) when another action already uses it.
    @discardableResult
    func setShortcut(_ shortcut: Shortcut, for action: GlobalAction) -> GlobalAction? {
        if let other = conflict(for: shortcut, excluding: action) { return other }
        customShortcuts[action] = shortcut == action.defaultShortcut ? nil : shortcut
        return nil
    }

    func resetShortcut(for action: GlobalAction) {
        customShortcuts[action] = nil
    }

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
        let start = defaults.object(forKey: "workdayStart") as? Int ?? 9 * 60
        let end = defaults.object(forKey: "workdayEnd") as? Int ?? 18 * 60
        let valid = (0..<1440).contains(start) && (1...1440).contains(end) && start < end
        workdayStart = valid ? start : 9 * 60
        workdayEnd = valid ? end : 18 * 60
        displayChoice = DisplayChoice(storageValue: defaults.string(forKey: "displayChoice"))
        let stored = defaults.data(forKey: "shortcuts").flatMap { try? JSONDecoder().decode([String: Shortcut].self, from: $0) } ?? [:]
        customShortcuts = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            GlobalAction(rawValue: key).map { ($0, value) }
        })
    }
}
