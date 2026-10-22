# Nook — spec v1

A free, open-source notch planner for macOS. It takes the best of
**NotchOwl** (planner: tasks, daily notepad, focus timer, agenda, insights) and
**Notchable** (fast capture, brain-dump splitting, Pomodoro, live activity in the
notch), built on the foundation of **Pullo** (NSPanel + hover + peek, MIT).

## Why it's better
- Free and MIT, no license, account or telemetry. Data lives in a local JSON file.
- Universal binary (Apple silicon + Intel), macOS 14+.
- Local capture parser (no cloud AI): `call Ana tomorrow 3pm !high #work`
  becomes a task with a date, time, priority and tag. Pasting/typing several items
  separated by `;` or line breaks creates several tasks (brain dump).
- Live activity: during focus the notch grows "wings" (ring + countdown),
  and it also warns about an event starting within 10 min.
- Glass (macOS 26+) or Solid.

## Interaction
- Opens on hover (80ms) or on click (setting). Closes 200ms after the cursor leaves, on a click outside, or on Esc.
- Global hotkey ⌥⌘N: opens with the cursor in the capture field.
- States: `closed` (notch / wings), `peek` (alert slides out of the notch), `open` (workspace).
- No notch: virtual notch at the top center, visible only when open/peek.
- Menu bar item: Open, Settings, Quit.

## Workspace (open state)
Three columns:
1. **Tasks**: capture at the top; Today / Upcoming / Done lists; check, priority, tag, due chip; right-click → delete / tomorrow / priority.
2. **Notepad**: daily auto-saving notes; ⌘↩ on a line turns it into a task.
3. **Side**: Agenda card (today's events from EventKit, read-only, permission asked lazily) + Focus card (presets 25/5, 50/10, 15/3, countdown, stopwatch; pause/resume/+5 min/stop).

Bottom switcher: Workspace · Insights (completed tasks, focus minutes, 7-day chart, streak).

## Alerts (peek)
Focus/break finished, event starting in 5 min, task due now. Queue + 4.5 s, hover holds it.

## Architecture
SwiftPM (`swift build`), default isolation MainActor, `scripts/bundle.sh` builds a universal `.app`.
`App/` (lifecycle, panel, hotkey) · `Notch/` (geometry, shape, interaction) · `Domain/` (models) ·
`Stores/` (PlannerStore, FocusTimer, AgendaModel, AppSettings) · `Features/*` (SwiftUI) · `DesignSystem/`.
