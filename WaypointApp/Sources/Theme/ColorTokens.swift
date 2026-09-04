import SwiftUI
import UIKit

enum ColorTokens {
    /// Shared with `CardBackground.ShadowTier` — kept here (not nested in that view modifier)
    /// so `elevatedFill` below can be a pure color-token function, not tied to a specific view.
    enum ShadowTier {
        case resting, raised, floating
    }

    // MARK: - Palette

    static let surface0 = dynamic(light: hex(0xF5F5F3), dark: hex(0x1C1C1A))
    static let surface1 = dynamic(light: hex(0xFFFFFF), dark: hex(0x242422))
    static let textPrimary = dynamic(light: hex(0x2C2C2A), dark: hex(0xF1EFE8))
    static let textSecondary = dynamic(light: hex(0x5F5E5A), dark: hex(0xB4B2A9))
    static let textMuted = Color(hex(0x888780))
    static let border = dynamic(light: hex(0xE5E3DB), dark: hex(0x3A3A37))

    /// Green is a *moment*, not a label. It was once the full dress for every completed task
    /// — tinted row, green ink, solid green disc — which put the loudest treatment in the app
    /// on its most common row and left a normal Tuesday showing green, red, purple and the
    /// user's accent in one column. Completed tasks now recede instead (see `TaskRowView`),
    /// and green survives only where it marks an event or a fact rather than a state: the
    /// day-complete celebration, and static "included"/"on" markers. Its companion `textSuccess`
    /// and `successTint` shades were retired with the tinted done-row they existed for.
    static let success = Color(hex(0x5B8A63))

    /// "In progress" role token — fixed semantic color, independent of the user's accent swatch.
    static let inProgress = dynamic(light: hex(0x378ADD), dark: hex(0x85B7EB))
    static let textInProgress = dynamic(light: hex(0x185FA5), dark: hex(0xB5D4F4))
    static let inProgressTint = dynamic(
        light: mix(hex(0x378ADD), over: hex(0xFFFFFF), amount: 0.24),
        dark: mix(hex(0x85B7EB), over: hex(0x242422), amount: 0.24)
    )

    /// "Needs attention" role token — schedule conflicts, warnings. Deliberately shifted
    /// red-ward (was #D85A30) so it's no longer the exact same hex as the Orange accent swatch
    /// — once the accent shows up on the tab bar and search icon too, an Orange-accented user
    /// would otherwise see their own UI chrome and an overdue task badge in literally identical
    /// color, purely by coincidence.
    static let warning = Color(hex(0xD83E30))
    static let textWarning = dynamic(light: hex(0xB02A1E), dark: hex(0xF09383))
    static let warningTint = dynamic(
        light: mix(hex(0xD83E30), over: hex(0xFFFFFF), amount: 0.24),
        dark: mix(hex(0xD83E30), over: hex(0x242422), amount: 0.24)
    )

    /// "Medium priority" role token — same reasoning as `warning` above: was a duplicate of the
    /// Pink accent swatch's exact hex (#D4537E), shifted toward magenta so it's a distinct rose
    /// rather than an accidental match to an accent option.
    static let priorityMedium = Color(hex(0xD4539E))

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
    static let shadowResting = dynamic(light: shadowTint.withAlphaComponent(0.10), dark: hex(0x000000, alpha: 0.55))
    static let shadowRaised = dynamic(light: shadowTint.withAlphaComponent(0.13), dark: hex(0x000000, alpha: 0.65))
    static let shadowFloating = dynamic(light: shadowTint.withAlphaComponent(0.16), dark: hex(0x000000, alpha: 0.75))

    /// Kept for any call site still referencing the old single-tier name directly.
    static let cardShadow = shadowResting

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
