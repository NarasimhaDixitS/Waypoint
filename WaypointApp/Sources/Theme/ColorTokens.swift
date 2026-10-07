import SwiftUI
import UIKit

enum ColorTokens {
    /// Shared with `CardBackground.ShadowTier` — kept here (not nested in that view modifier)
    /// so `elevatedFill` below can be a pure color-token function, not tied to a specific view.
    enum ShadowTier {
        case resting, raised, floating

        /// Geometry lives on the tier, not at the call site. It used to be hand-copied wherever
        /// a shadow was drawn, and had already drifted — `raised` existed as 22/18, 18/8 and
        /// 14/8 in three different files, so the tiers could never be tuned as a set.
        ///
        /// **Every radius is capped below the 20pt page margin.** Scroll content is inset by 20
        /// and a `ScrollView` clips to its bounds, so a blur wider than the margin is sliced off
        /// down both sides — the shadow doesn't read as bigger, it reads as cut, with a hard
        /// vertical edge where it meets the screen. `floating` is the one exception: it is only
        /// ever used by overlays that sit outside padded scroll content.
        var radius: CGFloat {
            switch self {
            case .resting: 12
            case .raised: 16
            case .floating: 26
            }
        }

        var y: CGFloat {
            switch self {
            case .resting: 6
            case .raised: 9
            case .floating: 18
            }
        }

        var color: Color {
            switch self {
            case .resting: ColorTokens.shadowResting
            case .raised: ColorTokens.shadowRaised
            case .floating: ColorTokens.shadowFloating
            }
        }
    }

    // MARK: - Palette

    /// Every token carries both palettes, on one line, so the pair can be read together.
    ///
    /// Computed rather than stored: `Palette.current` changes while the app is running, and a
    /// `static let` would freeze whichever palette happened to be active at first access. The
    /// cost is a switch per read, which is nothing next to drawing the view that asked.
    ///
    /// Ratios below are measured, not estimated — paper card is `0xF6F1E6`, paper page is
    /// `0xEDE6D8`, paper night card is `0x201C16`.
    private static func token(
        standard: (light: UInt32, dark: UInt32),
        paper: (light: UInt32, dark: UInt32)
    ) -> Color {
        let pair = Palette.current == .paper ? paper : standard
        return dynamic(light: hex(pair.light), dark: hex(pair.dark))
    }

    /// A floating dark slab — the undo toast. Opaque and palette-aware rather than
    /// `Color.black.opacity(0.85)`, which composited differently over every page it floated
    /// above and gave paper a cold black it has nowhere else.
    static var inkSlab: Color { token(standard: (0x242423, 0x121211), paper: (0x332F29, 0x332F29)) }
    /// Body text on `inkSlab`. Not `textPrimary`, which is near-*white* in dark mode only.
    static var onInkPrimary: Color { token(standard: (0xFFFFFF, 0xF1EFE8), paper: (0xF9F7F2, 0xF9F7F2)) }

    /// Paper grounds are warm and never pure: no `0xFFFFFF` to glare, no `0x000000` to halo.
    ///
    /// **These two are one surface at two depths. They are not a separator.** `#F5F5F3` against
    /// `#FFFFFF` is a 4% difference, and paper's pair is closer still. Put one directly on the
    /// other and the result reads as a layering mistake rather than an edge — three separate
    /// bugs have come from assuming otherwise:
    ///
    /// - the clash sheet's buttons filled `surface1` on a `surface1` sheet and vanished; the
    ///   fix that worked was restoring the **border**, not swapping the fill to `surface0`,
    ///   which changed nothing anybody could see;
    /// - both editor sheets drew a `surface1` card inset on a `surface0` sheet, which testers
    ///   described, accurately, as a white page pasted onto a grey one.
    ///
    /// When something needs to read as a separate object, spend `border` or a shadow on it —
    /// or let it share the surface and separate with space. Depth is for recession (an input
    /// well inside a raised page) and for stacking order, never for telling two things apart.
    static var surface0: Color { token(standard: (0xF5F5F3, 0x1C1C1A), paper: (0xEFEDE6, 0xEFEDE6)) }
    static var surface1: Color { token(standard: (0xFFFFFF, 0x242422), paper: (0xF9F7F2, 0xF9F7F2)) }
    /// Paper: 10.97:1 on card, 9.95:1 on page — against standard light's 13.99:1. Softer by
    /// about a quarter, and still miles clear of 4.5:1.
    static var textPrimary: Color { token(standard: (0x2C2C2A, 0xF1EFE8), paper: (0x1A1A17, 0x1A1A17)) }
    /// Paper: 6.46:1 on card, 7.43:1 on night card.
    static var textSecondary: Color { token(standard: (0x53524E, 0xB4B2A9), paper: (0x46453F, 0x46453F)) }
    /// Was a single flat `0x888780` shared by both schemes, which measured **3.61:1** on a white
    /// card and **4.31:1** on a dark one — under the 4.5:1 normal text needs, in both. It carries
    /// start times, day summaries and secondary counts, so a good deal of the app's small text
    /// was failing. Now scheme-aware and pulled to 5.11:1 light / 5.43:1 dark, which also puts
    /// real daylight between it and `textSecondary` instead of the two nearly touching.
    ///
    /// Paper: 5.20:1 on card and 4.72:1 on the page — the tightest value in the whole paper set,
    /// and the one that decided how far the ground could be warmed. It was the floor in standard
    /// mode too, for the same reason: it carries the small text, so it sets the limit.
    static var textMuted: Color { token(standard: (0x6F6E69, 0x9A998F), paper: (0x6B6A62, 0x6B6A62)) }

