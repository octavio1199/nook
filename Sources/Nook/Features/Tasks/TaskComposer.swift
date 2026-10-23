import AppKit
import SwiftUI

/// Dimmed backdrop + centered composer card, drawn over the workspace inside the open panel.
struct TaskComposerOverlay: View {
    @Environment(WorkspaceState.self) private var workspace

    var body: some View {
        ZStack {
            if workspace.isComposerOpen {
                Color.black.opacity(0.55)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { workspace.closeComposer() }
                    .transition(.opacity)
                TaskComposerCard()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(Motion.navigate, value: workspace.isComposerOpen)
    }
}

/// The new-task card. Every stop is reachable with Tab (title, due, priority, estimate, tags,
/// focus, notes); the pickers take arrows and typing (`ComposerKeyboard`), routed here by
/// `PanelOverlayKeys` before the focused view sees the key.
struct TaskComposerCard: View {
    @Environment(PlannerStore.self) private var planner
    @Environment(FocusTimer.self) private var focus
    @Environment(AppSettings.self) private var settings
    @Environment(WorkspaceState.self) private var workspace
    @Environment(NotchInteraction.self) private var notch

    @FocusState private var textFocus: ComposerField?
    @LocalState private var datePickerShown = false

    private var draft: Binding<ComposerDraft> {
        Binding(get: { workspace.composer }, set: { workspace.composer = $0 })
    }

    private var field: ComposerField { workspace.composerKeys.field }
    private var preset: FocusPreset { .with(id: settings.focusPresetID) }

    var body: some View {
        let now = Date()
        let model = ComposerModel(draft: workspace.composer, preset: preset, now: now)
        return VStack(alignment: .leading, spacing: 9) {
            header
            titleField
            if model.isBrainDump {
                brainDump(model, now: now)
            } else {
                fieldGrid(model, now: now)
                if datePickerShown { dateRow }
                focusRow(model)
                notesField
            }
            footer(model)
        }
        .padding(14)
        .frame(width: 500, height: 348)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.145), Color(white: 0.105)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.13)))
        .shadow(color: .black.opacity(0.6), radius: 28, y: 12)
        .contentShape(Rectangle())
        .onAppear { focusField(.title) }
        .onChange(of: notch.captureRequest) { focusField(.title) }
        .onChange(of: workspace.composerKeys.field) { _, newField in syncTextFocus(newField) }
        .onChange(of: textFocus) { _, newFocus in
            if let newFocus, workspace.composerKeys.field != newFocus { workspace.composerKeys.field = newFocus }
        }
        .animation(Motion.navigate, value: model.isBrainDump)
        .animation(Motion.navigate, value: datePickerShown)
        .animation(Motion.hover, value: field)
        .animation(Motion.navigate, value: workspace.composer.startFocus)
    }

    // MARK: Focus

    private func focusField(_ target: ComposerField) {
        workspace.composerKeys.field = target
        DispatchQueue.main.async { syncTextFocus(target) }
    }

    /// Text stops hold the cursor; on a picker nothing does, so typing goes to the picker.
    private func syncTextFocus(_ target: ComposerField) {
        let wanted: ComposerField? = target == .title || target == .tags ? target : nil
        if textFocus != wanted { textFocus = wanted }
    }

    // MARK: Header / title

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accent)
            Text("New task").font(Typography.title).foregroundStyle(Color.textPrimary)
            Spacer(minLength: 0)
            if !workspace.composer.isEmpty {
                Button {
                    withAnimation(Motion.navigate) { workspace.composer = ComposerDraft() }
                    datePickerShown = false
                    focusField(.title)
                } label: {
                    Text("Clear").font(Typography.micro).foregroundStyle(Color.textTertiary).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Discard this draft")
            }
            Button { workspace.closeComposer() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.surface))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close, keeping the draft (esc)")
        }
    }

    private var titleField: some View {
        let active = field == .title
        return TextField("", text: draft.title,
                         prompt: Text("What needs doing? Try “call Ana tomorrow 3pm !high ~25m”").foregroundStyle(Color.textTertiary))
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.textPrimary)
            .focused($textFocus, equals: .title)
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(active ? Color.accent.opacity(0.75) : Color.hairline, lineWidth: active ? 1.3 : 1)
            )
    }

    // MARK: Brain dump

    private func brainDump(_ model: ComposerModel, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Chip(text: "\(model.parsed.count) tasks", symbol: "square.stack", tint: .accent)
                Text("Brain dump: each line becomes a task. Notes and focus are ignored.")
                    .font(Typography.micro)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(model.parsed.prefix(6).enumerated()), id: \.offset) { _, task in
                    HStack(spacing: 6) {
                        Circle().strokeBorder(Color.textTertiary, lineWidth: 1.2).frame(width: 9, height: 9)
                        Text(task.title).font(Typography.caption).foregroundStyle(Color.textPrimary).lineLimit(1)
                        if task.due != nil {
                            Text(TaskFormat.dueText(task, now: now)).font(Typography.micro).foregroundStyle(Color.accent)
                        }
                        if let minutes = task.estimateMinutes {
                            Text(TaskTime.estimateText(minutes)).font(Typography.micro).foregroundStyle(Color.textTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if model.parsed.count > 6 {
                    Text("+\(model.parsed.count - 6) more").font(Typography.micro).foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.horizontal, 4)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Fields

    private func fieldGrid(_ model: ComposerModel, now: Date) -> some View {
        let task = model.effective
        return HStack(spacing: 6) {
            tile(.due, label: "Due", hint: "← → ↑ ↓") {
                Menu {
                    Button("Today") { pick(.due) { $0.due = .today } }
                    Button("Tomorrow") { pick(.due) { $0.due = .tomorrow } }
                    Button("Next Week") { pick(.due) { $0.due = .date(Self.nextWeek(from: now)) } }
                    Button("Pick a Date…") {
                        if case .date = workspace.composer.due {} else { draft.wrappedValue.due = .date(Self.nextDay(from: now)) }
                        workspace.composerKeys.field = .due
                        datePickerShown = true
                    }
                    Divider()
                    Button("No Date") { pick(.due) { $0.due = .none } }
                } label: {
                    value(task.due == nil ? "Add date" : TaskFormat.dueText(task, now: now),
                          symbol: task.hasTime ? "clock" : "calendar", set: task.due != nil, tint: .accent)
                }
            }
            tile(.priority, label: "Priority", hint: "↑ ↓  h m l") {
                Menu {
                    ForEach(TaskItem.Priority.allCases.reversed(), id: \.self) { p in
                        Button {
                            pick(.priority) { $0.priority = p }
                        } label: {
                            if task.priority == p { Label(p.title, systemImage: "checkmark") } else { Text(p.title) }
                        }
                    }
                } label: {
                    value(task.priority == .none ? "None" : task.priority.title, symbol: task.priority == .none ? "flag" : "flag.fill",
                          set: task.priority != .none, tint: task.priority.tint)
                }
            }
            tile(.estimate, label: "Estimate", hint: "↑ ↓  0–9") {
                Menu {
                    ForEach(ComposerDraft.estimatePresets, id: \.self) { m in
                        Button {
                            pick(.estimate) { $0.estimateMinutes = m }
                        } label: {
                            if task.estimateMinutes == m { Label(TaskTime.estimateText(m), systemImage: "checkmark") } else { Text(TaskTime.estimateText(m)) }
                        }
                    }
                    if workspace.composer.estimateMinutes != nil {
                        Divider()
                        Button("Clear") { pick(.estimate) { $0.estimateMinutes = nil } }
                    }
                } label: {
                    value(task.estimateMinutes.map { "~" + TaskTime.estimateText($0) } ?? "None",
                          symbol: "hourglass", set: task.estimateMinutes != nil, tint: .accent)
                }
            }
            tile(.tags, label: "Tags", hint: "a, b", grows: true) {
                HStack(spacing: 4) {
                    ForEach(model.parsed.first?.tags ?? [], id: \.self) {
                        Text("#\($0)").font(Typography.caption).foregroundStyle(Color.textSecondary).fixedSize()
                    }
                    TextField("", text: draft.tagsText, prompt: Text("Add tags").foregroundStyle(Color.textTertiary))
                        .textFieldStyle(.plain)
                        .font(Typography.caption)
                        .foregroundStyle(Color.textPrimary)
                        .focused($textFocus, equals: .tags)
                }
                .frame(height: 16)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    /// A menu choice made with the mouse: applies it and moves the keyboard to that stop.
    private func pick(_ target: ComposerField, _ change: (inout ComposerDraft) -> Void) {
        change(&draft.wrappedValue)
        workspace.composerKeys.field = target
    }

    /// A labeled stop. Pickers size to their value (never truncated); `grows` takes the space left.
    private func tile<Content: View>(_ stop: ComposerField, label: String, hint: String, grows: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        let active = field == stop
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(active ? Color.accent : Color.textTertiary)
                Spacer(minLength: 0)
                if active {
                    Text(hint).font(.system(size: 8.5, weight: .medium)).foregroundStyle(Color.textTertiary).lineLimit(1).transition(.opacity)
                }
            }
            content()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(minWidth: grows ? 70 : 92, maxWidth: grows ? .infinity : nil, alignment: .leading)
        .fixedSize(horizontal: !grows, vertical: false)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active ? Color.accent.opacity(0.09) : Color.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(active ? Color.accent.opacity(0.75) : Color.hairline, lineWidth: active ? 1.3 : 1)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { workspace.composerKeys.field = stop })
    }

    private func value(_ text: String, symbol: String, set: Bool, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(set ? tint : Color.textTertiary)
            Text(text).font(Typography.caption)
                .foregroundStyle(set ? Color.textPrimary : Color.textTertiary)
                .lineLimit(1)
        }
        .frame(height: 16)
        .fixedSize()
    }

    private var dateRow: some View {
        let binding = Binding<Date>(
            get: { if case .date(let d) = workspace.composer.due { d } else { Date() } },
            set: { draft.wrappedValue.due = .date($0) }
        )
        return HStack(spacing: 8) {
            Image(systemName: "calendar").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.textSecondary)
            DatePicker("", selection: binding, displayedComponents: .date)
                .datePickerStyle(.field)
                .labelsHidden()
                .environment(\.colorScheme, .dark)
            Spacer(minLength: 0)
            miniButton("Done") { datePickerShown = false }
        }
        .transition(.opacity)
    }

    private func miniButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typography.micro)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(Color.surface))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Focus

    private func focusRow(_ model: ComposerModel) -> some View {
        let active = field == .focus
        let on = workspace.composer.startFocus
        return HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { on }, set: { value in pick(.focus) { $0.startFocus = value } })) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text("Start focus now")
                    .font(Typography.caption)
                    .foregroundStyle(on ? Color.focus : Color.textSecondary)
                Text(on ? model.focusHint(timerRunning: focus.isActive) : (active ? "space to turn on · ← → length" : "Focus on it as soon as it's added"))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            .layoutPriority(-1)
            Spacer(minLength: 4)
            if on { durationPicker(model).fixedSize().transition(.opacity) }
        }
        .padding(.horizontal, 9)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active ? Color.focus.opacity(0.1) : Color.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(active ? Color.focus.opacity(0.8) : Color.hairline, lineWidth: active ? 1.3 : 1)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { workspace.composerKeys.field = .focus })
    }

    private func durationPicker(_ model: ComposerModel) -> some View {
        let minutes = model.focusMinutes
        let custom = !ComposerDraft.focusPresets.contains(minutes)
        return HStack(spacing: 3) {
            ForEach(ComposerDraft.focusPresets, id: \.self) { m in
                optionChip("\(m)m", selected: minutes == m) { pick(.focus) { $0.focusMinutes = m } }
            }
            HStack(spacing: 0) {
                stepButton("minus") { pick(.focus) { $0.focusMinutes = max(minutes - 5, ComposerDraft.focusRange.lowerBound) } }
                Text(custom ? "\(minutes)m" : "Custom")
                    .font(Typography.micro)
                    .monospacedDigit()
                    .foregroundStyle(custom ? Color.textPrimary : Color.textTertiary)
                    .frame(minWidth: 40)
                stepButton("plus") { pick(.focus) { $0.focusMinutes = min(minutes + 5, ComposerDraft.focusRange.upperBound) } }
            }
            .padding(.horizontal, 2)
            .frame(height: 22)
            .background(Capsule().fill(custom ? Color.focus.opacity(0.22) : Color.white.opacity(0.06)))
        }
    }

    private func optionChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typography.micro)
                .monospacedDigit()
                .foregroundStyle(selected ? Color.textPrimary : Color.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(selected ? Color.focus.opacity(0.24) : Color.white.opacity(0.06)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 18, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Notes

    private var notesField: some View {
        let active = field == .notes
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.surface)
            MarkdownEditor(
                text: draft.notes, placeholder: "Notes — markdown supported",
                onCommandReturn: { _ in
                    ComposerActions.submit(focusNow: workspace.composer.startFocus, workspace: workspace, planner: planner, focus: focus, settings: settings)
                    return false
                },
                wantsFocus: active,
                onFocusChange: { focused in if focused, workspace.composerKeys.field != .notes { workspace.composerKeys.field = .notes } }
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(active ? Color.accent.opacity(0.75) : Color.hairline, lineWidth: active ? 1.3 : 1)
        )
        .frame(minHeight: 44, maxHeight: .infinity)
    }

    // MARK: Footer

    private func footer(_ model: ComposerModel) -> some View {
        let canAdd = !model.parsed.isEmpty
        let focusOn = workspace.composer.startFocus && !model.isBrainDump
        return HStack(spacing: 10) {
            if model.isBrainDump {
                keyHint("↩", "add all")
            } else {
                keyHint("⇥", "next")
                keyHint("↩", focusOn ? "add & focus" : "add")
                if !focusOn { keyHint("⌥↩", "add & focus") }
            }
            keyHint("esc", "keep draft")
            Spacer(minLength: 0)
            if model.isBrainDump {
                actionButton("Add \(model.parsed.count) tasks", prominent: true, tint: .accent) { submit(focusNow: false) }
                    .disabled(!canAdd)
            } else if focusOn {
                actionButton("Add & focus", symbol: "play.fill", prominent: true, tint: .focus) { submit(focusNow: true) }
                    .disabled(!canAdd)
            } else {
                actionButton("Add & focus", symbol: "play.fill", prominent: false, tint: .focus) { submit(focusNow: true) }
                    .disabled(!canAdd)
                actionButton("Add", prominent: true, tint: .accent) { submit(focusNow: false) }
                    .disabled(!canAdd)
            }
        }
        .frame(height: 26)
    }

    private func keyHint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 4)
                .frame(minWidth: 16, minHeight: 15)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
            Text(text).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Color.textTertiary)
        }
        .fixedSize()
    }

    private func actionButton(_ title: String, symbol: String? = nil, prominent: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 8, weight: .bold)) }
                Text(title).font(Typography.caption)
            }
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : tint)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(prominent ? tint : tint.opacity(0.16)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func submit(focusNow: Bool) {
        ComposerActions.submit(focusNow: focusNow, workspace: workspace, planner: planner, focus: focus, settings: settings)
    }

    static func nextDay(from now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
    }

    static func nextWeek(from now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
    }
}

