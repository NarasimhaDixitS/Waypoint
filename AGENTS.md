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

**The app is in TestFlight and being prepared for the App Store.** Build 1.0 (2) is with
external testers. Subscriptions exist as real products in App Store Connect
(`waypoint.pro.monthly` $1.99/mo, `waypoint.pro.annual` $19.99/yr, group "Waypoint Pro"), and
the free tier is real, gated code — not a mockup.

Still deliberate non-goals right now:

- **Backend/sync**: not built, and not to be proposed. Core Data on-device only. The user is
  handling any backend separately, outside this repo.
- **AI planning**: removed. `AIPlanningStub` is gone — do not reintroduce it.

**The one real gap is RevenueCat.** `SubscriptionManager.purchase` currently writes to
`UserDefaults`; no money changes hands and no StoreKit is involved. Until that's replaced, the
app cannot be submitted for App Store review. Integration touches exactly three function
bodies — `refresh`, `purchase`, `restore` — and must not change the gates
(`canViewDay`, `canEditDay`, `canUseWeekTab`, `canUseProgress`, `canCreateGoal`).

**`BetaAccess.swift` is what makes that safe to ship to testers.** It detects
`embedded.mobileprovision` — present in TestFlight and development builds, stripped by the App
Store — and unlocks everything, with a 2027-03-01 date backstop because the check fails in the
dangerous direction if it fails at all. It is a `var` only so tests can disable it: ten
free-tier tests went green for the wrong reason the moment it was added. **Delete the whole
file when RevenueCat lands.**

## Design philosophy

These aren't vibes, they're conclusions reached by trial and error over many rounds with the
user. Follow them without re-litigating:

- **Simple and correct over clever and fragile.** Drag-to-reorder was tried three different
  ways (SwiftUI `.draggable`, hand-rolled `GeometryReader` dragging, native `List.onMove`),
  each with real bugs, and was cut entirely rather than debugged further — you can just edit a
  task's time instead. Row swipe-to-delete was cut for the same reason: it fought the
  day-change swipe, committing at 78pt against the day's 55pt, so it could never fire alone.
  If a feature keeps generating bugs, cutting it is a legitimate answer.
- **Accountability over convenience.** No bulk "move all unfinished tasks to tomorrow" — the
  whole point of tracking overdue tasks is that misses stay visible and get chosen
  individually. An overdue task's checkbox is disabled (completion is locked to its own day),
  and its reschedule button opens the editor rather than moving it to tomorrow in one tap:
  one tap is how a task gets pushed fourteen times without anyone noticing. See
  `GoalWeekStrip` for the same instinct at goal scale — a missed day stays visibly hollow.
  **The line is direction, not bulk:** operating on *future* tasks is planning and is fine;
  operating on *past* ones is erasing the record and is not.
- **Fixed commitments are informational, not walls.** Only sleep is a hard scheduling
  constraint. Work hours, etc. render alongside tasks but don't block them — real tasks happen
  during work.
- **Explain, then confirm, then implement.** Lay out the approach in plain terms before
  writing code, especially for anything with a design/UX dimension. The user has repeatedly
  asked for this explicitly and it has caught real mistakes before code got written.
- **The user drives the simulator, you don't.** Build/install/launch/read-logs via
  `xcodebuild`/`simctl` freely, and use the `-wp…` launch flags below to land on a screen. Do
  not attempt to automate taps or drags — it's flaky and wastes effort; the user taps through
  the app themselves and reports back (often with screenshots).

## Build / test / run

Xcode project: `WaypointApp/Waypoint.xcodeproj`, scheme `Waypoint`. Bundle ID
**`com.narasimhadixit.waypoint`** (widget: `.widget`). Team `23495RS836`. iPhone only
(`TARGETED_DEVICE_FAMILY = 1`). Deployment target iOS 17.0.

> The bundle ID was `com.waypoint.app` until Oct 2026. It changed because the only provisioning
> profiles are for the new one, and the simulator never checks provisioning — which is the
> likeliest reason the widget never worked on hardware.

Find the test device first — it may be recreated across sessions, so don't hardcode the UDID
blindly:
```
xcrun simctl list devices | grep "Waypoint Test"
```

Build:
```
xcodebuild -project Waypoint.xcodeproj -scheme Waypoint -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,id=<UDID>' build
```

Test — **run the full suite** (185 tests across 15 files in `Tests/`). Don't rely on a stale
`-only-testing` list carried over from a previous session's notes — it's easy for a new test
file to get silently excluded:
```
xcodebuild test -project Waypoint.xcodeproj -scheme Waypoint -destination 'platform=iOS Simulator,id=<UDID>'
```

