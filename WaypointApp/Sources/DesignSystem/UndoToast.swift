import SwiftUI

/// The black slab that appears after a delete, with four seconds to take it back.
///
/// Shared rather than written twice. Today and the goal lists both delete tasks and both grew
/// their own copy of this, which is how one of them can quietly acquire a fix the other never
/// gets — and the colour bug this fixes was in both.
///
/// **The slab is dark in every appearance**, so everything on it takes a colour that reads on
/// dark rather than one that follows the page. See `AccentSwatch.onInkColor`.
struct UndoToast: View {
    @EnvironmentObject private var theme: ThemeManager

    let title: String
    var onUndo: () -> Void

    /// Latched on first appearance, purely so the delete haptic has an edge to fire on.
    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: 14) {
            Text("\(title) deleted")
                .wpTypography(.body)
                .foregroundStyle(ColorTokens.onInkPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            // Four letters, four seconds, and no second chance — so the target is the padded
            // block, not the word. `Button("Undo")` is hit-tested against the glyphs, which
            // is about 44pt wide and 17 tall on a slab with room for far more; the negative
            // padding pulls the slab's own layout back so a bigger target doesn't make a
            // taller toast.
            Button(action: onUndo) {
                Text("Undo")
                    .wpTypography(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.accentSwatch.onInkColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.wpRow)
            .padding(.horizontal, -12)
            .padding(.vertical, -10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(ColorTokens.inkSlab)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
        // A delete is the one destructive thing the app does, and this slab is where both
        // paths — Today and the goal lists — end up, so the confirmation belongs here rather
        // than at each call site. Medium, not light: heavier than a press because something
        // left the screen, short of `.warning` because it is entirely undoable for four
        // seconds and the way back is right there.
        .onAppear { hasAppeared = true }
        .sensoryFeedback(.impact(weight: .medium), trigger: hasAppeared) { _, new in new }
    }
}