/// Turns the draft into tasks (and maybe a focus). Shared by the buttons and the keyboard.
enum ComposerActions {
    @discardableResult
    static func submit(focusNow: Bool, workspace: WorkspaceState, planner: PlannerStore, focus: FocusTimer, settings: AppSettings, now: Date = Date()) -> Bool {
        let composer = workspace.composer
        let tasks = composer.makeTasks(now: now)
        guard !tasks.isEmpty else {
            workspace.composerKeys.field = .title
            return false
        }
        let single = tasks.count == 1 ? tasks.first : nil
        withAnimation(Motion.navigate) { planner.add(tasks) }
        if focusNow, let task = single {
            let minutes = composer.focusMinutes(effectiveEstimate: task.estimateMinutes, preset: .with(id: settings.focusPresetID))
            withAnimation(Motion.navigate) {
                TaskActions.startComposerFocus(task: task, minutes: minutes, timer: focus, settings: settings)
            }
        }
        if let task = single {
            workspace.toaster.show("Added", task.title, symbol: focusNow ? "scope" : "plus.circle")
        } else {
            workspace.toaster.show("Added \(tasks.count) tasks", symbol: "plus.circle")
        }
        workspace.finishComposer()
        return true
    }
}

extension ComposerKey {
    /// Nil for keys the composer never takes (⌘ shortcuts other than ⌘↩, function keys).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        switch Int(event.keyCode) {
        case 48: self = .tab(backward: flags.contains(.shift))
        case 36, 76: self = .enter(option: flags.contains(.option), command: command)
        case 123 where !command: self = .left
        case 124 where !command: self = .right
        case 125 where !command: self = .down
        case 126 where !command: self = .up
        case 51 where !command, 117 where !command: self = .delete
        case 49 where !command: self = .space
        default:
            guard !command, !flags.contains(.control), let c = event.charactersIgnoringModifiers?.first else { return nil }
            self = .character(c)
        }
    }
}

