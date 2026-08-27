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

    // MARK: - "In progress" complement

    /// The "task is happening right now" indicator used to be a single fixed blue
    /// (`ColorTokens.inProgress`) regardless of accent — which, for the Blue accent
    /// specifically, was the *exact same hex* as the accent itself, so the in-progress task,
    /// the nav bar, the FAB, and the goal banner all read as one undifferentiated block of
    /// blue. Each accent now gets its own complementary hue instead, chosen to sit opposite it
    /// on the color wheel (reusing the same complementary pairings approved once before for a
    /// background-tint experiment) so it always reads as a distinct signal against that accent's
    /// own chrome, whichever accent is active.
    private var inProgressPrimaryHex: UInt32 {
        switch self {
        case .blue: 0xDD8A37 // amber, complements blue
        case .green: 0x9B59D0 // violet, complements green — more saturated than the tint
                              // below since a pastel value doesn't read clearly as an icon/line
        case .orange: 0x2AA8D4 // cyan, complements orange
        case .pink: 0x3FC79A // teal, complements pink
        }
    }

    /// Softer version of the same hue, for the tinted background wash — this is the exact
    /// complementary value approved for each accent previously.
    private var inProgressTintHex: UInt32 {
        switch self {
        case .blue: 0xDD8A37
        case .green: 0xC8A1E9
        case .orange: 0x30AED8
        case .pink: 0x53D4A9
        }
    }

    /// Primary in-progress color (icon, stroke, wave line) — lightened for dark mode the same
    /// way every other primary/dark pairing in `ColorTokens` is, since a color tuned to read
    /// against white washes out or under-contrasts against a near-black surface unchanged.
    var inProgressColor: Color {
        let base = ColorTokens.hex(inProgressPrimaryHex)
        return ColorTokens.dynamic(
            light: base,
            dark: ColorTokens.mix(ColorTokens.hex(0xFFFFFF), over: base, amount: 0.30)
        )
    }

    /// Text-weight variant — darkened in light mode for contrast against a light tint
    /// background, lightened further in dark mode for contrast against the dark surface.
    var inProgressTextColor: Color {
        let base = ColorTokens.hex(inProgressPrimaryHex)
        return ColorTokens.dynamic(
            light: ColorTokens.mix(ColorTokens.hex(0x000000), over: base, amount: 0.35),
            dark: ColorTokens.mix(ColorTokens.hex(0xFFFFFF), over: base, amount: 0.55)
        )
    }

    /// Soft background wash — same `mix over surface1` technique as every other `*Tint` token
    /// in `ColorTokens`, just parameterized by this accent's complementary hue instead of a
    /// single fixed one.
    var inProgressTintColor: Color {
        let base = ColorTokens.hex(inProgressTintHex)
        return ColorTokens.dynamic(
            light: ColorTokens.mix(base, over: ColorTokens.hex(0xFFFFFF), amount: 0.24),
            dark: ColorTokens.mix(base, over: ColorTokens.hex(0x242422), amount: 0.24)
        )
    }
}
