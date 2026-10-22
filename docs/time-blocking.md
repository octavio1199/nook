# Time blocking — design

**Decisions for v1 (approved):** a new Day tab; the notch *asks* before starting a block (no
auto-start); blocks live only inside Nook (no Calendar writes); planning by drag & drop,
"Plan my day" and "Push rest of day". Capture-with-a-time ("14h ~1h") is deferred.

Goal: turn "what I need to do today" into "when I'll do each thing", inside the notch, and let
the notch run the day for you: it knows what block you're in, what's next, and starts the focus.

## Model

- `TaskItem.estimateMinutes` is the block length (default 30 min when unset).
- `TaskItem.scheduledStart` places the task on today's timeline. Clearing it unschedules.
- Calendar events (EventKit, read-only today) are fixed blocks that tasks flow around.
- A day has working hours (setting, default 09:00–18:00) used by auto-planning.

## Planning

1. **Drag & drop**: drag a task from the list onto the timeline; it snaps to 15 min.
   Drag a block to move it, drag its bottom edge to resize (updates the estimate).
2. **Plan my day**: one button packs today's open, unscheduled tasks into free gaps between
   events, highest priority first, respecting working hours and a 5 min buffer. Shows a
   preview you accept or undo (⌘Z works, it goes through the undoable store).
3. *(Deferred)* **Capture with a time**: "write report 14h ~1h" schedules it at 14:00 for 1 h.
4. Overlaps are allowed but shown side by side with a warning tint.

## In the notch

- **Closed notch** during a block: left wing "▍Write report", right wing "until 11:30".
  During a focus it keeps today's look (ring + countdown).
- **5 min before a block**: peek "Next: Design review · 14:00 · 50m" with **Start now** /
  **Snooze 10 min** / **Skip** (moves it to the next free slot).
- **When a block starts**: peek with **Start focus** (focus length = block length, tied to the
  task so time tracking and the check-in flow just work). No auto-start in v1.
- **Running late**: if a block ends and the task isn't done, the check-in offers
  **+5 min / Break / Done** as today, plus **Push rest of day** (shifts later blocks).

## Views

- New **Day** tab (Workspace · Day · Insights): vertical timeline for today with the hour
  grid, events (gray, calendar color stripe), task blocks (priority color), a "now" line,
  and the unscheduled tasks in a side list to drag from. ←/→ to plan tomorrow.
- Workspace Agenda card becomes **Up next**: current block + next 3 blocks/events mixed.
- Insights: planned vs actual per task (estimate vs tracked focus).

## Later (optional)

- Write blocks to a "Nook" calendar in Apple Calendar (needs write permission) so the plan
  shows on iPhone and to colleagues as busy.
- Recurring blocks (e.g. "Email 09:00 ~30m every weekday").
