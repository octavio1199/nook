import AppKit
import SwiftUI

struct WorkspaceView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WorkspaceState.self) private var workspace
    @Environment(NotchInteraction.self) private var notch
    @Environment(PlannerStore.self) private var planner
    @Environment(FocusTimer.self) private var focus

    static let spacing: CGFloat = 10
    static let sideWidth: CGFloat = 230

    var body: some View {
        GeometryReader { proxy in
            // Tasks and Notepad share what the right column leaves; the divider sits in their gap.
            let available = max(proxy.size.width - Self.sideWidth - Self.spacing * 2, 0)
            let tasksWidth = workspace.tasksWidth(available: available)
            HStack(alignment: .top, spacing: 0) {
                TasksColumn()
                    .frame(width: tasksWidth)
                ColumnDivider(width: Self.spacing, tasksWidth: tasksWidth, available: available)
                NotesColumn()
                    .frame(maxWidth: .infinity)
                VStack(spacing: Self.spacing) {
                    if settings.showsAgenda { AgendaCard() }
                    FocusCard()
                }
                .frame(width: Self.sideWidth)
                .padding(.leading, Self.spacing)
            }
        }
        .overlay { TaskComposerOverlay() }
        .overlay { FocusPickerOverlay() }
        .onAppear {
            notch.onEscape = { [workspace] in workspace.dismissOverlayIfOpen() }
            notch.keyInterceptor = { [workspace, planner, focus, settings] event in
                PanelOverlayKeys.handle(event, workspace: workspace, planner: planner, focus: focus, settings: settings)
            }
        }
        .onDisappear {
            notch.onEscape = nil
            notch.keyInterceptor = nil
        }
    }
}

/// Drag to trade width between Tasks and Notepad; double-click for an even split.
private struct ColumnDivider: View {
    let width: CGFloat
    let tasksWidth: CGFloat
    let available: CGFloat
    @Environment(WorkspaceState.self) private var workspace
    @LocalState private var hovering = false
    @LocalState private var dragStart: CGFloat?

    var body: some View {
        let active = hovering || dragStart != nil
        Capsule()
            .fill(Color.white.opacity(active ? 0.28 : 0))
            .frame(width: 3)
            .padding(.vertical, 18)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? tasksWidth
                        if dragStart == nil { dragStart = start }
                        workspace.setTasksWidth(start + value.translation.width, available: available)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                withAnimation(Motion.navigate) { workspace.resetColumns() }
            })
            .animation(Motion.hover, value: active)
            .help("Drag to resize · double-click to reset")
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
