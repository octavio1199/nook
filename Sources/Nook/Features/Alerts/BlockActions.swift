import SwiftUI

/// Start / Snooze / Skip for a block that is about to begin (or just did).
struct BlockActions: View {
    let alert: NotchAlert
    @Environment(BlockWatcher.self) private var blocks

    var body: some View {
        if let id = alert.taskID {
            HStack(spacing: 6) {
                pill(alert.kind == .blockSoon ? "Start now" : "Start focus", filled: true) { blocks.startFocus(id) }
                pill("Snooze \(blocks.snoozeMinutes) min", filled: false) { blocks.snooze(id) }
                pill("Skip", filled: false) { blocks.skip(id) }
            }
        }
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(filled ? Color.white : alert.tint)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(Capsule().fill(filled ? alert.tint : alert.tint.opacity(0.18)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
