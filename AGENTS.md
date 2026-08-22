# Waypoint

Waypoint is a local-only iOS SwiftUI app for tracking goals and daily tasks. The core loop:
set a goal, break it into scheduled daily tasks, and let the app help you actually get through
the day — a Today screen, a Week overview, fixed commitments (work, sleep) rendered alongside
tasks, and a scheduling engine that resolves conflicts instead of letting things silently
overlap.

The Xcode project lives in `WaypointApp/`. This file is at the repo root so any agent session
(Claude Code, Codex, etc.) picking up work here has the context it needs without re-deriving
it from scratch or re-asking the user.

## What stage this is at

Free tier first, deliberately. There is no backend (Core Data only, on-device), no real AI
planning, and no live paywall — all three are intentional non-goals *right now*, not gaps to
fill reflexively:

- **Backend/sync**: not built. Being handled by the user separately, outside this repo. Don't
  propose adding one.
- **AI planning**: `AIPlanningStub` (`Sources/Features/Goal/GoalCreateView.swift`) is a
  deliberate stub — do not build it out unless explicitly asked.
- **Pro/paywall**: `PaywallView` shows a "coming soon" badge everywhere it's gated rather than
  a working purchase flow (not ready to sell it yet). Settings has one real entry point plus a
  dev-only `theme.isPro` toggle (`SettingsView.swift`) for previewing what's unlocked.

Everything else — goals, scheduling, Today/Week/Progress, notifications, search, recurring
tasks — is real and working.

## Design philosophy

These aren't vibes, they're conclusions reached by trial and error over many rounds with the
user. Follow them without re-litigating:

- **Simple and correct over clever and fragile.** Drag-to-reorder was tried three different
  ways (SwiftUI `.draggable`, hand-rolled `GeometryReader` dragging, native `List.onMove`),
  each with real bugs, and was cut entirely rather than debugged further — you can just edit a
  task's time instead. If a feature keeps generating bugs, cutting it is a legitimate answer.
- **Accountability over convenience.** No bulk "move all unfinished tasks to tomorrow" — the
  whole point of tracking overdue tasks is that misses stay visible and get chosen
  individually, not silently swept away. Same instinct applies to anything that would let a
  user avoid seeing their own missed day. See `GoalWeekStrip` (the goal banner's 7-day strip):
  a missed day stays visibly hollow rather than resetting a hidden streak counter to zero.
- **Fixed commitments are informational, not walls.** Only sleep is a hard scheduling
  constraint. Work hours, etc. render alongside tasks but don't block them — real tasks happen
  during work.
- **Explain, then confirm, then implement.** Lay out the approach in plain terms before
  writing code, especially for anything with a design/UX dimension. The user has repeatedly
  asked for this explicitly and it has caught real mistakes before code got written.
- **The user drives the simulator, you don't.** Build/install/launch/read-logs via
  `xcodebuild`/`simctl` freely. Do not attempt to automate taps or drags — it's flaky and
  wastes effort; the user taps through the app themselves and reports back (often with
  screenshots).

## Build / test / run

Xcode project: `WaypointApp/Waypoint.xcodeproj`, scheme `Waypoint`. Bundle ID
`com.waypoint.app`. Deployment target iOS 17.0.

Find the test device first — it may be recreated across sessions, so don't hardcode the UDID
blindly:
```
xcrun simctl list devices | grep "Waypoint Test"
```

Build:
```
xcodebuild -project Waypoint.xcodeproj -scheme Waypoint -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,id=<UDID>' build
```

Test — **run the full suite** (33 tests as of this writing across `ScheduleEngineTests`,
`TaskStateTests`, `TaskReplicatorTests`, `GoalStreakTests`). Don't rely on a stale
`-only-testing` list carried over from a previous session's notes — it's easy for a new test
file to get silently excluded:
```
xcodebuild test -project Waypoint.xcodeproj -scheme Waypoint -destination 'platform=iOS Simulator,id=<UDID>'
```

Install + launch:
```
APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*Waypoint-*/Build/Products/Debug-iphonesimulator/Waypoint.app" | head -1)
xcrun simctl terminate <UDID> com.waypoint.app 2>&1 || true   # "found nothing to terminate" is harmless if it wasn't running
xcrun simctl install <UDID> "$APP"
xcrun simctl launch <UDID> com.waypoint.app
```
If the simulator's shut down: `xcrun simctl boot <UDID> && open -a Simulator`.

**Reinstalling can wipe the app's local Core Data store**, resetting it back to onboarding —
this happened repeatedly and unpredictably in practice, not just on the rare deliberate
uninstall. Warn the user before reinstalling if they have test data on the simulator they care
about; there's no backend, so once it's gone it's gone.

## Gotchas discovered the hard way

- **SourceKit shows persistent false-positive errors** like `Cannot find type 'TaskEntity' in
  scope` on files touching Core Data–generated classes, even on correct code. This is a
  standalone-indexing limitation (Core Data codegen types aren't visible to SourceKit outside
  a full Xcode build), not a real error. Trust `xcodebuild`'s actual result, not the inline
  diagnostics.
- **The simulator's region is `en_IN`**, not `en_US` (check via
  `xcrun simctl spawn <UDID> defaults read .GlobalPreferences AppleLocale`). Locale-dependent
  formatting — `DateFormatter` pattern strings *and* `Calendar.veryShortWeekdaySymbols` alike
  — produced wrong/blank output here (e.g., weekday letters). For small, fixed vocabularies
  like this, hardcode the values instead of trusting locale data.
