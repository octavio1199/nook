import SwiftUI

/// The three answers to "time's up on this task": +5 min, break then continue, done.
struct CheckInActions: View {
    enum Style { case compact, large }

    var style: Style
    @Environment(FocusTimer.self) private var focus

    var body: some View {
        switch style {
        case .compact:
            HStack(spacing: 6) {
                pill("+5 min", symbol: nil, tint: .focus, filled: true) { withAnimation(Motion.navigate) { focus.extend(minutes: 5) } }
                pill("Break", symbol: "cup.and.saucer.fill", tint: .rest, filled: false) { withAnimation(Motion.navigate) { focus.breakThenContinue() } }
                pill("Done", symbol: "checkmark", tint: .rest, filled: true, dark: true) { withAnimation(Motion.navigate) { focus.finishTask() } }
            }
        case .large:
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    big("+5 min", symbol: "plus", tint: .focus, filled: true) { withAnimation(Motion.navigate) { focus.extend(minutes: 5) } }
                    big("Break", symbol: "cup.and.saucer.fill", tint: .rest, filled: false) { withAnimation(Motion.navigate) { focus.breakThenContinue() } }
                }
                big("Finished", symbol: "checkmark", tint: .rest, filled: true, dark: true) { withAnimation(Motion.navigate) { focus.finishTask() } }
            }
        }
    }

    private func pill(_ title: String, symbol: String?, tint: Color, filled: Bool, dark: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
                Text(title).font(Typography.caption)
            }
            .foregroundStyle(filled ? (dark ? Color.black.opacity(0.8) : Color.white) : tint)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Capsule().fill(filled ? tint : tint.opacity(0.18)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func big(_ title: String, symbol: String, tint: Color, filled: Bool, dark: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                Text(title).font(Typography.title)
            }
            .foregroundStyle(filled ? (dark ? Color.black.opacity(0.8) : Color.white) : tint)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(Capsule().fill(filled ? tint : tint.opacity(0.18)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
