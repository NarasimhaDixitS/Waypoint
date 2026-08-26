# Waypoint Design System

Extracted directly from `WaypointApp/Sources/Theme/` and `Sources/DesignSystem/` plus
representative feature screens (Today, Week, Settings, New Task). Every value below is copied
from real code, not inferred or invented — file paths are given throughout so anything here can
be re-verified against source. Where the codebase has no defined rule, that's called out
explicitly rather than guessed.

---

## 1. Color Palette

Source: `Sources/Theme/ColorTokens.swift`, `Sources/Theme/AccentSwatch.swift`.

Every token is defined as `dynamic(light:dark:)` (a `UIColor` trait closure) unless noted
"fixed" — the same token name automatically resolves to the right value in light or dark mode.
Base palette is warm and slightly desaturated — **never pure black/white**.

| Token | Light | Dark | Role |
|---|---|---|---|
| `surface0` | `#F5F5F3` | `#1C1C1A` | Screen background |
| `surface1` | `#FFFFFF` | `#242422` | Card / row background |
| `textPrimary` | `#2C2C2A` | `#F1EFE8` | Primary text (warm off-white in dark, not `#FFF`) |
| `textSecondary` | `#5F5E5A` | `#B4B2A9` | Secondary/meta text |
| `textMuted` | `#888780` (fixed, same both modes) | | Least-emphasis text/icons |
| `border` | `#E5E3DB` | `#3A3A37` | Hairlines, unstroked-state rings |
| `cardShadow` | `black @ 7% opacity` (fixed) | | The one shadow value in the app — see §4 |

**Semantic status colors** — each is a `(base, text, tint)` triple. `base` = solid fill (icons,
dots, filled rings). `text` = the readable-on-`surface1` variant. `tint` = the base mixed 24%
over `surface1`'s own light/dark value (`ColorTokens.mix`), used as a status row's background
wash.

| Status | Base (fixed unless noted) | Text (light / dark) | Tint (light / dark) |
|---|---|---|---|
| Success / done | `#639922` | `#3B6D11` / `#C0DD97` | mix(`#639922`, 24%) over `#FFF` / `#242422` |
| In progress | `#378ADD` (light) / `#85B7EB` (dark) | `#185FA5` / `#B5D4F4` | mix over `#FFF` / `#242422` |
| Warning / overdue | `#D85A30` | `#B0431E` / `#F0A583` | mix over `#FFF` / `#242422` |
| Scheduled / future | `#7B5EA7` (light) / `#B79BDB` (dark) | `#5C4380` / `#D3C0EE` | mix over `#FFF` / `#242422` |

These are **fixed semantic roles, independent of the user's accent color** — a task's
done/overdue/in-progress/future state always reads in the same hue regardless of theme
customization.

**Accent (user-customizable, `AccentSwatch.swift`)** — one flat hex per swatch, *not*
light/dark-adaptive:

| Swatch | Hex |
|---|---|
| Green | `#3B6D11` |
| Blue | `#378ADD` |
| Orange | `#D85A30` |
| Pink | `#D4537E` |

Note: Orange and Pink accents share their exact hex with the Warning and Scheduled-adjacent
semantic tokens above. Not a bug, but worth knowing — an orange-accented button and an overdue
task badge use the identical color by coincidence of the palette, not by design relationship.

**`CurvedBackground` zones** (`Sources/DesignSystem/CurvedBackground.swift`) — not static
tokens; computed at render time as the *accent color* mixed over a near-black/near-white base:

| | Base | Top zone mix | Bottom zone mix |
|---|---|---|---|
| Dark | `#0E0D0C` | accent @ 32% | accent @ 10% |
| Light | `#FAF9F6` | accent @ 24% | accent @ 6% |

Used only on Today, Week, and Progress — not app-wide (see §6).

