import SwiftUI

/// The shared frame every analysis sits in: a title, a one-line reading of what the chart says,
/// and the chart itself.
///
/// The caption is not decoration. A chart shows a shape; it does not say what the shape means,
/// and a reader who has to work that out for themselves usually works out something wrong. Each
/// card states its own conclusion in words and lets the chart be the evidence.
struct AnalyticsCard<Content: View>: View {
    let title: String
    let caption: String
    /// Only for a card with a genuine catch — how the number is arrived at, where that would
    /// change how it's read. Most cards have none, and that's the point: a footnote on every
    /// card is a page nobody finishes.
    var footnote: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .wpTypography(.cardTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                Text(caption)
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
            if let footnote {
                Text(footnote)
                    .wpTypography(.micro)
                    .foregroundStyle(ColorTokens.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wpCard(padding: 18)
    }
}

/// Names what a mark on a chart means. A chart carrying two lines and no key is not a hard
/// chart to read — it is an unreadable one, because nothing on screen says which line is which.
struct ChartLegend: View {
    enum Mark { case line(Color), dashed(Color), swatch(Color), fade(Color) }

    let items: [(String, Mark)]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(items, id: \.0) { label, mark in
                HStack(spacing: 6) {
                    glyph(mark)
                    Text(label)
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func glyph(_ mark: Mark) -> some View {
        switch mark {
        case .line(let color):
            Capsule().fill(color).frame(width: 16, height: 3)
        case .dashed(let color):
            // Drawn as a real dashed stroke rather than a solid stub, so the key looks like the
            // thing it is keying.
            Path { $0.addLines([CGPoint(x: 0, y: 1.5), CGPoint(x: 16, y: 1.5)]) }
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 2.5]))
                .frame(width: 16, height: 3)
        case .swatch(let color):
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 11, height: 11)
        case .fade(let color):
            LinearGradient(colors: [color.opacity(0.18), color], startPoint: .leading, endPoint: .trailing)
                .frame(width: 26, height: 11)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

/// Shown in place of a chart that has nothing to draw yet. A chart with no data still renders
/// axes and an empty plot, which reads as "you have done nothing" rather than "there isn't
/// enough here yet" — two very different messages to put in front of someone.
struct AnalyticsEmpty: View {
    let message: String

    var body: some View {
        Text(message)
            .wpTypography(.body)
            .foregroundStyle(ColorTokens.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
    }
}

/// A labelled proportion bar — used where a pie would be read as "share of a whole" when the
/// number actually being shown is a *rate*. Three priorities completing at 90/70/50% do not sum
/// to anything, and drawing them as a pie would invent a relationship that isn't there.
struct RatioBar: View {
    let label: String
    let done: Int
    let total: Int
    let fraction: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textPrimary)
                Spacer(minLength: 8)
                Text(total == 0 ? "—" : "\(Int(fraction * 100))%")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
                    .monospacedDigit()
                Text(total == 0 ? "" : "(\(done)/\(total))")
                    .wpTypography(.micro)
                    .foregroundStyle(ColorTokens.textMuted)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ColorTokens.border)
                    if fraction > 0 {
                        Capsule()
                            .fill(tint)
                            .frame(width: max(geo.size.width * fraction, 6))
                    }
                }
            }
            .frame(height: 6)
        }
    }
}
