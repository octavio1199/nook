import AppKit
import Observation
@preconcurrency import UserNotifications

// MARK: - Pure logic (no UserNotifications calls; unit tested)

/// What the Mac is doing right now, as far as "can the user see the notch" goes.
struct PresenceContext: Equatable {
    var screenLocked = false
    var displaysAsleep = false
    var fullScreenOnNotchDisplay = false
    var justWoke = false

    /// True when the notch peek would probably go unseen.
    var notchHidden: Bool { screenLocked || displaysAsleep || fullScreenOnNotchDisplay || justWoke }
}

enum NotificationPolicyLogic {
    static func shouldPost(policy: SystemNotificationPolicy, context: PresenceContext, kind: NotchAlert.Kind) -> Bool {
        guard kind != .info else { return false }
        switch policy {
        case .off: return false
        case .always: return true
        case .whenAway: return context.notchHidden
        }
    }

    /// Focus-related alerts may break through Focus modes (when the user allowed time-sensitive).
    static func isTimeSensitive(_ kind: NotchAlert.Kind) -> Bool {
        switch kind {
        case .taskCheckIn, .focusFinished, .breakFinished, .focusPaused, .blockStart: true
        case .eventSoon, .taskDue, .info, .blockSoon: false
        }
    }
}

/// Stable identifiers: `nook.<kind>.<key>`, where key is the task id, event id or alert id.
/// A repeat alert of the same kind for the same thing replaces the previous notification.
nonisolated enum NotificationID {
    static let prefix = "nook"
    static let test = "nook.test"

    static func kindName(_ kind: NotchAlert.Kind) -> String {
        switch kind {
        case .focusFinished: "focusFinished"
        case .breakFinished: "breakFinished"
        case .eventSoon: "eventSoon"
        case .taskDue: "taskDue"
        case .focusPaused: "focusPaused"
        case .taskCheckIn: "taskCheckIn"
        case .info: "info"
        case .blockSoon: "blockSoon"
        case .blockStart: "blockStart"
        }
    }

    static func make(kind: NotchAlert.Kind, key: String?) -> String {
        "\(prefix).\(kindName(kind)).\(key ?? "-")"
    }

    static func parse(_ identifier: String) -> (kind: String, key: String)? {
        let parts = identifier.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == prefix else { return nil }
        return (String(parts[1]), String(parts[2]))
    }

    /// Notification category (which action buttons it shows), if any.
    static func category(kind: NotchAlert.Kind, hasTask: Bool, hasJoinURL: Bool, headline: String) -> String? {
        switch kind {
        case .taskCheckIn: "TASK_CHECKIN"
        case .breakFinished: hasTask ? "BREAK_OVER_CONTINUE" : "BREAK_OVER"
        case .focusFinished: headline == "Focus done" ? "FOCUS_DONE" : nil
        case .taskDue: hasTask ? "TASK_DUE" : nil
        case .eventSoon: hasJoinURL ? "EVENT_SOON_JOIN" : nil
        case .focusPaused: "FOCUS_PAUSED"
        case .info, .blockSoon, .blockStart: nil
        }
    }
}

/// What a tapped notification (or one of its buttons) asks the app to do.
nonisolated enum NotificationCommand: Equatable {
    case open
    case extend(minutes: Int)
    case breakThenContinue
    case finishTask
    case startNextFocus
    case startBreak
    case resume
    case snoozeTask(UUID, minutes: Int)
    case toggleTask(UUID)
    case join(URL)
    case none

    static let snoozeMinutes = 10

    nonisolated static func from(actionID: String, userInfo: [String: String]) -> NotificationCommand {
        let taskID = userInfo["taskID"].flatMap(UUID.init(uuidString:))
        switch actionID {
        case UNNotificationDefaultActionIdentifier: return .open
        case UNNotificationDismissActionIdentifier: return .none
        case "EXTEND_5": return .extend(minutes: 5)
        case "BREAK_THEN_CONTINUE": return .breakThenContinue
        case "FINISH_TASK": return .finishTask
        case "START_FOCUS", "CONTINUE_TASK": return .startNextFocus
        case "START_BREAK": return .startBreak
        case "SKIP": return .none
        case "RESUME": return .resume
        case "SNOOZE_TASK": return taskID.map { .snoozeTask($0, minutes: snoozeMinutes) } ?? .none
        case "DONE_TASK": return taskID.map { .toggleTask($0) } ?? .none
        case "JOIN_EVENT":
            guard let raw = userInfo["url"], let url = URL(string: raw), url.scheme?.lowercased() == "https" else { return .none }
            return .join(url)
        default: return .none
        }
    }
}

