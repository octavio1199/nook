import AppKit
import SwiftUI

/// "Start a focus": a keyboard-first task picker over the workspace (global shortcut).
/// Type to filter, ↑/↓ to choose, ↩ to start. A running focus is pointed at the chosen task instead.
enum FocusPicker {
    enum Item: Equatable, Identifiable {
        case noTask
        case task(TaskItem)

        var id: String {
            switch self {
            case .noTask: "none"
            case .task(let task): task.id.uuidString
            }
        }
    }

    /// Today's open tasks (plus "no task" while the query is empty). Typing also searches the
    /// upcoming tasks; every word must appear in the title or a tag.
    static func items(today: [TaskItem], upcoming: [TaskItem], query: String) -> [Item] {
        let words = query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }
        guard !words.isEmpty else { return [.noTask] + today.map(Item.task) }
        let matches = (today + upcoming).filter { task in
            let haystack = fold(([task.title] + task.tags).joined(separator: " "))
            return words.allSatisfy { haystack.contains($0) }
        }
        return matches.map(Item.task)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Focus length: the task's estimate when it has one, else the preset.
    static func minutes(for item: Item, preset: FocusPreset) -> Int {
        guard case .task(let task) = item else { return preset.focus }
        return ComposerDraft.focusMinutes(picked: nil, estimate: task.estimateMinutes, preset: preset)
    }

    static func start(_ item: Item, timer: FocusTimer, settings: AppSettings) {
        let preset = FocusPreset.with(id: settings.focusPresetID)
        switch item {
        case .task(let task):
            TaskActions.startComposerFocus(task: task, minutes: minutes(for: item, preset: preset), timer: timer, settings: settings)
        case .noTask:
            if !timer.isActive { timer.startPomodoro(preset) }
        }
    }

    static func currentItems(planner: PlannerStore, query: String) -> [Item] {
        items(today: planner.todayTasks(), upcoming: planner.upcomingTasks(), query: query)
    }

    /// ↑/↓ move, ↩ starts, Tab stays put; everything else goes to the search field.
    static func handle(_ event: NSEvent, workspace: WorkspaceState, planner: PlannerStore, focus: FocusTimer, settings: AppSettings) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.contains(.command) else { return false }
        let items = currentItems(planner: planner, query: workspace.focusQuery)
        switch Int(event.keyCode) {
        case 125:
            workspace.moveFocusSelection(by: 1, count: items.count)
        case 126:
            workspace.moveFocusSelection(by: -1, count: items.count)
        case 36, 76:
            guard items.indices.contains(workspace.focusSelection) else { return true }
            withAnimation(Motion.navigate) {
                start(items[workspace.focusSelection], timer: focus, settings: settings)
                workspace.closeFocusPicker()
            }
        case 48:
            break
        default:
            return false
        }
        return true
    }
}

struct FocusPickerOverlay: View {
    @Environment(WorkspaceState.self) private var workspace

    var body: some View {
        ZStack {
            if workspace.isFocusPickerOpen {
                Color.black.opacity(0.55)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { workspace.closeFocusPicker() }
                    .transition(.opacity)
                FocusPickerCard()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(Motion.navigate, value: workspace.isFocusPickerOpen)
    }
}

private struct FocusPickerCard: View {
    @Environment(PlannerStore.self) private var planner
    @Environment(FocusTimer.self) private var focus
    @Environment(AppSettings.self) private var settings
    @Environment(WorkspaceState.self) private var workspace
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = FocusPicker.currentItems(planner: planner, query: workspace.focusQuery)
        let preset = FocusPreset.with(id: settings.focusPresetID)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "scope").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.focus)
                Text(focus.isActive ? "Switch focus to…" : "Start a focus").font(Typography.title).foregroundStyle(Color.textPrimary)
                Spacer(minLength: 0)
                Text(preset.name).font(Typography.micro).foregroundStyle(Color.textTertiary)
            }
            TextField("", text: Binding(get: { workspace.focusQuery }, set: { query in
                guard query != workspace.focusQuery else { return }
                workspace.focusQuery = query
                workspace.focusSelection = 0
            }), prompt: Text("Type to find a task").foregroundStyle(Color.textTertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .focused($searchFocused)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.surface))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.focus.opacity(0.6), lineWidth: 1.2))
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, selected: index == workspace.focusSelection, preset: preset)
                                .id(item.id)
                                .onHover { if $0 { workspace.focusSelection = index } }
                                .onTapGesture {
                                    withAnimation(Motion.navigate) {
                                        FocusPicker.start(item, timer: focus, settings: settings)
                                        workspace.closeFocusPicker()
                                    }
                                }
                        }
                        if items.isEmpty {
                            Text("No task matches “\(workspace.focusQuery)”.")
                                .font(Typography.caption)
                                .foregroundStyle(Color.textTertiary)
                                .padding(.top, 8)
                        }
                    }
                }
                .onChange(of: workspace.focusSelection) { _, index in
                    if items.indices.contains(index) { reader.scrollTo(items[index].id) }
                }
            }
            HStack(spacing: 10) {
                hint("↑ ↓", "choose")
                hint("↩", focus.isActive ? "switch" : "start")
                hint("esc", "close")
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(width: 400, height: 320)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.145), Color(white: 0.105)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.13)))
        .shadow(color: .black.opacity(0.6), radius: 28, y: 12)
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
    }

    private func row(_ item: FocusPicker.Item, selected: Bool, preset: FocusPreset) -> some View {
        let minutes = FocusPicker.minutes(for: item, preset: preset)
        return HStack(spacing: 8) {
            switch item {
            case .noTask:
                Image(systemName: "timer").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.textSecondary).frame(width: 10)
                Text("Just focus (no task)").font(Typography.body).foregroundStyle(Color.textSecondary)
            case .task(let task):
                Circle().fill(task.priority == .none ? Color.textTertiary : task.priority.tint).frame(width: 7, height: 7).frame(width: 10)
                Text(task.title).font(Typography.body).foregroundStyle(Color.textPrimary).lineLimit(1)
                if focus.isActive, focus.taskID == task.id {
                    Text("now").font(Typography.micro).foregroundStyle(Color.focus)
                }
            }
            Spacer(minLength: 6)
            Text("\(minutes) min").font(Typography.micro).monospacedDigit().foregroundStyle(selected ? Color.textSecondary : Color.textTertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Color.focus.opacity(0.2) : Color.clear))
        .contentShape(Rectangle())
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 4)
                .frame(minWidth: 16, minHeight: 15)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.08)))
            Text(text).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Color.textTertiary)
        }
    }
}
