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
        // Walk the region explicitly: down the waterline, along the bottom, up the left edge,
        // and let `closeSubpath` run the top edge back to the waterline's start. The leading
        // `move(to:)` this used to have was dead weight — `addLines` begins with a move of its
        // own, so it opened a second subpath starting at the *top of the waterline*, and the
        // close then cut a diagonal from the bottom-left corner back up to it. The fill was a
        // triangle, not a filled column.
        var fillPath = Path()
        fillPath.addLines(points)
        fillPath.addLine(to: CGPoint(x: 0, y: size.height))
        fillPath.addLine(to: CGPoint(x: 0, y: 0))
        fillPath.closeSubpath()
        ctx.fill(fillPath, with: .color(line.opacity(0.22)))

        var edgePath = Path()
        edgePath.addLines(points)

        // Aura: the waterline is the one element on this row that actually moves, so it — not
        // the card — carries the glow. A halo around the card itself would just be a second
        // shadow fighting the row's own elevation.
        //
        // This has to be a real blur. Stacking two wider, dimmer copies of the stroke was the
        // cheap version, and at these widths the steps between them stayed visible as discrete
        // bands beside the line — it read as misregistered printing, not as light. A blurred
        // layer is the only thing that gives a continuous falloff. It's dark ink over a light
        // card in light mode, so there it lands as a soft depth cue rather than a true glow;
        // in dark mode, where `line` is a warm off-white, it genuinely emits.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 3.5))
            layer.stroke(
                edgePath,
                with: .color(line.opacity(0.45)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
        }

        ctx.stroke(edgePath, with: .color(line), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
    }
}