/// App state relevant to deciding whether a delivered notification went stale.
nonisolated struct NotificationSnapshot: Equatable {
    var awaitingCheckIn = false
    var focusActive = false
    var focusPaused = false
    /// Open, timed tasks whose due time has already passed.
    var dueTaskIDs: Set<UUID> = []
}

nonisolated enum NotificationStaleness {
    static func isStale(identifier: String, in snapshot: NotificationSnapshot) -> Bool {
        guard let (kind, key) = NotificationID.parse(identifier) else { return false }
        switch kind {
        case "taskCheckIn": return !snapshot.awaitingCheckIn
        case "focusPaused": return !(snapshot.focusActive && snapshot.focusPaused)
        case "breakFinished": return snapshot.focusActive
        case "taskDue":
            guard let id = UUID(uuidString: key) else { return false }
            return !snapshot.dueTaskIDs.contains(id)
        default: return false
        }
    }
}

enum NotificationAuthorization: Equatable {
    case unknown, notDetermined, denied, authorized
}

// MARK: - Notifier

@Observable
final class SystemNotifier: NSObject, UNUserNotificationCenterDelegate {
    private(set) var authorization: NotificationAuthorization = .unknown

    /// Off in demo mode and in non-bundled runs (`swift run`), where UNUserNotificationCenter would crash.
    @ObservationIgnored var isEnabled = true

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let focus: FocusTimer
    @ObservationIgnored private let planner: PlannerStore
    @ObservationIgnored private let agenda: AgendaModel
    @ObservationIgnored private let notch: NotchInteraction

    @ObservationIgnored private var presence = PresenceContext()
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [(center: NotificationCenter, token: Any)] = []
    @ObservationIgnored private var wasFocusActive = false
    @ObservationIgnored private var activated = false

    init(settings: AppSettings, focus: FocusTimer, planner: PlannerStore, agenda: AgendaModel, notch: NotchInteraction) {
        self.settings = settings
        self.focus = focus
        self.planner = planner
        self.agenda = agenda
        self.notch = notch
        super.init()
    }

    private var isAvailable: Bool { isEnabled && Bundle.main.bundleURL.pathExtension == "app" }
    private var center: UNUserNotificationCenter { .current() }

    // MARK: Setup

    /// Registers the delegate and categories. Call early at launch; never prompts.
    func activate() {
        guard isAvailable, !activated else { return }
        activated = true
        center.delegate = self
        center.setNotificationCategories(Self.categories)
        wasFocusActive = focus.isActive
        observePresence()
        observeState()
        Task { await refreshAuthorization() }
    }

    private static var categories: Set<UNNotificationCategory> {
        func action(_ id: String, _ title: String) -> UNNotificationAction { UNNotificationAction(identifier: id, title: title, options: []) }
        func category(_ id: String, _ actions: [UNNotificationAction]) -> UNNotificationCategory {
            UNNotificationCategory(identifier: id, actions: actions, intentIdentifiers: [], options: [])
        }
        return [
            category("TASK_CHECKIN", [action("EXTEND_5", "+5 min"), action("BREAK_THEN_CONTINUE", "Break"), action("FINISH_TASK", "Done ✓")]),
            category("BREAK_OVER_CONTINUE", [action("CONTINUE_TASK", "Continue")]),
            category("BREAK_OVER", [action("START_FOCUS", "Start focus")]),
            category("FOCUS_DONE", [action("START_BREAK", "Start break"), action("SKIP", "Skip")]),
            category("TASK_DUE", [action("SNOOZE_TASK", "Snooze 10 min"), action("DONE_TASK", "Done")]),
            category("EVENT_SOON_JOIN", [action("JOIN_EVENT", "Join")]),
            category("FOCUS_PAUSED", [action("RESUME", "Resume")]),
        ]
    }

