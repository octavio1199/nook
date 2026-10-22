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

struct TaskComposerCard: View {
    @Environment(PlannerStore.self) private var planner
    @Environment(FocusTimer.self) private var focus
    @Environment(AppSettings.self) private var settings
    @Environment(WorkspaceState.self) private var workspace
    @Environment(NotchInteraction.self) private var notch

    @FocusState private var titleFocused: Bool
    @LocalState private var datePickerShown = false
    @LocalState private var estimateStepperShown = false

    private var draft: Binding<ComposerDraft> {
        Binding(get: { workspace.composer }, set: { workspace.composer = $0 })
    }

    private var preset: FocusPreset { .with(id: settings.focusPresetID) }

    var body: some View {
        let now = Date()
        let model = ComposerModel(draft: workspace.composer, preset: preset, now: now)
        return VStack(alignment: .leading, spacing: 8) {
            header(model)
            titleField(model)
            if model.isBrainDump {
                brainDump(model)
            } else {
                notesField
                chipRow(model, now: now)
                if datePickerShown { dateRow }
                if estimateStepperShown { estimateRow(model) }
                focusSection(model)
            }
            footer(model)
        }
        .padding(14)
        .frame(width: 460, height: 300)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.115)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.6), radius: 26, y: 10)
        .contentShape(Rectangle())
        .onAppear { focusTitle() }
        .onChange(of: notch.captureRequest) { focusTitle() }
        .animation(Motion.navigate, value: model.isBrainDump)
        .animation(Motion.navigate, value: datePickerShown)
        .animation(Motion.navigate, value: estimateStepperShown)
        .animation(Motion.navigate, value: workspace.composer.startFocus)
    }

    private func focusTitle() {
        DispatchQueue.main.async { titleFocused = true }
    }

    // MARK: Header / title

    private func header(_ model: ComposerModel) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill").font(Typography.micro).foregroundStyle(Color.accent)
            Text("NEW TASK").font(Typography.micro).tracking(0.8).foregroundStyle(Color.textSecondary)
            Spacer(minLength: 0)
            if !workspace.composer.isEmpty {
                Button {
                    withAnimation(Motion.navigate) { workspace.composer = ComposerDraft() }
                    datePickerShown = false
                    estimateStepperShown = false
                    focusTitle()
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
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.surface))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close, keeping the draft (esc)")
        }
    }

    private func titleField(_ model: ComposerModel) -> some View {
        TextField("", text: draft.title,
                  prompt: Text("Task — try “call Ana tomorrow 3pm !high #work ~25m”").foregroundStyle(Color.textTertiary))
            .textFieldStyle(.plain)
            .font(Typography.title)
            .foregroundStyle(Color.textPrimary)
            .focused($titleFocused)
            .onSubmit { submit(focusNow: workspace.composer.startFocus && !model.isBrainDump) }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(titleFocused ? Color.accent.opacity(0.6) : Color.hairline)
            )
            .animation(Motion.hover, value: titleFocused)
    }

    // MARK: Brain dump

    private func brainDump(_ model: ComposerModel) -> some View {
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
                ForEach(Array(model.parsed.prefix(5).enumerated()), id: \.offset) { _, task in
                    HStack(spacing: 6) {
                        Circle().strokeBorder(Color.textTertiary, lineWidth: 1.2).frame(width: 9, height: 9)
                        Text(task.title).font(Typography.caption).foregroundStyle(Color.textPrimary).lineLimit(1)
                        if task.due != nil {
                            Text(TaskFormat.dueText(task, now: Date())).font(Typography.micro).foregroundStyle(Color.accent)
                        }
                        if let minutes = task.estimateMinutes {
                            Text(TaskTime.estimateText(minutes)).font(Typography.micro).foregroundStyle(Color.textTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if model.parsed.count > 5 {
                    Text("+\(model.parsed.count - 5) more").font(Typography.micro).foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.horizontal, 4)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Notes

    private var notesField: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.surface)
            MarkdownEditor(text: draft.notes, placeholder: "Notes — markdown supported", onCommandReturn: { _ in
                submit(focusNow: workspace.composer.startFocus)
                return false
            })
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
        }
        .frame(minHeight: 48, maxHeight: .infinity)
    }

    // MARK: Chips

    private func chipRow(_ model: ComposerModel, now: Date) -> some View {
        let task = model.effective
        return HStack(spacing: 4) {
            Menu {
                Button("Today") { draft.wrappedValue.due = .today }
                Button("Tomorrow") { draft.wrappedValue.due = .tomorrow }
                Button("Next Week") { draft.wrappedValue.due = .date(Self.nextWeek(from: now)) }
                Button("Pick a Date…") {
                    if case .date = workspace.composer.due {} else { draft.wrappedValue.due = .date(Self.nextDay(from: now)) }
                    datePickerShown = true
                }
                Divider()
                Button("No Date") { draft.wrappedValue.due = .none }
            } label: {
                if task.due != nil {
                    Chip(text: TaskFormat.dueText(task, now: now), symbol: task.hasTime ? "clock" : "calendar", tint: .accent).fixedSize()
                } else {
                    Chip(text: "Due", symbol: "calendar", tint: .textTertiary)
                }
            }
            Menu {
                ForEach(TaskItem.Priority.allCases.reversed(), id: \.self) { p in
                    Button {
                        draft.wrappedValue.priority = p
                    } label: {
                        if task.priority == p { Label(p.title, systemImage: "checkmark") } else { Text(p.title) }
                    }
                }
            } label: {
                if task.priority != .none {
                    Chip(text: task.priority.shortTitle, symbol: "flag.fill", tint: task.priority.tint)
                } else {
                    Chip(text: "Priority", symbol: "flag", tint: .textTertiary)
                }
            }
            EstimateMenu(minutes: task.estimateMinutes, onSelect: { draft.wrappedValue.estimateMinutes = $0 }, onCustom: {
                if workspace.composer.estimateMinutes == nil { draft.wrappedValue.estimateMinutes = task.estimateMinutes ?? 30 }
                estimateStepperShown = true
            })
            ForEach(model.parsed.first?.tags ?? [], id: \.self) { Chip(text: "#\($0)", tint: .textSecondary) }
            tagsField
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .lineLimit(1)
    }

    private var tagsField: some View {
        TextField("", text: draft.tagsText, prompt: Text("+ tags").foregroundStyle(Color.textTertiary))
            .textFieldStyle(.plain)
            .font(Typography.micro)
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 7)
            .frame(minWidth: 40, maxWidth: .infinity)
            .frame(height: 20)
            .layoutPriority(-1)
            .background(Capsule().fill(Color.surface))
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

    private func estimateRow(_ model: ComposerModel) -> some View {
        let binding = Binding<Int>(
            get: { workspace.composer.estimateMinutes ?? model.effective.estimateMinutes ?? 30 },
            set: { draft.wrappedValue.estimateMinutes = $0 }
        )
        return HStack(spacing: 8) {
            Image(systemName: "hourglass").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.textSecondary)
            Text("Estimate").font(Typography.caption).foregroundStyle(Color.textSecondary)
            Text(TaskTime.estimateText(binding.wrappedValue)).font(Typography.caption).monospacedDigit().foregroundStyle(Color.textPrimary)
            Stepper("", value: binding, in: ComposerDraft.estimateRange, step: 5).labelsHidden()
            Spacer(minLength: 0)
            miniButton("Done") { estimateStepperShown = false }
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

    private func focusSection(_ model: ComposerModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle(isOn: draft.startFocus) {
                    Label("Start focus now", systemImage: "scope")
                        .font(Typography.caption)
                        .foregroundStyle(workspace.composer.startFocus ? Color.focus : Color.textSecondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                Spacer(minLength: 0)
                if workspace.composer.startFocus { durationPicker(model) }
            }
            if workspace.composer.startFocus {
                Text(model.focusHint(timerRunning: focus.isActive))
                    .font(Typography.micro)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 2)
    }

    private func durationPicker(_ model: ComposerModel) -> some View {
        let minutes = model.focusMinutes
        let custom = !ComposerDraft.focusPresets.contains(minutes)
        return HStack(spacing: 3) {
            ForEach(ComposerDraft.focusPresets, id: \.self) { m in
                optionChip("\(m)m", selected: minutes == m) { draft.wrappedValue.focusMinutes = m }
            }
            HStack(spacing: 0) {
                stepButton("minus") { draft.wrappedValue.focusMinutes = max(minutes - 5, ComposerDraft.focusRange.lowerBound) }
                Text(custom ? "\(minutes)m" : "Custom")
                    .font(Typography.micro)
                    .monospacedDigit()
                    .foregroundStyle(custom ? Color.textPrimary : Color.textTertiary)
                    .frame(minWidth: 40)
                stepButton("plus") { draft.wrappedValue.focusMinutes = min(minutes + 5, ComposerDraft.focusRange.upperBound) }
            }
            .padding(.horizontal, 2)
            .frame(height: 22)
            .background(Capsule().fill(custom ? Color.focus.opacity(0.22) : Color.surface))
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
                .background(Capsule().fill(selected ? Color.focus.opacity(0.22) : Color.surface))
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

    // MARK: Footer

    private func footer(_ model: ComposerModel) -> some View {
        let canAdd = !model.parsed.isEmpty
        let focusOn = workspace.composer.startFocus && !model.isBrainDump
        return HStack(spacing: 6) {
            Text(model.isBrainDump ? "↩ add all   esc keep draft" : "↩ add   ⌥↩ add & focus   esc keep draft")
                .font(Typography.micro)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if model.isBrainDump {
                actionButton("Add \(model.parsed.count) tasks", prominent: true, tint: .accent) { submit(focusNow: false) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canAdd)
            } else if focusOn {
                actionButton("Add & focus", symbol: "play.fill", prominent: true, tint: .focus) { submit(focusNow: true) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canAdd)
                hiddenShortcut { submit(focusNow: true) }
            } else {
                actionButton("Add & focus", symbol: "play.fill", prominent: false, tint: .focus) { submit(focusNow: true) }
                    .keyboardShortcut(.return, modifiers: .option)
                    .disabled(!canAdd)
                actionButton("Add", prominent: true, tint: .accent) { submit(focusNow: false) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canAdd)
            }
        }
        .frame(height: 26)
    }

    /// ⌥↩ keeps working as "add & focus" while the visible button is the toggle-driven one.
    private func hiddenShortcut(_ action: @escaping () -> Void) -> some View {
        Button("", action: action)
            .keyboardShortcut(.return, modifiers: .option)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
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

    // MARK: Submit

    private func submit(focusNow: Bool) {
        let now = Date()
        let composer = workspace.composer
        let tasks = composer.makeTasks(now: now)
        guard !tasks.isEmpty else {
            titleFocused = true
            return
        }
        let single = tasks.count == 1 ? tasks.first : nil
        withAnimation(Motion.navigate) { planner.add(tasks) }
        if focusNow, let task = single {
            let minutes = composer.focusMinutes(effectiveEstimate: task.estimateMinutes, preset: preset)
            withAnimation(Motion.navigate) {
                TaskActions.startComposerFocus(task: task, minutes: minutes, timer: focus, settings: settings)
            }
        }
        if let task = single {
            workspace.toaster.show("Added", task.title, symbol: focusNow ? "scope" : "plus.circle")
        } else {
            workspace.toaster.show("Added \(tasks.count) tasks", symbol: "plus.circle")
        }
        datePickerShown = false
        estimateStepperShown = false
        workspace.finishComposer()
    }

    static func nextDay(from now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
    }

    static func nextWeek(from now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
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
