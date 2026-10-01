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
            // Outline instead of lift. Paper has no shadow and barely any fill difference
            // between a card and the page it sits on, so with neither, a card stops being a
            // card — the edge is the only thing left to say "separate object". It isn't a
            // substitute for the shadow either; the outline *is* the look.
            .overlay {
                if Palette.current.usesOutlines {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(ColorTokens.border, lineWidth: 1)
                }
            }
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
