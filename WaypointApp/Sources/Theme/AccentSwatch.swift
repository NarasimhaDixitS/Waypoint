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

    /// Paper has no accent. It has ink.
    ///
    /// The first pass made this a sepia, which was the whole mistake: a saturated brown on a
    /// cream ground is a ninth accent, not a different mode. There is no hue in paper, so the
    /// accent resolves to the same near-black as the text — which turns every accent-filled
    /// surface (the Today card, the "+" button, the tab bar) into solid ink with white on it.
    /// That inversion is the look, and it's doing the job colour used to: this is the loud
    /// thing on the page.
    ///
    /// The accent picker still shows, and says that paper overrides it. Silently ignoring
    /// somebody's choice is the part that would be rude.
    ///
    /// Deliberately **not** the text ink.
    ///
    /// Set to the same near-black at first, which was too rich: a near-black *fill* the size of
    /// the Today card or the tab bar reads as a glossy slab rather than as print. Text wants all
    /// the contrast it can get; a large filled surface doesn't, and the eye reads the difference
    /// as finish. Lifting the fill a few steps into a warm charcoal is what makes it matte.
    ///
    /// 11.35:1 against the paper card, and white on it measures 13.30:1 — so it stays an
    /// emphatic block, it just stops being a hole in the page.
    static let paperFillHex: UInt32 = 0x332F29
    static let paperMarkHex: UInt32 = 0x332F29

    var color: Color {
        Palette.current == .paper
            ? ColorTokens.dynamic(light: ColorTokens.hex(Self.paperFillHex), dark: ColorTokens.hex(Self.paperMarkHex))
            : Color(ColorTokens.hex(hexValue))
    }

    /// What reads on top of `color`.
    ///
    /// Every site that drew on an accent fill was deciding this for itself — the tab bar by
    /// colour scheme, the Today card by hardcoding white — which worked only while every accent
    /// was a mid-tone. Paper's accent is near-black, so the tab bar's scheme-based answer came
    /// out black-on-black and the icons disappeared entirely.
    var onAccentColor: Color {
        // Paper's fill is the ink itself, so the only thing that can sit on it is the page.
        Palette.current == .paper ? Color(ColorTokens.hex(0xF9F7F2)) : ColorTokens.dynamic(light: ColorTokens.hex(0x1A1A17), dark: ColorTokens.hex(0xFFFFFF))
    }

    /// What reads on top of `onAccentColor` — the reverse pair.
    ///
    /// The tab bar's active badge is a reversed chip: the bar is filled with the accent, the
    /// badge is filled with what reads on the accent, and the glyph inside it has to read on
    /// *that*. Three layers, each the opposite of the one under it.
    ///
    /// This existed only as a literal before (`colorScheme == .dark ? .black : .white`), and
    /// when the tab bar was reworked for paper all three lines were replaced together — so the
    /// glyph became the accent itself, which is correct in paper by coincidence and wrong
    /// everywhere else. Teal on the near-black badge measured 3.59:1 where white had measured
    /// 17.44:1, making the *active* tab the least legible thing in the bar.
    var onAccentReversedColor: Color {
        // Paper's reverse of its off-white is the same charcoal the fill uses, which is why its
        // appearance doesn't move at all with this fix.
        Palette.current == .paper ? Color(ColorTokens.hex(Self.paperFillHex)) : ColorTokens.dynamic(light: ColorTokens.hex(0xFFFFFF), dark: ColorTokens.hex(0x1A1A17))
    }

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
        Palette.current == .paper
            ? ColorTokens.dynamic(light: ColorTokens.hex(Self.paperFillHex), dark: ColorTokens.hex(Self.paperMarkHex))
            : ColorTokens.dynamic(light: ColorTokens.hex(hexValue), dark: ColorTokens.hex(darkMarkHex))
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
    /// The ink and the ground here were written as literals, which quietly meant *standard
    /// palette* literals — so under paper this mixed warm ink over pure white and produced a
    /// cold grey band across the one row that is meant to be the warmest thing on screen. Any
    /// token read as a hex rather than through `ColorTokens` has the same bug waiting in it.
    var inProgressTintColor: Color {
        let grounds: (ink: (UInt32, UInt32), base: (UInt32, UInt32)) = Palette.current == .paper
            ? (ink: (0x1A1A17, 0x1A1A17), base: (0xF9F7F2, 0xF9F7F2))
            : (ink: (0x2C2C2A, 0xF1EFE8), base: (0xFFFFFF, 0x242422))
        // Lighter in paper. At the standard 10% an ink wash over an off-white page comes out a
        // solid grey slab across half the row — a printed page shows progress with a rule or a
        // fill you can still read through, not a block of toner.
        let amount: CGFloat = Palette.current == .paper ? 0.055 : 0.10
        return ColorTokens.dynamic(
            light: ColorTokens.mix(ColorTokens.hex(grounds.ink.0), over: ColorTokens.hex(grounds.base.0), amount: amount),
            dark: ColorTokens.mix(ColorTokens.hex(grounds.ink.1), over: ColorTokens.hex(grounds.base.1), amount: amount)
        )
    }
}