/// Routes keys to whichever overlay is up (installed by `WorkspaceView` as the panel's key interceptor).
enum PanelOverlayKeys {
    static func handle(_ event: NSEvent, workspace: WorkspaceState, planner: PlannerStore, focus: FocusTimer, settings: AppSettings, inlinePicker: Bool = false) -> Bool {
        if workspace.isComposerOpen {
            guard let key = ComposerKey(event: event) else { return false }
            var draft = workspace.composer
            var keys = workspace.composerKeys
            let result = keys.handle(key, draft: &draft)
            if draft != workspace.composer { withAnimation(Motion.hover) { workspace.composer = draft } }
            if keys != workspace.composerKeys { workspace.composerKeys = keys }
            switch result {
            case .pass: return false
            case .handled: return true
            case .submit(let focusNow):
                ComposerActions.submit(focusNow: focusNow, workspace: workspace, planner: planner, focus: focus, settings: settings)
                return true
            }
        }
        if workspace.isFocusPickerOpen || inlinePicker {
            return FocusPicker.handle(event, workspace: workspace, planner: planner, focus: focus, settings: settings)
        }
        return false
    }
}

/// What the composer shows for the current draft, computed once per render.
struct ComposerModel {
    let parsed: [TaskItem]
    let effective: TaskItem
    let isBrainDump: Bool
    let focusMinutes: Int
    let preset: FocusPreset
    let draft: ComposerDraft

