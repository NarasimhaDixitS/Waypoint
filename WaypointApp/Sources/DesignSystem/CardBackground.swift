import SwiftUI

struct CardBackground: ViewModifier {
    typealias ShadowTier = ColorTokens.ShadowTier

    var padding: CGFloat = 14
    var fill: Color = ColorTokens.surface1
    var cornerRadius: CGFloat = 18
    var shadow: ShadowTier = .resting

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(ColorTokens.elevatedFill(fill, tier: shadow, isDark: colorScheme == .dark))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }

    private var shadowColor: Color {
        switch shadow {
        case .resting: ColorTokens.shadowResting
        case .raised: ColorTokens.shadowRaised
        case .floating: ColorTokens.shadowFloating
        }
    }

    private var shadowRadius: CGFloat {
        switch shadow {
        case .resting: 14
        case .raised: 22
        case .floating: 30
        }
    }

    private var shadowY: CGFloat {
        switch shadow {
        case .resting: 10
        case .raised: 18
        case .floating: 28
        }
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