    /// Ink for a surface that is white in **both** schemes — a selected pill on an accent
    /// banner, a filled chip. `textPrimary` cannot be used there: it inverts with the scheme, so
    /// in dark mode it resolves to the warm off-white `0xF1EFE8` and vanishes against the white
    /// underneath it. Fixed dark charcoal, 13.99:1 on white, and deliberately scheme-blind
    /// because the thing it sits on is too.
    static let inkOnLight = Color(hex(0x2C2C2A))
    static var border: Color { token(standard: (0xE5E3DB, 0x3A3A37), paper: (0xCCC9BE, 0xCCC9BE)) }

    /// Green is a *moment*, not a label. It was once the full dress for every completed task
    /// — tinted row, green ink, solid green disc — which put the loudest treatment in the app
    /// on its most common row and left a normal Tuesday showing green, red, purple and the
    /// user's accent in one column. Completed tasks now recede instead (see `TaskRowView`),
    /// and green survives only where it marks an event or a fact rather than a state: the
    /// day-complete celebration, and static "included"/"on" markers. Its companion `textSuccess`
    /// and `successTint` shades were retired with the tinted done-row they existed for.
    static var success: Color { token(standard: (0x5B8A63, 0x5B8A63), paper: (0x1A1A17, 0x1A1A17)) }

    /// "In progress" role token — fixed semantic color, independent of the user's accent swatch.
    static var inProgress: Color { token(standard: (0x378ADD, 0x85B7EB), paper: (0x1A1A17, 0x1A1A17)) }
    /// Paper: 5.99:1 on card, 7.66:1 on night card.
    static var textInProgress: Color { token(standard: (0x185FA5, 0xB5D4F4), paper: (0x1A1A17, 0x1A1A17)) }
    static var inProgressTint: Color {
        Palette.current == .paper
            ? Color(mix(hex(0x1A1A17), over: hex(0xF9F7F2), amount: 0.08))
            : dynamic(
                light: mix(hex(0x378ADD), over: hex(0xFFFFFF), amount: 0.24),
                dark: mix(hex(0x85B7EB), over: hex(0x242422), amount: 0.24)
            )
    }

    /// "Needs attention" role token — schedule conflicts, warnings. Deliberately shifted
    /// red-ward (was #D85A30) so it's no longer the exact same hex as the Orange accent swatch
    /// — once the accent shows up on the tab bar and search icon too, an Orange-accented user
    /// would otherwise see their own UI chrome and an overdue task badge in literally identical
    /// color, purely by coincidence.
    ///
    /// Paper has no red. A warning there is carried by *tone* instead.
    ///
    /// This was the ink itself at first, which flattened eight different "this one is the odd
    /// one out" distinctions across the charts into nothing — the weakest weekday, the longest
    /// slips, the overrunning estimates all became the same black as everything beside them.
    /// Monochrome means one hue, not one value; a second tone is still monochrome and is how a
    /// printed chart has always picked a bar out.
    ///
    /// 6.95:1 on the paper card, so it works as a graphic *and* as text.
    static var warning: Color { token(standard: (0xD83E30, 0xD83E30), paper: (0x5A5952, 0x5A5952)) }
    /// Full ink in paper, unlike `warning` above — this one is *text*, and an overdue task
    /// reading fainter than an ordinary one would say the opposite of what it means. Weight
    /// carries it: the strongest value on the page, where the row around it is muted.
    static var textWarning: Color { token(standard: (0xB02A1E, 0xF09383), paper: (0x1A1A17, 0x1A1A17)) }
    static var warningTint: Color {
        Palette.current == .paper
            ? Color(mix(hex(0x1A1A17), over: hex(0xF9F7F2), amount: 0.10))
            : dynamic(
                light: mix(hex(0xD83E30), over: hex(0xFFFFFF), amount: 0.24),
                dark: mix(hex(0xD83E30), over: hex(0x242422), amount: 0.24)
            )
    }