**Flagged inconsistency**: `Sources/Models/Priority.swift`'s `tintColor` hardcodes raw RGB
literals (`Color(red: 0.847, green: 0.353, blue: 0.188)` for High, `0.831/0.325/0.494` for
Medium) that duplicate `ColorTokens.warning` (`#D85A30`) and the Pink accent (`#D4537E`) instead
of referencing them. `Priority.low` falls back to system `Color.secondary` rather than a
`ColorTokens` value — the one place in the app that isn't using the token system.

---

## 2. Typography Scale

Source: `Sources/DesignSystem/Typography.swift` — a closed 6-case enum, applied via
`.wpTypography(_:)`. Every size is anchored to a matching system text style via
`UIFontMetrics`, so Dynamic Type scales each role proportionally rather than uniformly.

| Role | Size | Weight | Tracking | Scales relative to |
|---|---|---|---|---|
| `appTitle` | 29 | semibold | `-0.5` | `.largeTitle` |
| `screenTitle` | 23 | semibold | 0 | `.title2` |
| `cardTitle` | 14.5 | semibold | 0 | `.headline` |
| `body` | 13 | regular | 0 | `.subheadline` |
| `micro` | 11 | regular | 0 | `.caption2` |
| `bigStat` | 19 | semibold | 0 | `.title3` |

**Flagged gap**: no dedicated "button label" or "input field" role — buttons hardcode their own
`.font(.system(size: 15, weight: .semibold/.medium))` directly in `PrimaryButtonStyle` /
`SecondaryButtonStyle` (`Sources/DesignSystem/Buttons.swift`) rather than going through
`WPTypography`. If you add a 7th role, `buttonLabel` at 15pt would formalize an already-real,
just-undeclared size.

---

## 3. Spacing Scale

**There is no defined spacing constant/enum anywhere in the codebase** — every padding and gap
value below is a literal repeated by convention across files, not a named token. Treat this
table as the *de facto* scale inferred from usage, and flag it to the user if introducing a
formal `Spacing` enum is ever wanted.

