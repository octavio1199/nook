import SwiftUI

struct PeekView: View {
    let alert: NotchAlert
    let onTap: () -> Void

    @Environment(FocusTimer.self) private var focus
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: alert.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(alert.tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(alert.tint.opacity(0.18)))
            VStack(alignment: .leading, spacing: 1) {
                Text(alert.headline)
                    .font(Typography.title)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if let detail = alert.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let action {
                Button(action: action.run) {
                    Text(action.title)
                        .font(Typography.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Capsule().fill(alert.tint))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private struct PillAction {
        var title: String
        var run: () -> Void
    }

    private var preset: FocusPreset { .with(id: settings.focusPresetID) }

    private var action: PillAction? {
        switch alert.kind {
        case .focusFinished:
            if focus.isActive {
                return PillAction(title: "Done") { focus.stop() }
            }
            // Plain countdowns ("Time's up") have no follow-up.
            guard alert.symbol != "timer" else { return nil }
            return PillAction(title: "Start break") { focus.startBreak() }
        case .breakFinished:
            return PillAction(title: "Start focus") { focus.startNextFocus() }
        default:
            return nil
        }
    }
}
