import SwiftUI
import UIKit

/// A two-zone background split by a seam that arcs upward toward the center, instead of a
/// flat color — the bottom zone starts at `topHeight` at the screen edges and rises
/// `peakLift` points higher at the horizontal center. Both zones are the near-black/near-white
/// base tinted with the *complement* of the user's accent color (not the accent itself), top
/// mixed in noticeably stronger than bottom. Tinting toward the accent's own hue read as
/// same-family and didn't give accent-colored elements (the FAB, in-progress borders) any real
/// contrast to pop against; the color-wheel opposite does.
struct CurvedBackground: View {
    var topHeight: CGFloat
    var peakLift: CGFloat = 70

    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    private var tintUIColor: UIColor { UIColor(theme.accentSwatch.complementaryColor) }

    private var baseUIColor: UIColor {
        colorScheme == .dark ? ColorTokens.hex(0x0E0D0C) : ColorTokens.hex(0xFAF9F6)
    }

    private var topColor: Color {
        Color(ColorTokens.mix(tintUIColor, over: baseUIColor, amount: colorScheme == .dark ? 0.32 : 0.24))
    }

    private var bottomColor: Color {
        Color(ColorTokens.mix(tintUIColor, over: baseUIColor, amount: colorScheme == .dark ? 0.10 : 0.06))
    }

    var body: some View {
        ZStack {
            topColor
            CurvedSeam(topHeight: topHeight, peakLift: peakLift)
                .fill(bottomColor)
        }
        .ignoresSafeArea()
    }
}

private struct CurvedSeam: Shape {
    var topHeight: CGFloat
    var peakLift: CGFloat

    func path(in rect: CGRect) -> Path {
        let edgeY = topHeight
        let peakY = topHeight - peakLift
        var path = Path()
        path.move(to: CGPoint(x: 0, y: edgeY))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: edgeY), control: CGPoint(x: rect.width / 2, y: peakY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}
