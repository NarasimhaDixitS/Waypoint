import SwiftUI

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    /// Every call site passes this explicitly — progress is drawn in the user's accent, and
    /// a view struct can't reach `ThemeManager` from a default argument. Neutral ink is the
    /// fallback so nothing silently inherits a semantic hue.
    var color: Color = ColorTokens.textPrimary
    var trackColor: Color = ColorTokens.border
    var showsLabel: Bool = true
    var labelFont: Font = WPTypography.cardTitle.font
    var labelColor: Color = ColorTokens.textPrimary

    /// Where the day currently stands, 0–1, drawn as a mark on the track. The arc says how much
    /// is done; this says how much *should* be by now, and the gap between them is the only
    /// thing on the card that answers "am I behind". `nil` hides it — for a past day, where
    /// pace is meaningless, and anywhere the ring isn't measuring a day at all.
    var paceMark: Double? = nil
    var paceMarkColor: Color = ColorTokens.textPrimary

    @State private var animatedProgress: Double = 0
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().stroke(trackColor, lineWidth: lineWidth)

            // Soft glow behind the crisp arc — a blurred, wider, dimmer duplicate of the
            // same trim so the ring reads as lit from within rather than a flat stroke.
            // Scaled off `lineWidth` so it settles down on its own at the small sizes this
            // same component is used at (e.g. the Week tab's compact rings).
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth * 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .blur(radius: lineWidth * 0.85)
                .opacity(0.55)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .scaleEffect(pulse ? 1.05 : 1.0)

            if let paceMark {
                // A radial tick across the track's own width, not a dot sitting on it: a dot
                // reads as another piece of progress, where a line cutting the track reads as a
                // position — which is what this is.
                GeometryReader { geo in
                    let radius = (min(geo.size.width, geo.size.height) - lineWidth) / 2
                    Capsule()
                        .fill(paceMarkColor)
                        .frame(width: 2, height: lineWidth + 5)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(min(max(paceMark, 0), 1) * 360))
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }

            if showsLabel {
                Text("\(Int(round(progress * 100)))%")
                    .font(labelFont)
                    .foregroundStyle(labelColor)
            }
        }
        .onAppear { animate() }
        .onChange(of: progress) { animate() }
    }

    private func animate() {
        withAnimation(.spring(response: 0.9, dampingFraction: 0.75)) {
            animatedProgress = progress
        }
        guard progress >= 0.98 else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.4).delay(0.75)) {
            pulse = true
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.5).delay(1.1)) {
            pulse = false
        }
    }
}
