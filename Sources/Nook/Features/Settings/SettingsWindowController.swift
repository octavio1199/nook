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
            LabeledContent("Global hotkey") {
                Text("⌥⌘N").font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { login.enabled = settings.launchAtLogin }
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
            Image(systemName: "rectangle.topthird.inset.filled").font(.system(size: 40)).foregroundStyle(.tint)
            Text("Nook").font(.title.bold())
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("A free, open-source notch planner. MIT licensed.").multilineTextAlignment(.center)
            Text("Notch shell adapted from Pullo by Gabriel Jordan (MIT)")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
