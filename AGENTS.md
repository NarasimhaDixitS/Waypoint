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

**The app is in TestFlight and being prepared for the App Store.** Builds through 1.0 (9) are
uploaded and the public TestFlight link is live; build 9 is the one staged for review, and the
monthly/annual products are gone from both App Store Connect and RevenueCat. Version 1.0 was
**rejected** on 2026-10-27 (submission `d733a453`) under guidelines 2.1(b) and 3.1.2(c) — both
causes are written up below, because both were avoidable and neither was a code bug.

**Waypoint is sold once, not rented.** One non-consumable in App Store Connect:
`waypoint.pro.lifetime`, $5.99, id `6827496691`, display name "Waypoint Pro". It replaces
`waypoint.pro.monthly` and `waypoint.pro.annual`, which were only ever bought in sandbox and are
not being submitted — so there was nobody to migrate. There is no server and no account here, so
no recurring cost existed for a renewal to fund, and a 14-day trial means nobody buys on faith
either. It also deleted a category of bug rather than fixing one: lapsed, cancelled, refunded and
card-declined were each a state the app had to detect, name and draw, and six bugs came out of
exactly that in one afternoon. **Do not reintroduce a subscription** without re-reading that
commit (`e1338cc`) first. The free tier is real, gated code — not a mockup.

Still deliberate non-goals right now:

- **Backend/sync**: not built, and not to be proposed. Core Data on-device only. The user is
  handling any backend separately, outside this repo.
- **AI planning**: removed. `AIPlanningStub` is gone — do not reintroduce it.

**The purchase is real and wired up.** RevenueCat is integrated: `Sources/Subscription/Store.swift`
is the only thing that talks to the SDK, and `SubscriptionManager`'s `refresh`/`purchase`/`restore`
go through it. Dashboard side: entitlement `pro`, offering `default`, one `$rc_lifetime` package
holding `waypoint.pro.lifetime`. A lifetime entitlement arrives with `willRenew == false` and
`expirationDate == nil`, which is why nothing reads either field any more — the old derivation
would have told every paying customer "won't renew" on day one. The gates — `canViewDay`, `canEditDay`, `canUseWeekTab`, `canUseProgress`,
`canCreateGoal` — are tested against `SubscriptionStatus` rather than against a network, which is
the whole reason the SDK sits behind a seam. Don't change a gate to accommodate the store.

`BetaAccess.swift` is **deleted**. It unlocked everything in TestFlight builds while purchases were
a `UserDefaults` mock; keeping it after RevenueCat landed would mean no tester ever exercised the
real path. Do not reintroduce it — `-wpFree` is how you get the free tier now.

**The purchase path is verified on real hardware, on this product.** `waypoint.pro.lifetime` was
bought in the sandbox on an iPhone on 2026-10-27, against build 9. RevenueCat recorded it as active
with unlimited duration, the gates opened, and nothing in Settings or on the paywall said anything
about renewing or expiring — which was the one thing that could not be checked anywhere but on
device, because a lifetime entitlement arrives with `willRenew == false` and `expirationDate == nil`
and the pre-lifetime code would have drawn that as "Ends 1 Jan 4001 — won't renew". The simulator
cannot answer it: with no App Store account signed in, a purchase cannot complete there however
correct the dashboard is. **Fetching prices is a separate matter and does work** — product metadata comes
back from the App Store without an account, so the simulator paywall shows the genuine localized
price (verified: `-wpPaywall` rendered $5.99 the same day the product was created, and the old
products it could have been caching were $1.99 and $19.99). That makes a simulator capture valid
as the App Store Connect review screenshot, and the em dash is a network failure, not a baseline.

