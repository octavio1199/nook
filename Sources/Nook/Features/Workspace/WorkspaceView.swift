import AppKit
import SwiftUI

struct WorkspaceView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 10) {
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
        .overlay { TaskComposerOverlay() }
    }
}

/// The open panel's header lives in the strip beside the camera, which is otherwise empty:
/// date on the left of the notch, pin / settings / quit on the right.
struct NotchHeaderBar: View {
    @Environment(NotchInteraction.self) private var notch
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let notchWidth = notch.geometry.notchSize.width
        HStack(spacing: 0) {
            TimelineView(.everyMinute) { context in
                HStack(spacing: 7) {
                    Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(Typography.title)
                        .foregroundStyle(Color.textPrimary)
                    Text(Self.greeting(for: context.date))
                        .font(Typography.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Keep the camera area clear (plus a little breathing room).
            Color.clear.frame(width: notch.geometry.hasNotch ? notchWidth + 24 : 24)
            HStack(spacing: 2) {
                icon(notch.isPinned ? "pin.fill" : "pin", tint: notch.isPinned ? .accent : .textSecondary,
                     help: notch.isPinned ? "Unpin" : "Keep open") { notch.isPinned.toggle() }
                icon("gearshape.fill", help: "Settings") { openSettings() }
                icon("power", help: "Quit Nook") { NSApp.terminate(nil) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: notch.geometry.notchSize.height)
    }

    private func icon(_ symbol: String, tint: Color = .textSecondary, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    static func greeting(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}
