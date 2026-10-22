import AppKit
import SwiftUI

struct AgendaCard: View {
    @Environment(AgendaModel.self) private var agenda
    @Environment(PlannerStore.self) private var planner

    var body: some View {
        let blocks = planner.scheduledTasks(on: Date())
        if blocks.isEmpty {
            agendaCard
        } else {
            Card("Up next", symbol: "clock") {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    UpNextList(
                        items: UpNextItem.list(events: agenda.access == .granted ? agenda.today : [], blocks: blocks, now: context.date),
                        now: context.date
                    )
                }
            }
            .frame(height: 150)
        }
    }

    private var agendaCard: some View {
        Card("Agenda", symbol: "calendar") {
            switch agenda.access {
            case .unknown:
                Prompt(
                    text: "See today's events right in the notch. Read-only, never changes your calendar.",
                    button: "Connect Calendar", action: agenda.requestAccess
                )
            case .denied:
                Prompt(
                    text: "Calendar access is off. Enable it in System Settings to see your events.",
                    button: "Open Privacy Settings", action: agenda.openPrivacySettings
                )
            case .granted:
                EventList(today: agenda.today, tomorrow: agenda.tomorrow, now: agenda.now)
            }
        }
        .frame(height: 150)
    }
}

private struct Prompt: View {
    var text: String
    var button: String
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(Typography.caption).foregroundStyle(Color.textSecondary).fixedSize(horizontal: false, vertical: true)
            Button(button, action: action)
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .controlSize(.small)
        }
    }
}

/// Current time block plus the next three items (calendar events and task blocks) of the day.
private struct UpNextList: View {
    var items: [UpNextItem]
    var now: Date

    var body: some View {
        if items.isEmpty {
            Text("Nothing left on today's plan")
                .font(Typography.caption).foregroundStyle(Color.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        if let event = item.event {
                            EventRow(event: event, now: now)
                        } else if let task = item.task {
                            BlockRow(task: task, start: item.start, end: item.end, now: now)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct BlockRow: View {
    var task: TaskItem
    var start: Date
    var end: Date
    var now: Date
    @Environment(BlockWatcher.self) private var blocks
    @Environment(FocusTimer.self) private var focus

    private var isNow: Bool { start <= now && end > now }
    private var progress: Double {
        let total = end.timeIntervalSince(start)
        return total > 0 ? min(max(now.timeIntervalSince(start) / total, 0), 1) : 0
    }

    var body: some View {
        let tint = DayPalette.tint(task.priority)
        let format = Date.FormatStyle.dateTime.hour().minute()
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5).fill(tint).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("\(start.formatted(format)) – \(end.formatted(format))").font(Typography.micro).foregroundStyle(Color.textSecondary)
                    if isNow {
                        Text("Now").font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accent))
                            .foregroundStyle(Color.black)
                    }
                }
                Text(task.title).font(Typography.caption).foregroundStyle(Color.textPrimary).lineLimit(1)
                if isNow {
                    ProgressView(value: progress).progressViewStyle(.linear).tint(tint).controlSize(.mini).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if isNow, !(focus.isActive && focus.taskID == task.id) {
                Button { blocks.startFocus(task.id) } label: {
                    Text("Start").font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accent.opacity(0.9)))
                        .foregroundStyle(Color.black)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Start a focus as long as this block")
            }
        }
        .padding(.vertical, 2).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(isNow ? Color.surfaceRaised : .clear))
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct EventList: View {
    var today: [AgendaEvent]
    var tomorrow: [AgendaEvent]
    var now: Date

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                if today.isEmpty {
                    Text("Nothing on your calendar today")
                        .font(Typography.caption).foregroundStyle(Color.textTertiary)
                } else {
                    ForEach(today) { EventRow(event: $0, now: now) }
                }
                if !tomorrow.isEmpty {
                    Text("TOMORROW").font(Typography.micro).tracking(0.8)
                        .foregroundStyle(Color.textTertiary).padding(.top, 4)
                    ForEach(tomorrow.prefix(3)) { EventRow(event: $0, now: now) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct EventRow: View {
    var event: AgendaEvent
    var now: Date

    private var isNow: Bool { !event.isAllDay && event.start <= now && event.end > now }
    private var joinURL: URL? {
        guard let url = event.joinURL, Self.isSafe(url), url.scheme?.lowercased() == "https", event.end > now else { return nil }
        return url
    }
    private var progress: Double {
        let total = event.end.timeIntervalSince(event.start)
        return total > 0 ? min(max(now.timeIntervalSince(event.start) / total, 0), 1) : 0
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        let format = Date.FormatStyle.dateTime.hour().minute()
        return "\(event.start.formatted(format)) – \(event.end.formatted(format))"
    }

    var body: some View {
        let row = HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5).fill(event.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(timeText).font(Typography.micro).foregroundStyle(Color.textSecondary)
                    if isNow {
                        Text("Now").font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accent))
                            .foregroundStyle(Color.black)
                    }
                }
                Text(event.title).font(Typography.caption).foregroundStyle(Color.textPrimary).lineLimit(1)
                if let location = event.location, !location.isEmpty {
                    Text(location).font(Typography.micro).foregroundStyle(Color.textTertiary).lineLimit(1)
                }
                if isNow {
                    ProgressView(value: progress).progressViewStyle(.linear).tint(event.color).controlSize(.mini)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if let join = joinURL {
                Button { NSWorkspace.shared.open(join) } label: {
                    Text("Join").font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(event.color.opacity(isNow ? 0.9 : 0.25)))
                        .foregroundStyle(isNow ? Color.black : Color.textPrimary)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Join \(join.host() ?? "call")")
            }
        }
        .padding(.vertical, 2).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(isNow ? Color.surfaceRaised : .clear))
        .fixedSize(horizontal: false, vertical: true)

        if let url = event.url, Self.isSafe(url) {
            Button { NSWorkspace.shared.open(url) } label: { row.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .help("Open \(url.host() ?? url.absoluteString)")
        } else {
            row
        }
    }

    /// Calendar URLs come from third parties; only open web and meeting links.
    private static let safeSchemes: Set<String> = ["https", "http", "zoommtg", "msteams", "facetime"]

    static func isSafe(_ url: URL) -> Bool {
        safeSchemes.contains(url.scheme?.lowercased() ?? "")
    }
}
