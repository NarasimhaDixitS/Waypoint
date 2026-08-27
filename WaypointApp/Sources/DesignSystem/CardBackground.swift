import SwiftUI

struct CardBackground: ViewModifier {
    /// Three elevation tiers instead of one flat shadow — see `ColorTokens.shadowResting`
    /// /`shadowRaised`/`shadowFloating` for the reasoning. `resting` is the old app-wide
    /// default; `raised` is for interactive "lifted" chrome (banners, the FAB, the tab bar);
    /// `floating` is for true overlays (sheets, modals).
    enum ShadowTier {
        case resting, raised, floating

        var color: Color {
            switch self {
            case .resting: ColorTokens.shadowResting
            case .raised: ColorTokens.shadowRaised
            case .floating: ColorTokens.shadowFloating
            }
        }

        var radius: CGFloat {
            switch self {
            case .resting: 8
            case .raised: 14
            case .floating: 24
            }
        }

        var y: CGFloat {
            switch self {
            case .resting: 3
            case .raised: 6
            case .floating: 12
            }
        }
    }

    var padding: CGFloat = 14
    var fill: Color = ColorTokens.surface1
    var cornerRadius: CGFloat = 18
    var shadow: ShadowTier = .resting

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
    }
}

extension View {
    func wpCard(
        padding: CGFloat = 14,
        fill: Color = ColorTokens.surface1,
        cornerRadius: CGFloat = 18,
        shadow: CardBackground.ShadowTier = .resting
    ) -> some View {
        modifier(CardBackground(padding: padding, fill: fill, cornerRadius: cornerRadius, shadow: shadow))
    }
}
