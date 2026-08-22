import SwiftUI

struct WelcomeView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            WaypointLogoMark(size: 88)
                .padding(.bottom, 22)

            Text("Waypoint")
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(ColorTokens.textPrimary)

            Text("Plan your goals. Live your days.")
                .wpTypography(.body)
                .foregroundStyle(ColorTokens.textSecondary)
                .padding(.top, 4)

            Spacer()

            VStack(spacing: 10) {
                Button("Continue with Apple", action: onContinue)
                    .buttonStyle(.wpPrimary)

                Button("Continue with email", action: onContinue)
                    .buttonStyle(.wpSecondary)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorTokens.surface0.ignoresSafeArea())
    }
}

/// Bullseye target with a mirror-symmetric "W" monogram, per the design spec's logo description.
struct WaypointLogoMark: View {
    var size: CGFloat = 46

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(Color.white)
            .frame(width: size, height: size)
            .overlay(
                GeometryReader { proxy in
                    let s = proxy.size.width
                    ZStack {
                        Circle()
                            .stroke(Color(ColorTokens.hex(0x242422)), lineWidth: s * 0.038)
                            .frame(width: s * 0.58, height: s * 0.58)
                            .position(x: s * 0.42, y: s * 0.42)
                        Circle()
                            .stroke(Color(ColorTokens.hex(0x242422)), lineWidth: s * 0.038)
                            .frame(width: s * 0.36, height: s * 0.36)
                            .position(x: s * 0.42, y: s * 0.42)
                        Circle()
                            .fill(Color(ColorTokens.hex(0x639922)))
                            .frame(width: s * 0.15, height: s * 0.15)
                            .position(x: s * 0.42, y: s * 0.42)
                        WMonogramShape()
                            .stroke(Color(ColorTokens.hex(0x242422)), style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round, lineJoin: .round))
                            .frame(width: s * 0.55, height: s * 0.34)
                            .position(x: s * 0.72, y: s * 0.42)
                    }
                }
            )
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
    }
}

private struct WMonogramShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: w * 0.25, y: h))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.75, y: h))
        path.addLine(to: CGPoint(x: w, y: 0))
        return path
    }
}

#Preview {
    WelcomeView(onContinue: {})
}
