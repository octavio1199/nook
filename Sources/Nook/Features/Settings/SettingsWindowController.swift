import AppKit
import SwiftUI

final class SettingsWindowController {
    private unowned let app: AppDependencies
    private var window: NSWindow?

    init(app: AppDependencies) {
        self.app = app
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: app.inject(into: SettingsView()))
            host.sizingOptions = []
            let window = NSWindow(contentViewController: host)
            window.title = "Nook Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.contentMinSize = SettingsView.minSize
            window.setContentSize(SettingsView.minSize)
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("NookSettings")
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, focus, keyboard, notifications, calendar, data, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .focus: "Focus"
        case .keyboard: "Keyboard"
        case .notifications: "Notifications"
        case .calendar: "Calendar"
        case .data: "Data"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.fill"
        case .focus: "timer"
        case .keyboard: "keyboard.fill"
        case .notifications: "bell.badge.fill"
        case .calendar: "calendar"
        case .data: "externaldrive.fill"
        case .about: "info.circle.fill"
        }
    }

    /// Icon tile color, as in System Settings.
    var tint: Color {
        switch self {
        case .general: .gray
        case .appearance: .blue
        case .focus: .orange
        case .keyboard: .gray
        case .notifications: .red
        case .calendar: .red
        case .data: .indigo
        case .about: .gray
        }
    }
}

/// System Settings layout: sections in a sidebar, the page on the right. Remembers the last section.
struct SettingsView: View {
    static let minSize = NSSize(width: 720, height: 520)
    /// Screenshots pin a section without touching the stored one.
    var fixedSection: SettingsSection?
    @AppStorage("settingsSection") private var stored = SettingsSection.general.rawValue

    private var section: SettingsSection {
        fixedSection ?? SettingsSection(rawValue: stored) ?? .general
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding(get: { section }, set: { if let new = $0 { stored = new.rawValue } })) {
                ForEach(SettingsSection.allCases) { item in
                    SidebarRow(section: item).tag(item)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 200)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(section.title)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 28)
                    .padding(.top, 18)
                    .padding(.bottom, 2)
                page(section)
                    // One background for the title and the page (grouped forms draw their own otherwise).
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: Self.minSize.width, minHeight: Self.minSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func page(_ section: SettingsSection) -> some View {
        switch section {
        case .general: GeneralPage()
        case .appearance: AppearancePage()
        case .focus: FocusPage()
        case .keyboard: KeyboardPage()
        case .notifications: NotificationsPage()
        case .calendar: CalendarPage()
        case .data: DataPage()
        case .about: AboutPage()
        }
    }
}

extension Text {
    /// Explanations under a setting: secondary, left-aligned like System Settings.
    func settingsFootnote() -> some View {
        font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebarRow: View {
    let section: SettingsSection

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: section.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(section.tint.gradient))
            Text(section.title)
        }
        .padding(.vertical, 2)
    }
}

private final class LoginState: ObservableObject {
    @Published var enabled = false
}

private final class MessageState: ObservableObject {
    @Published var text: String?
}

