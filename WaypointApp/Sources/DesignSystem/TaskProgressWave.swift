import SwiftUI

/// The in-progress task row's background: a tinted wash growing left-to-right with a
/// rippling waterline at its leading edge — the "water tank" idea rotated 90°. Fill width
/// is elapsed ÷ scheduled duration, recomputed every frame via `TimelineView`, not a
/// canned loop, so it tracks real time even if nothing else re-renders the row.
struct TaskProgressWave: View {
    var start: Date
    var end: Date
    var tint: Color
    var line: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: false)) { context in
            Canvas { ctx, size in
                let progress = progress(at: context.date)
                let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 1.6
                draw(in: &ctx, size: size, progress: progress, phase: phase)
            }
        }
        .allowsHitTesting(false)
    }

    private func progress(at now: Date) -> CGFloat {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return CGFloat(min(max(now.timeIntervalSince(start) / total, 0), 1))
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, progress: CGFloat, phase: Double) {
        let fillX = progress * size.width
        let amplitude: CGFloat = 3.2
        let freq = (2 * .pi) / (size.height / 1.4)
        let step: CGFloat = 3

        var points: [CGPoint] = []
        var y: CGFloat = 0
        while y <= size.height {
            points.append(CGPoint(x: fillX + amplitude * sin(y * freq + phase), y: y))
            y += step
        }

        // Base: the whole card stays tinted regardless of progress, same as every other
        // row state — only the waterline should read as "progress," not a stark
        // filled-vs-transparent split.
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(tint))

        // The filled region gets a wash of the accent color itself (not black) so it reads
        // as visibly more saturated than the unfilled tint, staying in the same hue family.
        var fillPath = Path()
        fillPath.move(to: CGPoint(x: 0, y: 0))
        fillPath.addLines(points)
        fillPath.addLine(to: CGPoint(x: 0, y: size.height))
        fillPath.closeSubpath()
        ctx.fill(fillPath, with: .color(line.opacity(0.22)))

        var edgePath = Path()
        edgePath.addLines(points)
        ctx.stroke(edgePath, with: .color(line), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
    }
}