    init(draft: ComposerDraft, preset: FocusPreset, now: Date, calendar: Calendar = .current) {
        self.draft = draft
        self.preset = preset
        let parsed = draft.parsedTasks(now: now, calendar: calendar)
        self.parsed = parsed
        isBrainDump = parsed.count > 1
        effective = draft.applying(to: parsed.first ?? TaskItem(title: ""), now: now, calendar: calendar)
        focusMinutes = draft.focusMinutes(effectiveEstimate: effective.estimateMinutes, preset: preset)
    }

    func focusHint(timerRunning: Bool) -> String {
        if timerRunning { return "A timer is already running: it will switch to this task instead." }
        if draft.focusMinutes != nil { return "\(preset.name) breaks, \(focusMinutes) min focus." }
        if let estimate = effective.estimateMinutes { return "Matches your \(TaskTime.estimateText(estimate)) estimate. \(preset.name) breaks." }
        return "Your \(preset.name) preset: \(preset.focus) min focus, \(preset.shortBreak) min breaks."
    }
}

/// Estimate chip with presets; also used by the task detail. `onCustom` is optional (menus can't host a stepper).
struct EstimateMenu: View {
    var minutes: Int?
    var onSelect: (Int?) -> Void
    var onCustom: (() -> Void)?
    var showsAdjust = false

    var body: some View {
        Menu {
            ForEach(ComposerDraft.estimatePresets, id: \.self) { m in
                Button {
                    onSelect(m)
                } label: {
                    if minutes == m { Label(TaskTime.estimateText(m), systemImage: "checkmark") } else { Text(TaskTime.estimateText(m)) }
                }
            }
            if let onCustom {
                Button("Custom…", action: onCustom)
            }
            if showsAdjust, let minutes {
                Divider()
                Button("+ 5 min") { onSelect(min(minutes + 5, ComposerDraft.estimateRange.upperBound)) }
                Button("− 5 min") { onSelect(max(minutes - 5, ComposerDraft.estimateRange.lowerBound)) }
            }
            if minutes != nil {
                Divider()
                Button("No Estimate") { onSelect(nil) }
            }
        } label: {
            if let minutes {
                Chip(text: "~\(TaskTime.estimateText(minutes))", symbol: "hourglass", tint: .accent)
            } else {
                Chip(text: "Estimate", symbol: "hourglass", tint: .textTertiary)
            }
        }
    }
}
