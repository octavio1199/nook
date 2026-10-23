# Changelog

## 0.3.0 (2026-10-23)

### Focus
- **Focus tab** (Workspace · Focus · Day · Insights). While a focus runs it shows only the current task: a big timer with pause, +5, skip, stop and "Task done", its **sub-tasks** with a progress bar, and its Markdown notes. With no focus running it's a type-to-search task picker. Nook switches to it when a focus starts and back when it ends (can be turned off in Settings › Focus).
- **Sub-tasks**: add, check, rename, reorder and delete, in the Focus tab and the task detail. Task rows show "2/4".
- **Time's up check-in**: when a task's focus ends, choose **+5 min**, **Break** (then continue the same task) or **Done**, from the notch, the panel or a macOS notification.
- **Time per task**: focus time adds up per task and shows next to its estimate ("20/50m"), turning orange when it runs over.

### Planning
- **New-task card** (⌥⌘N or ⌘N): title with the natural-language parser, Markdown notes, due date, priority, **estimate**, tags, and "Start focus now". Fully keyboard-driven: Tab moves through the fields, arrows and letters set the pickers, ↩ adds, ⌥↩ adds and starts focusing. Several lines or `;` add several tasks at once.
- **Estimates** from the title too: `~25m`, `~1h30`, `est 45m`.
- **Time blocking** in the new **Day** tab: a 24-hour timeline with your calendar events; drag tasks onto it, move and resize blocks (15 min steps). **Plan my day** fills the free time inside your working hours by priority. Nook asks 5 minutes before a block (Start now / Snooze 10 / Skip) and when it starts (Start focus). It never starts on its own. During a block, the closed notch shows it. Ran late? **Push rest of day** shifts the remaining blocks.
- **Log past days**: go back on the Day tab and drag a task onto the timeline to log time you didn't track. Logged blocks can be moved, resized, deleted, or used to mark the task done at that time. They count in Insights.
- Workspace agenda becomes **Up next** (current block plus the next events and blocks). Insights shows **planned vs actual**.

### Workspace
- Calmer layout: the current task is pinned at the top of Tasks with a live timer. Rows show a priority dot and one detail at most (tags on hover). Lighter cards.
- **Resizable columns**: drag the divider between Tasks and Notepad (double-click resets).
- Task detail lays out due date, priority, estimate and tags as rows.
- **Archive** with restore, **⌘Z undo** for task actions, and an undo toast.
- Breaks get a green look and tips.

### Keyboard and displays
- **Global shortcuts**, rebindable in Settings › Keyboard:
  - ⌃⌥N open/close Nook
  - ⌥⌘N new task
  - ⌃⌥P pin
  - ⌃⌥S start a focus
  - ⌃⌥M move Nook to the display under the mouse
- In the panel: ⌘1–⌘4 switch tabs, ⌘N new task, ←/→ change day.
- **Choose the display**: Automatic (the notch, else the main display), Main display, **Active display** (where you last clicked or switched apps), or any connected monitor. On displays without a notch, live activities show as a pill in the middle of the menu bar.

### Settings and data
- Redesigned **Settings** with a sidebar, like System Settings.
- macOS **notifications with actions** when the notch can't be seen (screen locked, full-screen app, away).
- Header moved into the strip beside the camera. Labeled line-wrap toggle in the notepad.
- **Data safety**: daily backups next to `planner.json`, tolerant loading (a bad entry never drops the rest), an unreadable file is moved aside instead of overwritten, and saving on quit.

## 0.2.0 (2026-10-22)

- **Markdown notepad**: live headings, bold/italic, code and code blocks, lists, clickable `- [ ]` checkboxes, quotes and links. Enter continues lists, Tab indents. Line wrap on by default.
- **Task notes**: click a task to open its details with its own Markdown notes, focus time and a link back to the notepad day it came from.
- **Focus on a task**: the task title shows on the left of the notch and the timer on the right. Focus time adds up per task.
- **Copy/paste** in the notepad and task fields. **Quit** button in the panel header.
- Calendar fix: macOS now asks for Calendar access.

## 0.1.0 (2026-10-22)

First release: natural-language task capture (English and Portuguese) with brain-dump splitting, a daily notepad (⌘↩ turns a line into a task), focus timer with a live activity beside the notch, read-only Calendar agenda with alerts, Insights. Universal binary, macOS 14+.
