import SwiftUI

/// Drives the compact "Archived “Title” · Undo" toast at the bottom of the Tasks column.
/// Hides itself after a few seconds and whenever the planner's undo manager undoes something (⌘Z too).
final class UndoToaster: ObservableObject {
    struct Toast: Equatable, Identifiable {
        let id = UUID()
        var message: String
        var symbol: String
    }

    @Published private(set) var toast: Toast?
    private var hideTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private weak var observed: UndoManager?

    /// Starts listening for undo on `manager`; safe to call repeatedly.
    func observe(_ manager: UndoManager) {
        guard observed !== manager else { return }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observed = manager
        observer = NotificationCenter.default.addObserver(forName: .NSUndoManagerDidUndoChange, object: manager, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    func show(_ verb: String, _ title: String? = nil, symbol: String) {
        let message = title.map { "\(verb) “\($0)”" } ?? verb
        let next = Toast(message: message, symbol: symbol)
        hideTask?.cancel()
        withAnimation(Motion.pop) { toast = next }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        hideTask?.cancel()
        guard toast != nil else { return }
        withAnimation(Motion.fade) { toast = nil }
    }

    func undo(_ manager: UndoManager) {
        manager.undo()
        dismiss()
    }
}

struct UndoToastView: View {
    let toast: UndoToaster.Toast
    let onUndo: () -> Void
    @LocalState private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: toast.symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            Text(toast.message)
                .font(Typography.caption)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Button(action: onUndo) {
                Text("Undo")
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accent.opacity(hovering ? 0.22 : 0.12)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .help("Undo (⌘Z)")
        }
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.surfaceRaised)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        )
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.hairline))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

enum ArchiveFormat {
    /// "just now", "5m ago", "3h ago", "2d ago".
    static func ago(_ date: Date, now: Date) -> String {
        let s = max(0, now.timeIntervalSince(date))
        switch s {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(s / 60))m ago"
        case ..<86_400: return "\(Int(s / 3600))h ago"
        default: return "\(Int(s / 86_400))d ago"
        }
    }
}
