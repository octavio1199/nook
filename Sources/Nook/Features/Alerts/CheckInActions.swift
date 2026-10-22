import SwiftUI

/// The three answers to "time's up on this task": +5 min, break then continue, done.
struct CheckInActions: View {
    enum Style { case compact, large }

    var style: Style
    @Environment(FocusTimer.self) private var focus
    @Environment(PlannerStore.self) private var planner
    @Environment(BlockWatcher.self) private var blocks
    @LocalState private var pushed = false

    /// Set when this task's block is over and later blocks exist: the "Push rest" case.
    private var late: (end: Date, overrun: TimeInterval)? {
        guard !pushed, let task = planner.task(focus.taskID) else { return nil }
        return blocks.overrun(for: task)
    }

    var body: some View {
        switch style {
        case .compact:
            HStack(spacing: 6) {
                pill("+5 min", symbol: nil, tint: .focus, filled: true) { withAnimation(Motion.navigate) { focus.extend(minutes: 5) } }
                pill("Break", symbol: "cup.and.saucer.fill", tint: .rest, filled: false) { withAnimation(Motion.navigate) { focus.breakThenContinue() } }
                pill("Done", symbol: "checkmark", tint: .rest, filled: true, dark: true) { withAnimation(Motion.navigate) { focus.finishTask() } }
                if let late {
                    pill("Push rest", symbol: nil, tint: .accent, filled: false) { push(late) }
                        .help(pushHelp(late))
                }
            }
        case .large:
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    big("+5 min", symbol: "plus", tint: .focus, filled: true) { withAnimation(Motion.navigate) { focus.extend(minutes: 5) } }
                    big("Break", symbol: "cup.and.saucer.fill", tint: .rest, filled: false) { withAnimation(Motion.navigate) { focus.breakThenContinue() } }
                }
                big("Finished", symbol: "checkmark", tint: .rest, filled: true, dark: true) { withAnimation(Motion.navigate) { focus.finishTask() } }
                if let late {
                    big("Push rest of day", symbol: "arrow.down.to.line", tint: .accent, filled: false) { push(late) }
                        .help(pushHelp(late))
                        .transition(.opacity)
                }
            }
        }
    }

    private func push(_ late: (end: Date, overrun: TimeInterval)) {
        withAnimation(Motion.navigate) {
            blocks.pushRest(from: late.end, overrun: late.overrun)
            pushed = true
        }
    }

    private func pushHelp(_ late: (end: Date, overrun: TimeInterval)) -> String {
        "Shift the rest of today's blocks by \(DayPlanner.roundedOverrun(late.overrun)) min"
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
