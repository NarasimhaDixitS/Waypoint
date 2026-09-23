import SwiftUI

enum AccentSwatch: String, CaseIterable, Identifiable, Hashable {
    case teal, blue, orange, pink

    var id: String { rawValue }

    /// Teal is a **darkened** form of the requested #17B2C6, not that value itself. Every
    /// accent in this app is a fill with white text and white glyphs on it — the banner, the
    /// "+" button, the "Jump to Today" pill — and #17B2C6 measures **2.55:1** under white,
    /// which is not a near miss but roughly half the worst existing swatch. Same hue (187°) and
    /// the same saturation, walked down to 28% lightness, which lands at 5.55:1: stronger than
    /// blue, orange and pink, and close to the green it replaces. The requested value survives
    /// intact where it is genuinely excellent — see `darkMarkHex`.
    private var hexValue: UInt32 {
        switch self {
        case .teal: 0x0F7380
        case .blue: 0x378ADD
        case .orange: 0xD85A30
        case .pink: 0xD4537E
        }
    }

    var color: Color { Color(ColorTokens.hex(hexValue)) }

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

    private var darkMarkHex: UInt32 {
        switch self {
        // #17B2C6 exactly as asked: 6.09:1 against the dark card, the best mark of the four.
        case .teal: 0x17B2C6
        case .blue: 0x3D8EDE
        case .orange: 0xDC6943
        case .pink: 0xD8648B
        }
    }

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
