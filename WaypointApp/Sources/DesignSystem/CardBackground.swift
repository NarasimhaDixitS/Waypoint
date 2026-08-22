import SwiftUI

struct CardBackground: ViewModifier {
    var padding: CGFloat = 14
    var fill: Color = ColorTokens.surface1
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: ColorTokens.cardShadow, radius: 6, x: 0, y: 2)
    }
}

extension View {
    func wpCard(padding: CGFloat = 14, fill: Color = ColorTokens.surface1, cornerRadius: CGFloat = 18) -> some View {
        modifier(CardBackground(padding: padding, fill: fill, cornerRadius: cornerRadius))
    }
}