| Value | Where it shows up |
|---|---|
| 4 | Tight internal gaps (icon-to-label in small rows) |
| 6–9 | Row-internal `HStack`/`VStack` spacing (task row title/meta gap: 3, icon gaps: 5–7) |
| 8 | Common small vertical rhythm (label-to-control gap in form fields) |
| 10 | Card-list gaps (Today's task stack `VStack(spacing: 10)` in some screens, 8–9 in others — **inconsistent**, not a fixed value) |
| 12 | `HStack` spacing inside a row (`TaskRowView`'s icon/text gap) |
| 14 | The single most common card/button internal padding (`CardBackground` default, `PrimaryButtonStyle`/`SecondaryButtonStyle` vertical padding, Settings row padding) |
| 16 | Section-to-section `VStack` spacing on some screens (Today) |
| 18–20 | Section-to-section `VStack` spacing on others (Week: 18; several: 20) — **inconsistent**, both used |
| 20 | Universal screen horizontal margin — every top-level screen (`Today`, `Week`, `Progress`, `Settings`) uses `.padding(.horizontal, 20)` with no exception found |
| 24 | Bottom padding on scroll content (most screens) |
| 100 | Today's bottom padding specifically (extra room to clear the FAB) |

**Consistent, safe to rely on**: 20pt horizontal screen margin, 14pt card/button internal
padding. **Not consistent**: inter-section vertical spacing (16 vs 18 vs 20 all appear), and
inter-row-in-a-list spacing (8, 9, and 10 all appear across different screens). A new screen
should default to 20pt margins + 14pt card padding, and pick one inter-section value (18 is the
most common single choice) rather than copying whichever screen happens to be open.

---

## 4. Component Style Rules

### Corner radius
No named constant — a consistent *tiered* pattern by component size, purely from repetition:

| Radius | Used for |
|---|---|
| 14 | Buttons (`PrimaryButtonStyle`/`SecondaryButtonStyle`), text fields, small pickers/pill buttons |
| 18 | Cards, task rows, day cards — the standard "content card" radius |
| 20 | The goal banner card specifically |
| 22–26 | Bottom sheets / modal cards (`DeleteConfirmSheet`: 26) |
| `Capsule()` | Pills — "Jump to today" button, `ProBadge`, page-dot indicators, tab bar |

### Shadow
Exactly one shadow in the entire app: `ColorTokens.cardShadow` = `black @ 7% opacity`, applied
via `CardBackground` (`Sources/DesignSystem/CardBackground.swift`) as
`.shadow(color: cardShadow, radius: 6, x: 0, y: 2)`. No elevation tiers — everything that has a
shadow has *this exact* shadow. Flat, low-elevation look by design.

### Borders
`ColorTokens.border`, stroke width varies by context: 1pt (`SecondaryButtonStyle`,
priority-unselected outline), 1.6pt (unselected status-icon rings, priority-selected outline),
1.8–2pt (selected accent-swatch ring in Settings, in-progress status ring). No named "thin/thick"
tokens — width is chosen per-component.

### Buttons (`Sources/DesignSystem/Buttons.swift`)
Two `ButtonStyle`s, both full-width, both 14pt corner radius, both 14pt vertical padding:
- **Primary** (`.wpPrimary`): solid fill (`tint`, defaults to `textPrimary`), configurable
  foreground (defaults to `surface0`) — i.e. defaults to an inverted pill, but every real call
  site overrides `tint` to `theme.accentSwatch.color`.
- **Secondary** (`.wpSecondary`): `surface1` fill + 1pt `border` stroke, `textPrimary` foreground.
- Both: press state = 85% opacity (+ 0.98 scale for Primary only), light impact haptic on press.

### Cards (`CardBackground.swift`)
One modifier, `.wpCard(padding:fill:cornerRadius:)`, defaults `padding: 14`, `fill: surface1`,
`cornerRadius: 18`. This is the single source of the "card" look — every card in the app either
uses this modifier or manually replicates its three parameters.

### Status-driven components
Not a generic "input field" system, but a strong, repeated pattern for *stateful* rows
(`TaskRowView`): a `TaskState` (done/overdue/future/inProgress/pending) drives title color, meta
text color (at 85% opacity except `pending`), background tint, and status-icon ring color, all
pulled from the same semantic token family in lockstep — see the state→color switch statements
in `Sources/DesignSystem/TaskRowView.swift` as the canonical example to copy for any new
stateful list row.

### Motion
Sparse and purpose-built, not decorative:
- Spring bounce on interaction (`response: 0.32, dampingFraction: 0.45` on task-row tap).
- Real-time-driven fill (`TaskProgressWave`): a `TimelineView`-clocked Canvas wave, not a looped
  animation — literally tracks elapsed-time-of-day.
- One-shot celebration (`CompletionBurst`): ring pulse + 6 flung particles, fires once per
  completion via a monotonic trigger counter, explicitly *not* built with `keyframeAnimator`
  (didn't render correctly in that overlay position per its own doc comment).
- `ProgressRing` pulses once at 98%+ completion, not continuously.

---

## 5. Layout & Navigation Patterns

Source: `Sources/App/MainTabView.swift`, `RootView.swift`, and sheet-handling code across
`TodayView`/`WeekView`/`GoalDetailView`.

- **Root shape**: native `TabView`, 4 tabs (Today/`sun.max`, Week/`calendar`,
  Progress/`chart.bar.fill`, Settings/`gearshape`), each tab wrapped in its own `NavigationStack`.
- **Every screen hides the native nav bar** (`.navigationBarHidden(true)`) and draws its own
  in-content title (`Text(...).wpTypography(.screenTitle)`) instead — `NavigationStack` is used
  purely as a push/pop container, not for chrome. A couple of Settings sub-pages
  (`ScheduleSetupView`, `SleepSetupView`) are reached via plain `NavigationLink` push — the one
  place push navigation is used instead of a sheet.
- **Everything else is a sheet.** Task detail/creation, goal creation, the paywall, pickers
  (time/duration/goal), and multi-step flows all present via `.sheet`.
- **One `ActiveSheet` enum per screen, `.sheet(item:)`, never stacked `.sheet(isPresented:)`
  calls.** This is a deliberate, explicitly-commented architectural rule (see the doc comment
  above `ActiveSheet` in `TodayView.swift`): SwiftUI doesn't reliably support two simultaneous
  independent `.sheet` modifiers on one view, so every screen with multiple possible modals
  funnels them through a single `enum ActiveSheet: Identifiable` and one `.sheet(item:)` call.
  **Any new modal on an existing screen should add a case to that screen's `ActiveSheet` enum,
  not a second `.sheet(isPresented:)`.**
- **Swapping one sheet for another sheet-of-a-different-case never happens directly** — always
  dismiss (`activeSheet = nil`) and re-present via a queued follow-up
  (`queuedSheet`/`handleSheetDismissed`), because presenting a new sheet mid-dismissal is
  unreliable. Same reasoning extends to sheet→alert sequencing (`pendingRepeatResult` pattern):
  set the alert's content from the sheet's `onDismiss` callback, not from inside the sheet's own
  button action.
- **Confirmation pattern is inconsistent**: destructive confirmations use *two different* UI
  shapes — a custom bottom-anchored card with `.presentationDetents` (`DeleteConfirmSheet`) in
  one place, and native `.confirmationDialog` (goal deletion in `GoalDetailView`) in another.
  Both exist in the current codebase; pick the custom-card style for new destructive
  confirmations if consistency with the more common pattern matters.
- **Universal screen structure**: `ScrollView { VStack(alignment: .leading, spacing: N) { ... } }`
  with `.padding(.horizontal, 20)` on the VStack and `.background(<something>.ignoresSafeArea())`
  on the ScrollView. Every top-level screen follows this exact shape.

---

## 6. Design Principles (plain English)

- **Warm neutral, never pure black/white.** Backgrounds and text both sit slightly off from true
  monochrome (`#1C1C1A`/`#F5F5F3` backgrounds, `#F1EFE8` cream text in dark mode) — a deliberate
  softness, not a rounding error.
- **Flat by default, with one deliberate exception.** Almost the entire app is solid-fill,
  single-shadow-value flat design — no gradients as a general pattern. `CurvedBackground` (an
  accent-tinted two-zone background with a curved seam) is the one intentional decorative
  flourish, and it's scoped to exactly three screens (Today, Week, Progress) that have a
  header/hero region to anchor it to — not applied app-wide, deliberately excluded from
  utility-feeling screens like Settings.
- **Color carries meaning, not just brand.** The palette is organized around semantic roles
  (success/warning/scheduled/in-progress) that stay fixed regardless of the user's chosen accent
  color. The accent is layered on top for personalization (buttons, highlights, the curved
  background), but a task's done/overdue/future state is never accent-dependent — status must
  read the same regardless of theme.
- **Generously rounded, never sharp.** Every surface — buttons, cards, sheets, pills — uses a
  continuous rounded corner; there is no square/sharp-corner component anywhere in the design
  system.
- **Low, single-level elevation.** One shadow value for the whole app. Depth comes from color
  contrast (tints, the curved background's two zones) more than from shadow/blur.
  Dynamic Type–aware from the start: every typography role scales via `UIFontMetrics` against a
  matched system text style rather than a fixed pixel size.
- **Motion is earned, not ambient.** Animations exist where they communicate something real
  (elapsed time via the progress wave, a genuine one-time celebration on completion) rather than
  as decoration on every interaction. Most controls just have a simple press-opacity/scale, not
  a signature animation.
- **Custom chrome, native controls where the content is truly a form.** Screens with real visual
  identity (Today, task detail, cards) get fully custom-drawn components. Genuinely
  form-like utility screens (Settings' rows) lean on native `Picker`/`Toggle` — native controls
  aren't avoided on principle, they're used where the screen is functionally a settings list.
- **Light and dark are both first-class**, via paired `dynamic(light:dark:)` definitions on
  almost every token — this isn't a dark-mode-first app with light mode bolted on, both are
  defined together at each token's declaration site.