Install + launch — **resolve the app bundle path from `xcodebuild -showBuildSettings`, never by
globbing `DerivedData`.** A glob (even sorted by mtime) is a heuristic that can pick a stale or
unrelated project's build by accident (see the gotcha below); asking the build system directly
for `TARGET_BUILD_DIR`/`FULL_PRODUCT_NAME` is exact:
```
SETTINGS=$(xcodebuild -project Waypoint.xcodeproj -scheme Waypoint -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,id=<UDID>' -showBuildSettings 2>/dev/null)
TARGET_BUILD_DIR=$(echo "$SETTINGS" | awk -F ' = ' '/ TARGET_BUILD_DIR /{print $2; exit}')
FULL_PRODUCT_NAME=$(echo "$SETTINGS" | awk -F ' = ' '/ FULL_PRODUCT_NAME /{print $2; exit}')
APP="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
xcrun simctl terminate <UDID> com.narasimhadixit.waypoint 2>&1 || true   # "found nothing to terminate" is harmless
xcrun simctl install <UDID> "$APP"
xcrun simctl launch <UDID> com.narasimhadixit.waypoint
```
If the simulator's shut down: `xcrun simctl boot <UDID> && open -a Simulator`.

**`sleep` is blocked in this harness's foreground shell** (it returns instantly, so a
screenshot taken "after" it catches a half-drawn screen). Use `python3 -c "import
time;time.sleep(10)"` instead, and give the app ~10s before capturing.

**Reinstalling can wipe the app's local Core Data store**, resetting it back to onboarding —
this happened repeatedly and unpredictably in practice, not just on the rare deliberate
uninstall. Warn the user before reinstalling if they have test data on the simulator they care
about; there's no backend, so once it's gone it's gone.

### Debug launch flags

All `#if DEBUG`. They exist because the alternative is asking whoever holds the simulator to go
and tap through to a screen, which is the gap that led to shipping cards nobody had seen drawn.

| Flag | Lands on |
| --- | --- |
| `-wpTab <0-3>` | A given tab |
| `-wpSection <name>` | A section within a tab |
| `-wpDay <n>` | Today offset by n days |
| `-wpNewTask` | Task editor, open |
| `-wpEditTask` | Task editor on today's first task |
| `-wpClash` | The collision sheet, staged against today's first task |
| `-wpReseed` | Reloads the demo fixture (in `init`, deliberately — see `WaypointApp.swift`) |
| `-wpPaper` / `-wpStandard` | Forces the palette |
| `-wpFree` | Free tier, with `BetaAccess` off |

`-wpPaper`/`-wpStandard` are not a convenience: writing `themePalette` from the command line
races the app's own preference flush and loses about as often as it wins, so a palette set that
way can't be trusted to be the one on screen.

There is **no flag for light/dark** — `appearanceMode` lives in `UserDefaults`, which the
cfprefsd gotcha below makes unwritable from the CLI. Ask the user to tap the sun/moon toggle.

## Gotchas discovered the hard way

- **`surface0` and `surface1` are one surface at two depths, never a separator.** In light mode
  they are `#F5F5F3` and `#FFFFFF` — a 4% difference. Three separate bugs have come from
  treating them as contrast: the clash sheet's "invisible" buttons (fixed by restoring the
  *border*, not by swapping the fill), and both editor sheets reading as "a white page pasted
  on a grey one". If you need an edge, use `ColorTokens.border` or a shadow.

- **Editing a UserDefaults-backed plist file directly on disk does not take effect on
  relaunch**, even though the file itself is correctly updated. The simulator's `cfprefsd`
  caches domain contents in memory and doesn't notice a raw file write. Fix: find and kill the
  *simulator's own* `cfprefsd daemon` process from the host shell (`ps aux | grep cfprefsd` —
  the one running from inside `.../CoreSimulator/.../RuntimeRoot/usr/sbin/cfprefsd daemon`,
  not the host macOS one at `/usr/sbin/cfprefsd`), then relaunch. `xcrun simctl spawn <UDID>
  killall cfprefsd` does NOT work — `killall` isn't in the simulator's stripped runtime. Also:
  `xcrun simctl spawn <UDID> defaults write <bundle-id> key value` silently writes to the wrong
  location (resolves HOME to the simulator's root, not the app's container) — find the real
  file with `xcrun simctl get_app_container <UDID> <bundle-id> data` and `plutil -replace` it.

- **iOS allows 64 pending local notifications per app, total — and silently discards the
  overflow.** `add` reports no error. `NotificationManager` therefore schedules against a 48h
  rolling window with a priority-ordered budget (`remindableTasks`), reserving slots for
  non-task notifications. Any change that schedules more must keep that budget intact.

- **Three things fail by reporting success**, so verify them on real hardware, never in the
  simulator: a missing entitlement (`.timeSensitive` without
  `com.apple.developer.usernotifications.time-sensitive` is silently downgraded); an App Group
  identifier that doesn't match exactly (`containerURL` returns nil, indistinguishable from a
  missing entitlement); and the notification budget above. The app and widget have **separate**
  entitlements files in `Generated/` — a shared one would make the widget request
  time-sensitive, which its App ID lacks, and fail the build.