struct GeneralPage: View {
    @Environment(AppSettings.self) private var settings
    @StateObject private var login = LoginState()

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { login.enabled },
                    set: { settings.launchAtLogin = $0; login.enabled = settings.launchAtLogin }
                ))
            }
            Section("Notch") {
                Picker("Open the notch on", selection: $settings.openMode) {
                    ForEach(OpenMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                DisplayPicker()
                Toggle("Show agenda in the workspace", isOn: $settings.showsAgenda)
            }
            Section {
            Picker("Workday starts", selection: Binding(
                get: { settings.workdayStart },
                set: { settings.workdayStart = $0; if settings.workdayEnd <= $0 { settings.workdayEnd = min($0 + 60, 1440) } }
            )) {
                ForEach(Array(stride(from: 0, to: 1380, by: 30)), id: \.self) { Text(Self.clock($0)).tag($0) }
            }
            Picker("Workday ends", selection: $settings.workdayEnd) {
                ForEach(Array(stride(from: settings.workdayStart + 30, through: 1440, by: 30)), id: \.self) { Text(Self.clock($0)).tag($0) }
            }
            } header: {
                Text("Working hours")
            } footer: {
                Text("Plan my day only fills time inside your working hours.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .onAppear { login.enabled = settings.launchAtLogin }
    }

    private static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

private struct AppearancePage: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Panel style", selection: $settings.panelStyle) {
                    ForEach(PanelStyle.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Panel")
            } footer: {
                Text("Liquid Glass needs macOS 26 or later. On earlier systems, or with Reduce Transparency on, Nook uses the solid style.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }
}

private struct FocusPage: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Timer") {
                Picker("Default preset", selection: $settings.focusPresetID) {
                    ForEach(FocusPreset.all) { Text("\($0.name) · \($0.focus)/\($0.shortBreak)").tag($0.id) }
                }
                Toggle("Auto-start breaks", isOn: $settings.autoStartBreaks)
                Toggle("Switch to the Focus tab when a focus starts", isOn: $settings.autoShowsFocusTab)
            }
            Section("Feedback") {
                Toggle("Play sounds", isOn: $settings.playsSounds)
                Toggle("Haptic feedback", isOn: $settings.haptics)
            }
            Section {
                Toggle("Live activity in the notch", isOn: $settings.showsLiveActivity)
            } header: {
                Text("Notch")
            } footer: {
                Text("While a focus, block or event is live, the closed notch shows it beside the camera.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }
}

private struct NotificationsPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SystemNotifier.self) private var notifier

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Show macOS notifications", selection: $settings.systemNotifications) {
                    ForEach(SystemNotificationPolicy.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("macOS notifications")
            } footer: {
                Text(settings.systemNotifications == .whenAway
                    ? "Only when the notch can't be seen: screen locked, display asleep, another app full screen, or right after waking."
                    : settings.systemNotifications == .always
                        ? "Every alert also appears as a macOS notification."
                        : "Alerts only appear in the notch.")
                    .settingsFootnote()
            }
            Section("Permission") {
            LabeledContent("Status") {
                switch notifier.authorization {
                case .authorized: Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .denied: Label("Blocked in System Settings", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                case .notDetermined: Label("Not asked yet", systemImage: "circle.dashed").foregroundStyle(.secondary)
                case .unknown: Text("Checking…").foregroundStyle(.secondary)
                }
            }
            switch notifier.authorization {
            case .notDetermined, .unknown: Button("Allow notifications", action: notifier.requestAuthorizationIfNeeded)
            case .denied: Button("Open System Settings", action: notifier.openSystemSettings)
            case .authorized: EmptyView()
            }
            Button("Send test notification", action: notifier.sendTest)
            }
        }
        .formStyle(.grouped)
        .onAppear { Task { await notifier.refreshAuthorization() } }
        .onChange(of: settings.systemNotifications) { _, policy in
            if policy != .off { notifier.requestAuthorizationIfNeeded() }
        }
    }
}

private struct CalendarPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AgendaModel.self) private var agenda

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Access") {
            LabeledContent("Calendar") {
                switch agenda.access {
                case .granted: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .denied: Label("Denied", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                case .unknown: Label("Not connected", systemImage: "circle.dashed").foregroundStyle(.secondary)
                }
            }
            switch agenda.access {
            case .unknown: Button("Connect Calendar", action: agenda.requestAccess)
            case .denied: Button("Open Privacy Settings", action: agenda.openPrivacySettings)
            case .granted: EmptyView()
            }
            }
            Section {
                Picker("Alert before events", selection: $settings.eventAlertMinutes) {
                    ForEach([1, 5, 10, 15], id: \.self) { Text("\($0) min").tag($0) }
                }
            } header: {
                Text("Alerts")
            } footer: {
                Text("Nook only reads your calendar. It never creates or changes events.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }
}

private struct DataPage: View {
    @Environment(PlannerStore.self) private var planner
    @StateObject private var status = MessageState()

    var body: some View {
        Form {
            Section {
            Button("Reveal planner.json in Finder") {
                let url = PlannerStore.defaultURL
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    NSWorkspace.shared.open(url.deletingLastPathComponent())
                }
            }
            Button("Export JSON…", action: export)
            if let message = status.text { Text(message).settingsFootnote() }
            } header: {
                Text("Your data")
            } footer: {
                Text("Tasks, notes and focus history live in a local JSON file. Nothing leaves your Mac. Daily backups are kept in the Backups folder next to it.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "nook-export.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try planner.exportJSON().write(to: url, options: .atomic)
            status.text = "Exported to \(url.lastPathComponent)"
        } catch {
            status.text = "Export failed: \(error.localizedDescription)"
        }
    }
}

private struct AboutPage: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Nook").font(.title.bold())
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("A free, open-source notch planner.").multilineTextAlignment(.center)
            Text("Made by Octavio Rocha").font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("GitHub") {
                    if let url = URL(string: "https://github.com/octavio1199/nook") { NSWorkspace.shared.open(url) }
                }
                Button("Quit Nook") { NSApp.terminate(nil) }
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Keyboard

/// Records one key combination through a local key monitor while the Settings window is key.
private final class ShortcutRecorder: ObservableObject {
    @Published var recording: GlobalAction?
    @Published var message: String?
    private var monitor: Any?

    func start(_ action: GlobalAction, settings: AppSettings, hotKeys: HotKeyCenter) {
        stop(settings: settings, hotKeys: hotKeys)
        recording = action
        message = nil
        hotKeys.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.record(event, settings: settings, hotKeys: hotKeys) }
            return nil
        }
    }

    private func record(_ event: NSEvent, settings: AppSettings, hotKeys: HotKeyCenter) {
        guard let action = recording else { return }
        if Int(event.keyCode) == 53 { // esc
            stop(settings: settings, hotKeys: hotKeys)
            return
        }
        guard let shortcut = Shortcut(keyCode: Int(event.keyCode), flags: event.modifierFlags, characters: event.charactersIgnoringModifiers) else {
            message = "Use at least one of ⌘, ⌥ or ⌃."
            return
        }
        if let other = settings.setShortcut(shortcut, for: action) {
            message = "\(shortcut.symbols) is already “\(other.title)”."
            return
        }
        stop(settings: settings, hotKeys: hotKeys)
    }

    func stop(settings: AppSettings, hotKeys: HotKeyCenter) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording != nil {
            recording = nil
            hotKeys.resume(settings)
        }
    }
}

