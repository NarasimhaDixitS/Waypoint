import SwiftUI

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    var color: Color = ColorTokens.success
    var trackColor: Color = ColorTokens.border
    var showsLabel: Bool = true
    var labelFont: Font = WPTypography.cardTitle.font
    var labelColor: Color = ColorTokens.textPrimary

    @State private var animatedProgress: Double = 0
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .scaleEffect(pulse ? 1.05 : 1.0)
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