**Apple's subscription disclosure list is four items, not three** — title, length, price, and
working links to the Terms of Use (EULA) and privacy policy, all at the point of purchase. Build 5
was rejected under 3.1.2(c) with the title missing: the plan rows said "Monthly" and "Annual",
which are lengths, and nothing on the paywall named "Waypoint Pro". A source comment in
`PaywallView` claiming the list had three items is what made that a blind spot. Guideline 3.1.2
governs auto-renewable subscriptions and so no longer applies to a non-consumable — but the
paywall still names the product, shows its price, and carries both links, because removing
something a reviewer has already been shown invites the question of why. The metadata side was
separate and also required, and is already fixed: the privacy policy in the Privacy Policy field,
the EULA link in the **App Description** (or the EULA field), for every localization.

**Creating a product in App Store Connect does not submit it for review.** Both subscriptions sat
at `READY_TO_SUBMIT` with complete metadata, prices and review screenshots while build 5 went to
review without them, which is an automatic 2.1(b) rejection: "the app includes references to
subscriptions but the associated In-App Purchase products have not been submitted." A product has
to be a line item **inside** the version's review submission. Note that the API will not do this:
`reviewSubmissionItems` accepts `appStoreVersion`, custom product pages, app events and
experiments, and returns 409 `ENTITY_ERROR.RELATIONSHIP.UNKNOWN` for a purchase — it is a
checkbox on the version page in the ASC web UI.

**Launch state** — listing, screenshots, privacy label, the website repo and the TestFlight public
link — lives in the session memory rather than here, because it changes daily and this file
shouldn't rot behind it.

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

Test — **run the full suite** (253 tests across 24 files in `Tests/`). Don't rely on a stale
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
| `-wpReseed` | Reloads the demo fixture, and clears both onboarding gates |
| `-wpPaper` / `-wpStandard` | Forces the palette |
| `-wpFree` | Free tier |
| `-wpSearch <query>` | The search overlay, with that query typed |
| `-wpGoal` / `-wpNoGoal` | Straight into a goal's page, or the No-goal list |
| `-wpFresh` | **Wipes everything** and gives you a real first run |
| `-wpFocus` | The focus timer, on today's first task |
| `-wpFocusFill <0-1>` | …already that far through, and running |
| `-wpPaywall` | The paywall, open |
| `-wpTrial` | A fresh 14-day trial (the mirror of `-wpFree`) |

`-wpPaper`/`-wpStandard` are not a convenience: writing `themePalette` from the command line
races the app's own preference flush and loses about as often as it wins, so a palette set that
way can't be trusted to be the one on screen.

`-wpTrial` exists because the trial deliberately survives everything — it lives in the Keychain
so deleting the app can't buy a second one, which also means nothing outside the app can put it
back. Without it the only ways to see an unlocked Week or Progress are to wait out a real
fortnight, tap the Settings button, or run `-wpFresh` and lose the data that made the screen
worth looking at. **`-wpReseed` now clears `hasSeenWelcome` *and* `hasCompletedOnboarding`** —
`RootView` has two gates, not one, and setting only the second leaves the fixture stuck on the
welcome screen. The fixture is an established user with forty-five days of history; landing that
person on onboarding contradicts the thing being staged.

`-wpPaywall` exists because the purchase screen is otherwise behind a lapsed trial or a tap into
a locked feature, and because App Store Connect wants a review screenshot of it. It is good for
looking at the layout and not for that screenshot — see the hardware note above. There is no
`-wpRenewal` any more: it forced `renewing`/`cancelled`/`billing`, and a purchase has none of
those states.

`-wpFresh` is the one to reach for when testing onboarding, the empty Progress page or the
trial. Loading the demo fixture is its opposite — forty-five days of history is exactly what a
new user doesn't have — and deleting the app doesn't do it either, because the trial start
lives in the Keychain on purpose (`TrialRecord`) and survives reinstalling. Settings' Developer
section has the same thing as a button, which quits the app afterwards so the trial can't
re-begin before the relaunch.

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

