import SwiftUI

enum AccentSwatch: String, CaseIterable, Identifiable, Hashable {
    case green, blue, orange, pink

    var id: String { rawValue }

    private var hexValue: UInt32 {
        switch self {
        case .green: 0x3B6D11
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
    /// which wants them dark. That's the opposite of what a mark on a dark card needs: Green
    /// measures 6.21:1 against white text and only **2.50:1** against the dark card surface, so
    /// a green progress bar or ring in dark mode was very nearly invisible against its own
    /// track. Each is lightened here just far enough to clear 4.5:1 on that surface — Green
    /// needs 28% white, the others 3–9%, which is why this reads as a Green-specific problem
    /// but is fixed uniformly.
    var markColor: Color {
        ColorTokens.dynamic(light: ColorTokens.hex(hexValue), dark: ColorTokens.hex(darkMarkHex))
    }

    private var darkMarkHex: UInt32 {
        switch self {
        case .green: 0x729654
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