- **New Swift files must be added to `project.pbxproj` manually** (no file-system-synchronized
  groups here) — a `PBXFileReference`, a `PBXBuildFile`, a line in the group's `children`, and
  a line in the `Sources` build phase. `xcodebuild` will fail with "cannot find type in scope"
  if any of the four is missed.
- **A view driven by its own `@State`, attached via `.overlay()` onto a `switch`-based
  conditional view, can lose that state mid-animation.** When the switch's active case
  changes (e.g., a task's `state` flips from `.pending` to `.done`, changing which view type
  `statusIcon` renders), SwiftUI tears down and rebuilds the whole subtree at that position —
  including anything overlaid on it — rather than updating it in place. Fix: keep such views
  as a stable sibling in a plain `ZStack`, not chained onto the volatile branch.
- **A `Shape` (e.g. `Circle()`) with no explicit `.frame()` expands to fill whatever space is
  proposed.** `.overlay()` implicitly constrains its content to the base view's size, which
  can mask this; moving the same view to a plain `ZStack` sibling removes that implicit
  constraint and it can balloon (this took down an entire task row's height once). Always give
  decorative shapes an explicit frame.
- **`ViewThatFits`'s ideal-size check didn't reliably predict what actually clipped** in one
  case here (a caption + a fixed-width dot strip competing for a card's width). If layout
  correctness matters, verify empirically on-device rather than trusting the fitting logic
  blindly — and prefer widening the safety margin (shorter text, tighter spacing) over
  precise-but-fragile width math.
- **`@FetchRequest`-driven views go stale when a *related* object changes but the fetched
  entity itself doesn't fire a change notification** — e.g., completing a task changes its
  goal's computed `completionFraction`, but Core Data won't notify the goal's observers. The
  established pattern here is a manually-bumped `@State` counter (`goalRefreshTrigger`) passed
  to `.id()` on the affected view to force a rebuild.

## Where things live

```
Sources/App/            Entry point, root/tab navigation, date-navigation state
Sources/Features/       One folder per screen/flow (Today, Week, Goal, Task, Settings, ...)
Sources/DesignSystem/   Shared presentational views (TaskRowView, ProgressRing, GoalWeekStrip, ...)
Sources/Models/         Core Data entity extensions, TaskDraft, Priority/TaskState
Sources/Scheduling/     ScheduleEngine (collision resolution), TaskReplicator (recurring tasks)
Sources/Theme/          ColorTokens, AccentSwatch, ThemeManager
Sources/Persistence/    PersistenceController (Core Data stack)
Sources/Notifications/  Local notification scheduling
Tests/                  XCTest targets, one file per subsystem
```

Design mockups from earlier UI passes live as Claude Design canvas files (`*.dc.html`) at the
repo root, one per major screen.