    // MARK: Authorization

    func refreshAuthorization() async {
        guard isAvailable else { return }
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .notDetermined: authorization = .notDetermined
        case .denied: authorization = .denied
        default: authorization = .authorized
        }
    }

    /// Asks the system once, the first time it is useful (a focus starts, or the user enables it).
    func requestAuthorizationIfNeeded() {
        guard isAvailable else { return }
        Task {
            await refreshAuthorization()
            guard authorization == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorization()
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Posting

    /// Called for every alert the notch receives.
    func post(_ alert: NotchAlert) {
        guard isAvailable else { return }
        let context = currentPresence()
        guard NotificationPolicyLogic.shouldPost(policy: settings.systemNotifications, context: context, kind: alert.kind) else { return }
        deliver(alert, away: context.notchHidden)
    }

    func sendTest() {
        guard isAvailable else { return }
        Task {
            await refreshAuthorization()
            if authorization == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                await refreshAuthorization()
            }
            guard authorization == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Nook notifications work"
            content.body = "You'll see focus check-ins, due tasks and meetings here."
            if settings.playsSounds { content.sound = .default }
            try? await center.add(UNNotificationRequest(identifier: NotificationID.test, content: content, trigger: nil))
        }
    }

    private func deliver(_ alert: NotchAlert, away: Bool) {
        let taskID = alert.kind == .taskDue ? (alert.taskID ?? dueTask(titled: alert.headline)?.id) : alert.taskID
        let event = alert.kind == .eventSoon ? upcomingEvent(titled: alert.headline) : nil
        let joinURL = event?.joinURL.flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }

        let content = UNMutableNotificationContent()
        content.title = alert.headline
        if let detail = alert.detail { content.body = detail }
        var info: [String: String] = ["kind": NotificationID.kindName(alert.kind)]
        if let taskID { info["taskID"] = taskID.uuidString }
        if let joinURL { info["url"] = joinURL.absoluteString }
        content.userInfo = info
        if let category = NotificationID.category(kind: alert.kind, hasTask: taskID != nil, hasJoinURL: joinURL != nil, headline: alert.headline) {
            content.categoryIdentifier = category
        }
        // The notch already plays its chime; only add the system one when nobody would hear that.
        if away, settings.playsSounds { content.sound = .default }

        let key = taskID?.uuidString ?? event?.id ?? alert.id.uuidString
        let request = UNNotificationRequest(identifier: NotificationID.make(kind: alert.kind, key: key), content: content, trigger: nil)
        let timeSensitive = NotificationPolicyLogic.isTimeSensitive(alert.kind)
        Task {
            let notificationSettings = await center.notificationSettings()
            guard notificationSettings.authorizationStatus == .authorized || notificationSettings.authorizationStatus == .provisional else { return }
            if timeSensitive, notificationSettings.timeSensitiveSetting == .enabled {
                content.interruptionLevel = .timeSensitive
            }
            try? await center.add(request)
        }
    }

    private func dueTask(titled title: String) -> TaskItem? {
        let now = Date()
        return planner.tasks
            .filter { $0.isOpen && $0.title == title && ($0.due ?? .distantFuture) <= now }
            .max { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
    }

    private func upcomingEvent(titled title: String) -> AgendaEvent? {
        let now = Date().addingTimeInterval(-60)
        return agenda.events.filter { $0.title == title && !$0.isAllDay && $0.start > now }.min { $0.start < $1.start }
    }

    // MARK: Presence

    private func currentPresence() -> PresenceContext {
        var context = presence
        context.fullScreenOnNotchDisplay = Self.otherAppIsFullScreenOnNotchDisplay()
        return context
    }

    private func observePresence() {
        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ change: @escaping @MainActor (SystemNotifier) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { change(self) } }
            }
            observers.append((center, token))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.presence.screenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.presence.screenLocked = false }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.presence.displaysAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.presence.displaysAsleep = false; $0.markJustWoke() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.presence.displaysAsleep = false; $0.markJustWoke() }
        observe(.default, NSApplication.didBecomeActiveNotification) { notifier in Task { await notifier.refreshAuthorization() } }
    }

    private func markJustWoke() {
        presence.justWoke = true
        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled else { return }
            self?.presence.justWoke = false
        }
    }

    /// Another app has a window covering the whole notch display (full-screen app or Space).
    private static func otherAppIsFullScreenOnNotchDisplay() -> Bool {
        guard let screen = NotchGeometry.notchedScreen,
              let primaryHeight = NSScreen.screens.first?.frame.height,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let frame = screen.frame
        let cgOrigin = CGPoint(x: frame.minX, y: primaryHeight - frame.maxY)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }
            if abs(bounds.minX - cgOrigin.x) < 1, abs(bounds.minY - cgOrigin.y) < 1,
               abs(bounds.width - frame.width) < 1, abs(bounds.height - frame.height) < 1 {
                return true
            }
        }
        return false
    }

    // MARK: Keeping delivered notifications fresh

    private func observeState() {
        withObservationTracking {
            _ = focus.awaitingDecision
            _ = focus.isActive
            _ = focus.isPaused
            _ = planner.tasks
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.stateChanged()
                self?.observeState()
            }
        }
    }

    private func stateChanged() {
        if focus.isActive, !wasFocusActive, settings.systemNotifications != .off { requestAuthorizationIfNeeded() }
        wasFocusActive = focus.isActive
        guard isAvailable else { return }
        let now = Date()
        let snapshot = NotificationSnapshot(
            awaitingCheckIn: focus.awaitingDecision,
            focusActive: focus.isActive,
            focusPaused: focus.isPaused,
            dueTaskIDs: Set(planner.tasks.filter { $0.isOpen && $0.hasTime && ($0.due ?? .distantFuture) <= now }.map(\.id))
        )
        center.getDeliveredNotifications { delivered in
            let stale = delivered.map(\.request.identifier).filter { NotificationStaleness.isStale(identifier: $0, in: snapshot) }
            guard !stale.isEmpty else { return }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: stale)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        var info: [String: String] = [:]
        for (key, value) in response.notification.request.content.userInfo {
            if let key = key as? String, let value = value as? String { info[key] = value }
        }
        let command = NotificationCommand.from(actionID: action, userInfo: info)
        await MainActor.run { self.run(command) }
    }

    func run(_ command: NotificationCommand) {
        switch command {
        case .open: notch.open()
        case .extend(let minutes): if focus.awaitingDecision { focus.extend(minutes: minutes) }
        case .breakThenContinue: if focus.awaitingDecision { focus.breakThenContinue() }
        case .finishTask: if focus.awaitingDecision { focus.finishTask() }
        case .startNextFocus: if !focus.isActive { focus.startNextFocus() }
        case .startBreak: if !focus.isActive { focus.startBreak() }
        case .resume: focus.resume()
        case .snoozeTask(let id, let minutes):
            if var task = planner.task(id), task.isOpen {
                task.due = Date().addingTimeInterval(TimeInterval(minutes * 60))
                task.hasTime = true
                planner.update(task)
            }
        case .toggleTask(let id): if planner.task(id)?.isOpen == true { planner.toggle(id) }
        case .join(let url): NSWorkspace.shared.open(url)
        case .none: break
        }
    }
}