- **Deleting a task does not delete it for four seconds, and `ScheduleEngine` has to be told.**
  `PendingDeletions` holds the undo window: the row leaves the screen immediately, the real
  `context.delete` happens when the window elapses. Anything that reasons about what occupies a
  day must therefore read tasks through `ScheduleEngine.tasks(on:context:)`, the one private
  helper that filters the pending set out — **never fetch `TaskEntity.fetchRequest(on:)`
  directly inside the engine.** When the hidden set was `@State` on `TodayView` instead, the
  engine kept scheduling around tasks that had already left the screen: deleting a task and
  creating another in the same slot raised the bump prompt against an invisible task, and
  `TaskReplicator` silently skipped recurring occurrences for colliding with ghosts. The store
  is read as a singleton rather than passed as a defaulted `excluding:` argument precisely so a
  new call site can't opt back into that by omission.

  The same window is why `WaypointApp` calls `finalize()` on `scenePhase == .background`. The
  commit used to be a bare `DispatchQueue.main.asyncAfter` with nothing watching the lifecycle,
  so a process killed inside those four seconds lost the delete and the task came back — and
  iOS terminates suspended apps constantly, which made "delete a task, leave the app" a
  reliable way to resurrect it. `.background`, not `.inactive`: inactive fires for a pulled-down
  notification banner, and committing there would snatch Undo away mid-look.

- **Changing what is sold leaves copy behind in the gates.** The lifetime rewrite moved every
  file in `Sources/Subscription/` and the paywall, and still shipped four strings telling people
  to *subscribe*: the two Progress lock messages in `MainTabView`, the Week lock message, and the
  new-iPhone card in Settings. They were invisible because a gate message only renders while
  locked, and development runs unlocked. Build 8 went to TestFlight saying "Subscribing is what
  keeps reading them back" under a store listing promising a one-time purchase. It was caught by
  a marketing screenshot of the Progress tab, not by a test. Grep string *literals* — not
  identifiers, which are full of legitimate `subscription` — after any change to what the app
  sells.

- **To re-lock a sandbox entitlement, detach the product from the entitlement in RevenueCat.**
  Testing a purchase needs the gates shut, and once anything has been bought they stay open. Nothing
  on the device reopens them: RevenueCat identifies the buyer by an anonymous app user ID in
  `UserDefaults`, so signing in as a different sandbox Apple Account changes nothing, and deleting
  the app costs the local tasks while the trial survives in the Keychain regardless. The API is no
  help either — `POST /v2/sandboxTesters` is 403 (`GET_COLLECTION` and `UPDATE` only), so testers
  are web-UI only. The lever is the dashboard, because entitlements are mapped server-side from
  purchased products: detach the bought product from `pro` (Product catalog → **Entitlements** →
  `pro`, *not* the offering, which only controls what is offered) and the receipt grants nothing.
  This is how the leftover annual subscription was cleared so the lifetime purchase could be tested
  at all. Force-quit before looking — `customerInfo` is cached on device for a few minutes, so a
  plain background-and-return hands back the stale "you have Pro". Reattaching restores it.

- **Verify the exported IPA, never the `.xcarchive`.** The archive's `.app` is signed for
  development and carries `get-task-allow: true`; export re-signs it for distribution and flips
  that to false. Checking the archive therefore reports a problem that isn't real — and, worse,
  would report "Apple Distribution" missing on a perfectly good build. Unzip
  `export<n>/Waypoint.ipa` and inspect `Payload/Waypoint.app`. On build 8 the archive said
  `get-task-allow: true` and the shipped IPA said false, which is the expected pair, not a bug.

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
Sources/Subscription/   Subscription plans + gates, TrialRecord (Keychain), Store (RevenueCat)
Sources/Theme/          ColorTokens, AccentSwatch, Palette, ThemeManager
Sources/Persistence/    PersistenceController (Core Data stack, recovery)
Sources/Notifications/  Local notification scheduling and the 64-slot budget
WaypointWidget/         Widget extension sources
Resources/              Assets + PrivacyInfo.xcprivacy (both targets pull this)
Generated/              Info.plists and the two separate entitlements files
Tests/                  XCTest targets, one file per subsystem
```

The trial start is in the **Keychain**, not `UserDefaults`, so deleting and reinstalling the
app does not grant a second 14-day trial. Verified against a real `simctl uninstall`.