- **`.simultaneousGesture` never loses.** It runs alongside other gestures, so a
  container-level drag fires for every horizontal drag on screen. `TodayView` excludes the goal
  carousel from the day swipe by testing `carouselFrame.contains(value.startLocation)` in a
  named coordinate space — not by trying to make one gesture beat the other.

- **`.buttonStyle(.plain)` fades its label while pressed.** Usually right, occasionally
  catastrophic: on the tab bar the badge circle is the only thing covering `NotchedBarShape`'s
  pocket, so the fade opened a window onto the notch and read as the bar developing a sharp
  dip. Use `UnfadedButtonStyle` where a button is acting as a lid.

- **Paper is a palette, not a third appearance.** `ColorTokens.dynamic(light:dark:)` resolves
  through `UIColor`'s trait collection, which knows only two states, so paper lives on its own
  axis in `Palette.swift` and hands `dynamic` the same value twice. It is fully monochrome —
  `PaletteContrastTests` asserts that nothing in paper carries a hue, which is the test that
  would have caught the first attempt (a sepia accent on cream, which read as a ninth accent).

- **Stale/duplicate `DerivedData` folders from deleted project copies can get installed by
  mistake.** Xcode names them `<ProjectName>-<hash>`, so a since-deleted project that shared
  the name "Waypoint" leaves a folder that looks identical at a glance. This silently installed
  an old binary once. The `-showBuildSettings` command above removes the ambiguity. If a stale
  folder reappears, `ls ~/Library/Developer/Xcode/DerivedData | grep Waypoint` and check each
  match's `info.plist` `WorkspacePath`.

- **SourceKit shows persistent false-positive errors** like `Cannot find type 'TaskEntity' in
  scope` on files touching Core Data–generated classes, even on correct code. Core Data codegen
  types aren't visible to SourceKit outside a full Xcode build. Trust `xcodebuild`'s result.

- **The simulator's region is `en_IN`**, not `en_US`. Locale-dependent formatting —
  `DateFormatter` pattern strings *and* `Calendar.veryShortWeekdaySymbols` alike — produced
  wrong/blank output here (e.g. weekday letters). For small fixed vocabularies, hardcode.

- **New Swift files must be added to `project.yml`**, then regenerate with XcodeGen. Sources
  are listed per-target; the widget pulls a hand-picked subset of `Sources/` plus `Resources/`.

- **A view driven by its own `@State`, attached via `.overlay()` onto a `switch`-based
  conditional view, can lose that state mid-animation.** When the switch's active case changes,
  SwiftUI tears down and rebuilds the whole subtree at that position — including anything
  overlaid on it. Keep such views as a stable sibling in a plain `ZStack`.

- **A `Shape` with no explicit `.frame()` expands to fill whatever space is proposed.**
  `.overlay()` implicitly constrains its content; a plain `ZStack` sibling doesn't, and it can
  balloon (this took down a task row's height once, and later stretched the clash sheet's
  cards). Always give decorative shapes an explicit frame.

- **`@FetchRequest`-driven views go stale when a *related* object changes** — completing a task
  changes its goal's computed `completionFraction`, but Core Data won't notify the goal's
  observers. The established pattern is a manually-bumped `@State` counter
  (`goalRefreshTrigger`) passed to `.id()` on the affected view.

- **`strings -F` misses strings containing an em-dash.** Use `strings -a` when checking whether
  something was stripped from a built binary. And remember it proves presence, not absence.

## Where things live

```
Sources/App/            Entry point, root/tab navigation, date-navigation state
Sources/Features/       One folder per screen/flow (Today, Week, Goal, Task, Progress,
                        Paywall, Pomodoro, Settings, Schedule, Onboarding, AdhocBump, Completion)
Sources/DesignSystem/   Shared presentational views (TaskRowView, ProgressRing, GoalWeekStrip,
                        PaywallLock, ...)
Sources/Models/         Core Data entity extensions, TaskDraft, Priority/TaskState, SampleData
Sources/Scheduling/     ScheduleEngine (collision resolution), TaskReplicator (recurring tasks)
Sources/Subscription/   Subscription plans + gates, TrialRecord (Keychain), BetaAccess
Sources/Theme/          ColorTokens, AccentSwatch, Palette, ThemeManager
Sources/Persistence/    PersistenceController (Core Data stack, recovery)
Sources/Notifications/  Local notification scheduling and the 64-slot budget
WaypointWidget/         Widget extension sources
Resources/              Assets + PrivacyInfo.xcprivacy (both targets pull this)
Generated/              Info.plists and the two separate entitlements files
Tests/                  XCTest targets, one file per subsystem
docs/privacy/           The published privacy policy (GitHub Pages, /docs on main)
```

The trial start is in the **Keychain**, not `UserDefaults`, so deleting and reinstalling the
app does not grant a second 14-day trial. Verified against a real `simctl uninstall`.
