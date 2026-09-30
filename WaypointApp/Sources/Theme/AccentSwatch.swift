import SwiftUI

enum AccentSwatch: String, CaseIterable, Identifiable, Hashable {
    case graphite, teal, blue, ultramarine, purple, pink, red, orange

    var id: String { rawValue }

    /// Shared with the widget, which runs in its own process and cannot see the app's own
    /// `UserDefaults`. Mirrored by `ThemeManager` on every change so a widget drawn minutes
    /// later still matches the app it belongs to — an accent that drifts a shade away is the
    /// thing that makes both look unfinished.
    static let sharedDefaults = UserDefaults(suiteName: PersistenceController.appGroupID)

    static let storageKey = "themeAccentSwatch"

    static var current: AccentSwatch {
        let raw = sharedDefaults?.string(forKey: storageKey)
            ?? UserDefaults.standard.string(forKey: storageKey)
        return AccentSwatch(rawValue: raw ?? "") ?? .teal
    }

    /// Teal is a **darkened** form of the requested #17B2C6, not that value itself. Every
    /// accent in this app is a fill with white text and white glyphs on it — the banner, the
    /// "+" button, the "Jump to Today" pill — and #17B2C6 measures **2.55:1** under white,
    /// which is not a near miss but roughly half the worst existing swatch. Same hue (187°) and
    /// the same saturation, walked down to 28% lightness, which lands at 5.55:1: stronger than
    /// blue, orange and pink, and close to the green it replaces. The requested value survives
    /// intact where it is genuinely excellent — see `darkMarkHex`.
    /// Fill and dark-mode mark for every accent, in one table.
    ///
    /// A table rather than two switch statements because these are *tuning* values: the pair
    /// has to be read together, and changing one without the other is how an accent ends up
    /// legible in light mode and invisible in dark. Editing a colour is one line here.
    ///
    /// `white` is white text on the fill; `mark` is the dark-mode value measured against the
    /// dark card (`surface1`, `0x242422`). Normal text wants 4.5:1.
    ///
    /// The original four are **untouched** and three of them miss 4.5 under white — blue 3.59,
    /// orange 3.87, pink 3.93. That's a deliberate hold, not an oversight: deepening them
    /// changes the look of every screen at once, so it stays a separate decision. Everything
    /// added since clears the bar on both axes, so the problem at least stops growing.
    private var palette: (fill: UInt32, mark: UInt32) {
        switch self {
        //                          fill        white   mark        on dark card
        case .graphite:    (0x6D7583,          /* 4.64 */ 0x878F9B) /* 4.76 */
        case .teal:        (0x0F7380,          /* 5.55 */ 0x17B2C6) /* 6.09 */
        case .blue:        (0x378ADD,          /* 3.59 */ 0x3D8EDE) /* 4.53 */
        case .ultramarine: (0x5268E5,          /* 4.70 */ 0x7587EA) /* 4.75 */
        case .purple:      (0x9B55C3,          /* 4.69 */ 0xAF77CF) /* 4.71 */
        case .pink:        (0xD4537E,          /* 3.93 */ 0xD8648B) /* 4.53 */
        case .red:         (0xD53B30,          /* 4.67 */ 0xDF6B62) /* 4.75 */
        case .orange:      (0xD85A30,          /* 3.87 */ 0xDC6943) /* 4.55 */
        }
    }

    private var hexValue: UInt32 { palette.fill }

    var color: Color { Color(ColorTokens.hex(hexValue)) }

    var label: String {
        switch self {
        case .graphite: "Graphite"
        case .teal: "Teal"
        case .blue: "Blue"
        case .ultramarine: "Ultramarine"
        case .purple: "Purple"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        }
    }

    /// The accent drawn as a *mark* — a ring, a progress bar, a dot, a card edge — rather than
    /// as a fill with white text on it. Identical to `color` in light mode.
    ///
    /// The four swatches were picked to sit *under* white text on a solid accent background,
    /// which wants them dark. That's the opposite of what a mark on a dark card needs: the
    /// swatch this replaced measured 6.21:1 against white text and only **2.50:1** against the
    /// dark card surface, so a progress bar or ring in dark mode was very nearly invisible
    /// against its own track. Each is lightened here just far enough to clear 4.5:1 on that
    /// surface.
    var markColor: Color {
        ColorTokens.dynamic(light: ColorTokens.hex(hexValue), dark: ColorTokens.hex(darkMarkHex))
    }

    private var darkMarkHex: UInt32 { palette.mark }

    // MARK: - "In progress" — neutral ink, not accent-tied

    /// The "task is happening right now" indicator went through two color schemes before this
    /// one: first a single fixed blue (which, for the Blue accent specifically, was the *exact
    /// same hex* as the accent itself), then a per-accent complementary hue (which fixed that
    /// collision but added yet another hue competing for attention against the accent-colored
    /// nav bar/FAB/banner). Landing on a neutral ink tone instead sidesteps the whole class of
    /// clash: reusing `ColorTokens.textPrimary` — dark charcoal in light mode, warm off-white in
    /// dark mode — can never collide with any accent, in either mode, because it isn't a hue at
    /// all. Deliberately ignores `self` (the accent case) for that reason; kept as a member of
    /// `AccentSwatch` rather than moved to `ColorTokens` only so every existing call site
    /// (`theme.accentSwatch.inProgressColor`, etc.) keeps working unchanged.
    var inProgressColor: Color { ColorTokens.textPrimary }

    var inProgressTextColor: Color { ColorTokens.textPrimary }

    /// Same low-opacity-wash technique as every other `*Tint` token in `ColorTokens`, just with
    /// `textPrimary` as the base instead of a semantic hue — a subtle "this one's elevated"
    /// wash rather than a colored highlight.
    var inProgressTintColor: Color {
        ColorTokens.dynamic(
            light: ColorTokens.mix(ColorTokens.hex(0x2C2C2A), over: ColorTokens.hex(0xFFFFFF), amount: 0.10),
            dark: ColorTokens.mix(ColorTokens.hex(0xF1EFE8), over: ColorTokens.hex(0x242422), amount: 0.10)
        )
    }
}
