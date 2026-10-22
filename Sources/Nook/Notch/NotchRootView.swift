// Adapted from Pullo (MIT, (c) 2026 Gabriel Jordan)
import SwiftUI

struct NotchRootView: View {
    @Environment(NotchInteraction.self) private var notch
    @Environment(FocusTimer.self) private var focus

    var body: some View {
        let state = notch.state
        let size = notch.layout.size(for: state)
        let radii = notch.layout.radii(for: state)
        let shape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)

        VStack(spacing: 10) {
            panel(state: state, size: size, radii: radii, shape: shape)
            if state == .open {
                AreaSwitcher()
                    .transition(.opacity.combined(with: .offset(y: -10)))
            }
        }
        .opacity(state == .closed && !notch.geometry.hasNotch ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.peek, value: notch.liveActivity)
    }

    private func panel(state: NotchState, size: CGSize, radii: (top: CGFloat, bottom: CGFloat), shape: NotchShape) -> some View {
        VStack(spacing: 0) {
            if state == .closed, let live = notch.liveActivity {
                LiveActivityWings(activity: live, notchWidth: notch.geometry.notchSize.width, height: notch.geometry.notchSize.height)
                    .transition(.opacity)
            } else {
                Color.clear.frame(height: notch.geometry.notchSize.height)
            }
            if state == .peek, let alert = notch.peekAlert {
                PeekView(alert: alert) { notch.tapPeek(alert) }
                    .id(alert.id)
                    .transition(.reveal(delay: 0.08))
            }
            if state == .open {
                ExpandedView()
                    .transition(.reveal(delay: 0.07))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .padding(.horizontal, radii.top)
        .background { NotchBackground(state: state, shape: shape, notchWidth: notch.geometry.notchSize.width, height: size.height) }
        .clipShape(shape)
        .compositingGroup()
        .shadow(color: shadowColor(for: state), radius: state == .open ? 26 : 14, y: state == .closed ? 2 : 8)
    }
}

extension NotchRootView {
    /// Black drop shadow when open; a soft green glow around the closed notch during a break.
    fileprivate func shadowColor(for state: NotchState) -> Color {
        if state == .closed, focus.phase?.isBreak == true, notch.liveActivity == .focus { return BreakGreen.glow }
        return .black.opacity(state == .closed ? 0 : 0.55)
    }
}

struct AreaSwitcher: View {
    @Environment(NotchInteraction.self) private var notch

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PanelArea.allCases) { area in
                Button {
                    notch.show(area)
                } label: {
                    Label(area.title, systemImage: area.symbol)
                        .font(Typography.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(notch.area == area ? Color.textPrimary : Color.textSecondary)
                        .background(Capsule().fill(notch.area == area ? Color.surfaceRaised : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(.black))
        .overlay(Capsule().strokeBorder(Color.hairline))
    }
}

struct ExpandedView: View {
    @Environment(NotchInteraction.self) private var notch

    var body: some View {
        Group {
            switch notch.area {
            case .workspace: WorkspaceView()
            case .insights: InsightsView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
