import SwiftUI

/// A task's checklist: progress bar, rows (check, rename, move, delete on hover) and an add field.
/// Every change goes through the store, so ⌘Z undoes it.
struct SubtaskList: View {
    let taskID: UUID
    /// Larger rows for the Focus tab.
    var roomy = false
    @Environment(PlannerStore.self) private var planner
    @LocalState private var newTitle = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        let task = planner.task(taskID)
        let subtasks = task?.subtasks ?? []
        VStack(alignment: .leading, spacing: roomy ? 6 : 4) {
            if let progress = task?.subtaskProgress {
                ProgressHeader(done: progress.done, total: progress.total)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: roomy ? 2 : 0) {
                    ForEach(Array(subtasks.enumerated()), id: \.element.id) { index, subtask in
                        SubtaskRow(
                            subtask: subtask, taskID: taskID, roomy: roomy,
                            isFirst: index == 0, isLast: index == subtasks.count - 1
                        )
                    }
                }
            }
            // In the task detail the list stays short so the notes keep their room.
            .frame(maxHeight: roomy ? .infinity : nil)
            .frame(height: roomy ? nil : CGFloat(min(subtasks.count, 2)) * 22)
            addField
        }
    }

    private var addField: some View {
        HStack(spacing: 7) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 15)
            TextField("", text: $newTitle, prompt: Text("Add a sub-task").foregroundStyle(Color.textTertiary))
                .textFieldStyle(.plain)
                .font(roomy ? Typography.body : Typography.caption)
                .foregroundStyle(Color.textPrimary)
                .focused($addFocused)
                .onSubmit {
                    withAnimation(Motion.navigate) { planner.addSubtask(newTitle, to: taskID) }
                    newTitle = ""
                    DispatchQueue.main.async { addFocused = true }
                }
        }
        .padding(.horizontal, 6)
        .frame(height: roomy ? 28 : 24)
    }
}

private struct ProgressHeader: View {
    let done: Int
    let total: Int

    var body: some View {
        let fraction = total > 0 ? Double(done) / Double(total) : 0
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(done == total ? Color.rest : Color.focus).frame(width: proxy.size.width * fraction)
                    }
                }
            Text("\(done)/\(total)")
                .font(Typography.micro)
                .monospacedDigit()
                .foregroundStyle(done == total ? Color.rest : Color.textSecondary)
        }
        .animation(Motion.navigate, value: fraction)
    }
}

private struct SubtaskRow: View {
    let subtask: Subtask
    let taskID: UUID
    let roomy: Bool
    let isFirst: Bool
    let isLast: Bool
    @Environment(PlannerStore.self) private var planner
    @LocalState private var hovering = false
    @LocalState private var draft = ""
    @LocalState private var editing = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Button {
                withAnimation(Motion.navigate) { planner.toggleSubtask(subtask.id, in: taskID) }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(subtask.done ? Color.rest : Color.textTertiary, lineWidth: 1.3)
                    if subtask.done {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.rest)
                        Image(systemName: "checkmark").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(.black)
                    }
                }
                .frame(width: 13, height: 13)
                .frame(width: 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(roomy ? Typography.body : Typography.caption)
                    .foregroundStyle(Color.textPrimary)
                    .focused($fieldFocused)
                    .onSubmit(commit)
                    .onChange(of: fieldFocused) { if !fieldFocused { commit() } }
            } else {
                Text(subtask.title)
                    .font(roomy ? Typography.body : Typography.caption)
                    .foregroundStyle(subtask.done ? Color.textTertiary : Color.textPrimary)
                    .strikethrough(subtask.done, color: Color.textTertiary)
                    .lineLimit(roomy ? 2 : 1)
                    .onTapGesture(count: 2) {
                        draft = subtask.title
                        editing = true
                        DispatchQueue.main.async { fieldFocused = true }
                    }
                    .help("Double-click to rename")
            }
            Spacer(minLength: 4)
            if hovering && !editing {
                HStack(spacing: 2) {
                    iconButton("chevron.up", enabled: !isFirst, help: "Move up") { planner.moveSubtask(subtask.id, in: taskID, by: -1) }
                    iconButton("chevron.down", enabled: !isLast, help: "Move down") { planner.moveSubtask(subtask.id, in: taskID, by: 1) }
                    iconButton("xmark", enabled: true, help: "Delete (⌘Z to undo)") { planner.deleteSubtask(subtask.id, in: taskID) }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 6)
        .frame(minHeight: roomy ? 28 : 22)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Color.white.opacity(0.05) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }

    private func commit() {
        guard editing else { return }
        editing = false
        planner.renameSubtask(subtask.id, in: taskID, to: draft)
    }

    private func iconButton(_ symbol: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Motion.navigate, action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(enabled ? Color.textSecondary : Color.textTertiary.opacity(0.5))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}