struct KeyboardPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HotKeyCenter.self) private var hotKeys
    @StateObject private var recorder = ShortcutRecorder()

    var body: some View {
        Form {
            Section {
                ForEach(GlobalAction.allCases) { action in
                    LabeledContent(action.title) {
                        HStack(spacing: 6) {
                            if hotKeys.unavailable.contains(action) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                    .help("Another app or macOS already uses this shortcut. Pick a different one.")
                            }
                            Button {
                                if recorder.recording == action {
                                    recorder.stop(settings: settings, hotKeys: hotKeys)
                                } else {
                                    recorder.start(action, settings: settings, hotKeys: hotKeys)
                                }
                            } label: {
                                Text(recorder.recording == action ? "Type a shortcut…" : settings.shortcut(for: action).symbols)
                                    .font(.system(.body, design: .rounded))
                                    .frame(minWidth: 96)
                            }
                            .help("Click, then press the new shortcut (esc cancels)")
                            Button {
                                settings.resetShortcut(for: action)
                                hotKeys.apply(settings)
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(.borderless)
                            .disabled(settings.shortcut(for: action) == action.defaultShortcut)
                            .help("Back to \(action.defaultShortcut.symbols)")
                        }
                    }
                }
                if let message = recorder.message {
                    Text(message).font(.callout).foregroundStyle(.orange)
                }
            } header: {
                Text("Anywhere")
            } footer: {
                Text("These work from any app, even when Nook is closed.")
                    .settingsFootnote()
            }
            Section("While the panel is open") {
                ForEach(PanelShortcuts.all, id: \.title) { item in
                    LabeledContent(item.title) {
                        Text(item.keys).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { recorder.stop(settings: settings, hotKeys: hotKeys) }
    }
}

// MARK: - Display

/// Settings › General › Show Nook on. Lists the connected displays, refreshed when they change.
private struct DisplayPicker: View {
    @Environment(AppSettings.self) private var settings
    @StateObject private var screens = ScreenList()

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 4) {
            Picker("Show Nook on", selection: $settings.displayChoice) {
                Text(automaticTitle).tag(DisplayChoice.automatic)
                Text("Main display (menu bar)").tag(DisplayChoice.main)
                Text("Active display").tag(DisplayChoice.activeDisplay)
                Divider()
                ForEach(screens.items, id: \.id) { screen in
                    Text(title(for: screen)).tag(DisplayChoice.display(screen.id))
                }
                if case .display(let id) = settings.displayChoice, !screens.items.contains(where: { $0.id == id }) {
                    Text("Saved display (not connected)").tag(settings.displayChoice)
                }
            }
            Text(footnote)
                .settingsFootnote()
        }
    }

    private var automaticTitle: String {
        screens.items.contains { $0.hasNotch } ? "Automatic (built-in display)" : "Automatic (main display)"
    }

    private func title(for screen: ScreenInfo) -> String {
        var extras: [String] = []
        if screen.hasNotch { extras.append("notch") }
        if screen.isMain { extras.append("menu bar") }
        return extras.isEmpty ? screen.name : "\(screen.name) (\(extras.joined(separator: ", ")))"
    }

    private var footnote: String {
        let shortcut = settings.shortcut(for: .moveHere).symbols
        switch settings.displayChoice {
        case .activeDisplay: return "Nook moves to the display you're working on (where you last clicked or switched apps) whenever it's closed."
        case .display(let id) where !screens.items.contains(where: { $0.id == id }):
            return "That display isn't connected, so Nook is on the automatic one until it comes back."
        default: return "Without a notch, Nook sits at the top center, under the menu bar. \(shortcut) moves it to the display under the mouse."
        }
    }
}

private final class ScreenList: ObservableObject {
    @Published var items: [ScreenInfo] = NSScreen.screens.map(\.info)
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.items = NSScreen.screens.map(\.info) }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
