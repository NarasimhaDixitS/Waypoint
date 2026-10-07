import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = ColorTokens.textPrimary
    var foreground: Color = ColorTokens.surface0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tint)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { old, new in new }
    }
}

/// For a button shaped like a card or a list row — a picker option, a delete choice.
///
/// These were all `.buttonStyle(.plain)`, which gives a row no press state worth feeling: a
/// faint label fade on a card whose fill and border don't move. Tapping one of them didn't
/// read as a tap, which matters most on exactly these screens, where the next thing that
/// happens is a sheet closing and some number of tasks disappearing.
///
/// Scale is smaller than `PrimaryButtonStyle`'s because the target is bigger — the same 2%
/// on a full-width row is a much larger movement, and it reads as a wobble rather than a
/// press. Same light haptic, so every button in the app answers a finger the same way.
struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { old, new in new }
    }
}

extension ButtonStyle where Self == PressableRowStyle {
    static var wpRow: PressableRowStyle { PressableRowStyle() }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(ColorTokens.surface1)
            .foregroundStyle(ColorTokens.textPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ColorTokens.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { old, new in new }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var wpPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var wpSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
