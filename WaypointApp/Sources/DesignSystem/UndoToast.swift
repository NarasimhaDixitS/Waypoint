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

    var body: some View {
        HStack(spacing: 14) {
            Text("\(title) deleted")
                .wpTypography(.body)
                .foregroundStyle(ColorTokens.onInkPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("Undo", action: onUndo)
                .wpTypography(.body)
                .fontWeight(.semibold)
                .foregroundStyle(theme.accentSwatch.onInkColor)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(ColorTokens.inkSlab)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }
}
