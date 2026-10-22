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
            let window = NSWindow(contentViewController: host)
            window.title = "Nook Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 520, height: 420))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralPage().tabItem { Label("General", systemImage: "gearshape") }
            AppearancePage().tabItem { Label("Appearance", systemImage: "paintbrush") }
            FocusPage().tabItem { Label("Focus", systemImage: "timer") }
            KeyboardPage().tabItem { Label("Keyboard", systemImage: "keyboard") }
            NotificationsPage().tabItem { Label("Notifications", systemImage: "bell") }
            CalendarPage().tabItem { Label("Calendar", systemImage: "calendar") }
            DataPage().tabItem { Label("Data", systemImage: "externaldrive") }
            AboutPage().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
    }
}

private final class LoginState: ObservableObject {
    @Published var enabled = false
}

private final class MessageState: ObservableObject {
    @Published var text: String?
}

private struct GeneralPage: View {
    @Environment(AppSettings.self) private var settings
    @StateObject private var login = LoginState()

    var body: some View {
        @Bindable var settings = settings
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { login.enabled },
                set: { settings.launchAtLogin = $0; login.enabled = settings.launchAtLogin }
            ))
            Picker("Open the notch on", selection: $settings.openMode) {
                ForEach(OpenMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Show agenda in the workspace", isOn: $settings.showsAgenda)
            Picker("Workday starts", selection: Binding(
                get: { settings.workdayStart },
                set: { settings.workdayStart = $0; if settings.workdayEnd <= $0 { settings.workdayEnd = min($0 + 60, 1440) } }
            )) {
                ForEach(Array(stride(from: 0, to: 1380, by: 30)), id: \.self) { Text(Self.clock($0)).tag($0) }
            }
            Picker("Workday ends", selection: $settings.workdayEnd) {
                ForEach(Array(stride(from: settings.workdayStart + 30, through: 1440, by: 30)), id: \.self) { Text(Self.clock($0)).tag($0) }
            }
            Text("Plan my day only fills time inside your working hours.")
                .font(.callout).foregroundStyle(.secondary)
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
            Picker("Panel style", selection: $settings.panelStyle) {
                ForEach(PanelStyle.allCases) { Text($0.title).tag($0) }
            }
            Text("Liquid Glass needs macOS 26 or later. On earlier systems, or with Reduce Transparency on, Nook uses the solid style.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct FocusPage: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Picker("Default preset", selection: $settings.focusPresetID) {
                ForEach(FocusPreset.all) { Text("\($0.name) · \($0.focus)/\($0.shortBreak)").tag($0.id) }
            }
            Toggle("Auto-start breaks", isOn: $settings.autoStartBreaks)
            Toggle("Play sounds", isOn: $settings.playsSounds)
            Toggle("Haptic feedback", isOn: $settings.haptics)
            Toggle("Live activity in the notch", isOn: $settings.showsLiveActivity)
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
            Picker("Show macOS notifications", selection: $settings.systemNotifications) {
                ForEach(SystemNotificationPolicy.allCases) { Text($0.title).tag($0) }
            }
            Text(settings.systemNotifications == .whenAway
                ? "Only when the notch can't be seen: screen locked, display asleep, another app full screen, or right after waking."
                : settings.systemNotifications == .always
                    ? "Every alert also appears as a macOS notification."
                    : "Alerts only appear in the notch.")
                .font(.callout).foregroundStyle(.secondary)
            LabeledContent("Permission") {
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
            LabeledContent("Access") {
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
            Picker("Alert before events", selection: $settings.eventAlertMinutes) {
                ForEach([1, 5, 10, 15], id: \.self) { Text("\($0) min").tag($0) }
            }
            Text("Nook only reads your calendar. It never creates or changes events.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct DataPage: View {
    @Environment(PlannerStore.self) private var planner
    @StateObject private var status = MessageState()

    var body: some View {
        Form {
            Text("Tasks, notes and focus history live in a local JSON file. Nothing leaves your Mac.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Reveal planner.json in Finder") {
                let url = PlannerStore.defaultURL
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    NSWorkspace.shared.open(url.deletingLastPathComponent())
                }
            }
            Button("Export JSON…", action: export)
            if let message = status.text { Text(message).font(.callout).foregroundStyle(.secondary) }
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
                    .font(.callout).foregroundStyle(.secondary)
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