    /// "Medium priority" role token — same reasoning as `warning` above: was a duplicate of the
    /// Pink accent swatch's exact hex (#D4537E), shifted toward magenta so it's a distinct rose
    /// rather than an accidental match to an accent option.
    static var priorityMedium: Color { token(standard: (0xD4539E, 0xD4539E), paper: (0x6B6A62, 0x6B6A62)) }

    // The "scheduled for later" purple was retired along with the green done-row: an upcoming
    // task is depicted by receding (muted ink, dashed marker) rather than by a third hue
    // competing with the accent. See the note on `TaskRowView.isInProgress`.

    /// Elevation scale — was a single flat shadow value app-wide; now three tiers so ordinary
    /// content, "floating" interactive chrome (FAB, banners, the tab bar), and true overlays
    /// (sheets/modals) read as visibly different depths, not just decoration. Light mode uses a
    /// soft, low-alpha, cool-gray tint (not flat black) with a large blur and generous Y
    /// offset — a soft ambient shadow rather than a hard-edged one, so elevation reads gently
    /// rather than as an outline. Dark mode keeps a much higher-opacity near-black instead — a
    /// low-alpha tinted shadow is nearly invisible against an already-dark background no matter
    /// how it's tuned; shadow alone can't carry "elevated" on a dark surface. Pair each with
    /// `CardBackground.ShadowTier`'s radius/y, not just the color alone, and see `elevatedFill`
    /// below for the other half of the fix (surfaces get lighter, not just shadowed, as they
    /// rise in dark mode).
    private static let shadowTint = hex(0x5C6369)

    /// Paper has no shadows at all — all eighteen call sites in the app resolve through these
    /// three tokens, so clearing them here is the whole of it. Paper is matte, and a drop shadow
    /// is the single loudest "this is a lit screen" cue in the interface. Cards still read as
    /// separate because they keep their own fill against a slightly darker ground.
    private static func shadow(_ standard: Color) -> Color {
        Palette.current == .paper ? .clear : standard
    }

    static var shadowResting: Color {
        shadow(dynamic(light: shadowTint.withAlphaComponent(0.10), dark: hex(0x000000, alpha: 0.55)))
    }
    static var shadowRaised: Color {
        shadow(dynamic(light: shadowTint.withAlphaComponent(0.13), dark: hex(0x000000, alpha: 0.65)))
    }
    static var shadowFloating: Color {
        shadow(dynamic(light: shadowTint.withAlphaComponent(0.16), dark: hex(0x000000, alpha: 0.75)))
    }

    /// Kept for any call site still referencing the old single-tier name directly.
    static var cardShadow: Color { shadowResting }

    /// The other half of making elevation actually read in dark mode: blend a touch of white
    /// into a fill color as it rises, the same "surfaces get lighter at higher elevation"
    /// convention dark-themed UIs generally use, since a shadow's color contrast against an
    /// already-near-black background is inherently too low to carry depth by itself. No-op
    /// (returns `base` unchanged) in light mode, where shadow-only elevation already reads
    /// fine against a light background.
    static func elevatedFill(_ base: Color, tier: ShadowTier, isDark: Bool) -> Color {
        guard isDark else { return base }
        let amount: CGFloat = switch tier {
        case .resting: 0
        case .raised: 0.05
        case .floating: 0.1
        }
        guard amount > 0 else { return base }
        return Color(mix(hex(0xFFFFFF), over: UIColor(base), amount: amount))
    }

    /// Room a scrolling screen has to leave below its content for the floating tab bar.
    ///
    /// The bar is 68pt plus a 14pt badge lift plus its own margins, and it sits over the
    /// content rather than beside it. Screens were each guessing: Settings used 24 and its last
    /// row ended up unreachable under the bar, while Week and Progress used 140. One value, so
    /// the next screen added can't guess wrong.
    static let tabBarClearance: CGFloat = 116

    // MARK: - Helpers

    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func mix(_ foreground: UIColor, over background: UIColor, amount: CGFloat) -> UIColor {
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        foreground.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        background.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(
            red: fr * amount + br * (1 - amount),
            green: fg * amount + bg * (1 - amount),
            blue: fb * amount + bb * (1 - amount),
            alpha: 1
        )
    }

    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { trait in trait.userInterfaceStyle == .dark ? dark : light })
    }
}
