import SwiftUI

/// A rising waterline over whatever it's placed behind — the focus screen's progress.
///
/// **The same idea as `TaskProgressWave`, turned ninety degrees and driven differently.** That
/// one fills a row left to right and reads progress off the wall clock, which is right for a
/// card that just sits there elapsing. A timer pauses, so its progress can't come from the
/// clock; this takes an explicit fraction and lets the caller decide what it means.
///
/// **Flat below the line, moving only at the line.** The whole page is the vessel here, and a
/// full screen of motion for the length of a work block is the opposite of what a focus timer
/// is for. The ripple is a thin band that creeps upward; everything under it is still.
///
/// The wash is deliberately light. A wavy edge does nothing for readability — the water rises
/// and stays, so every element ends up inside it permanently — and what carries the text is the
/// fill being something you read *through*. Measured against `textPrimary` at full fill rather
/// than assumed; see `WaveFillTests`.
struct WaveFill: View {
    /// 0 is empty, 1 is full.
    var progress: Double
    var tint: Color
    var line: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The opacity of the filled region. Low enough that text sitting in it still reads.
    static let washOpacity: Double = 0.16
    static let paperWashOpacity: Double = 0.07

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: reduceMotion)) { context in
            Canvas { ctx, size in
                let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 1.1
                draw(in: &ctx, size: size, phase: phase)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, phase: Double) {
        let clamped = min(max(progress, 0), 1)
        // Measured from the bottom: empty is an empty glass.
        let fillY = size.height * (1 - clamped)

        // Gentler than the row's. That one crosses a 70pt card in a couple of seconds of
        // reading; this one is in someone's peripheral vision for forty minutes.
        let amplitude: CGFloat = 4.5
        let freq = (2 * .pi) / (size.width / 1.6)
        let step: CGFloat = 4

        var points: [CGPoint] = []
        var x: CGFloat = 0
        while x <= size.width {
            points.append(CGPoint(x: x, y: fillY + amplitude * sin(x * freq + phase)))
            x += step
        }
        // The loop can stop short of the trailing edge, which left a sliver of unfilled page
        // down the right-hand side at some widths.
        points.append(CGPoint(x: size.width, y: fillY + amplitude * sin(size.width * freq + phase)))

        var fill = Path()
        fill.addLines(points)
        fill.addLine(to: CGPoint(x: size.width, y: size.height))
        fill.addLine(to: CGPoint(x: 0, y: size.height))
        fill.closeSubpath()

        let wash = Palette.current == .paper ? Self.paperWashOpacity : Self.washOpacity
        ctx.fill(fill, with: .color(tint.opacity(wash)))

        var edge = Path()
        edge.addLines(points)

        // Same reasoning as the row: a real blur rather than stacked strokes, which banded.
        // Paper is matte and gets none of it.
        if Palette.current.usesDepth {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 4))
                layer.stroke(
                    edge,
                    with: .color(line.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
            }
        }

        ctx.stroke(edge, with: .color(line.opacity(0.75)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
    }
}
