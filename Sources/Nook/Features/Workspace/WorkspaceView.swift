import AppKit
import SwiftUI

struct WorkspaceView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 10) {
            WorkspaceHeader(openSettings: openSettings.callAsFunction)
            HStack(alignment: .top, spacing: 10) {
                TasksColumn()
                    .frame(maxWidth: .infinity)
                NotesColumn()
                    .frame(maxWidth: .infinity)
                VStack(spacing: 10) {
                    if settings.showsAgenda { AgendaCard() }
                    FocusCard()
                }
                .frame(width: 230)
            }
        }
    }
}

private struct WorkspaceHeader: View {
    @Environment(NotchInteraction.self) private var notch
    var openSettings: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 8) {
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(Typography.title)
                    .foregroundStyle(Color.textPrimary)
                Text(Self.greeting(for: context.date))
                    .font(Typography.caption)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Button {
                    notch.isPinned.toggle()
                } label: {
                    Image(systemName: notch.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12))
                        .foregroundStyle(notch.isPinned ? Color.accent : Color.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(notch.isPinned ? "Unpin" : "Keep open")
                Button(action: openSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Quit Nook")
            }
        }
    }

    static func greeting(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}
