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
    /// Whether anything is actually happening.
    ///
    /// **Stillness is the paused state.** The waterline used to ripple regardless, so a stopped
    /// clock sat behind moving water — which reads as running, on the one screen where the
    /// difference matters. Now motion means running, and that consistency is the whole licence
    /// for the bubbles below: they're a second way of saying the same true thing, rather than
    /// decoration that happens to be moving.
    var isRunning: Bool
    var tint: Color
    var line: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The opacity of the filled region. Low enough that text sitting in it still reads.
    static let washOpacity: Double = 0.16
    static let paperWashOpacity: Double = 0.07

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: reduceMotion || !isRunning)) { context in
            Canvas { ctx, size in
                let moving = isRunning && !reduceMotion
                let t = context.date.timeIntervalSinceReferenceDate
                draw(in: &ctx, size: size, phase: moving ? t * 1.1 : 0, time: moving ? t : nil)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, phase: Double, time: Double?) {
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

        if let time { drawBubbles(in: &ctx, size: size, fillY: fillY, time: time) }

        ctx.stroke(edge, with: .color(line.opacity(0.75)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
    }

    /// A handful of slow bubbles rising to the surface, only while the session runs.
    ///
    /// **Six, slow, and faint on purpose.** The body of the water is the one large still region
    /// on the screen, and a few bubbles make it read as liquid rather than as a coloured
    /// rectangle. More than a handful, or any real speed, and it becomes a lava lamp in the
    /// corner of the eye of someone trying to concentrate — which is the thing the flat-below,
    /// moving-only-at-the-line rule exists to prevent.
    ///
    /// Positions come from the index rather than an RNG: a `Canvas` redraws twelve times a
    /// second and anything random would respawn every frame. Each bubble's phase is offset so
    /// they don't rise in lockstep, and they fade out as they reach the surface rather than
    /// popping against the waterline.
    private func drawBubbles(in ctx: inout GraphicsContext, size: CGSize, fillY: CGFloat, time: Double) {
        let count = 6
        let depth = size.height - fillY
        guard depth > 40 else { return }

        for i in 0..<count {
            let seed = Double(i)
            // The golden ratio keeps the columns from lining up into a visible grid. Offset by
            // half a step first, or bubble zero sits at exactly x = 0 and rises half off the
            // left edge of the screen.
            let spread = ((seed + 0.5) * 0.6180339887).truncatingRemainder(dividingBy: 1)
            // Inset from both edges, so none of them grazes the rim.
            let x = size.width * (0.08 + 0.84 * CGFloat(spread))
            let speed = 22.0 + seed.truncatingRemainder(dividingBy: 3) * 7
            let travelled = (time * speed + seed * 97).truncatingRemainder(dividingBy: Double(depth))
            let y = size.height - CGFloat(travelled)

            // Fade in off the bottom and out as it nears the surface, so nothing appears or
            // vanishes abruptly.
            let fromSurface = (y - fillY) / depth
            let fade = min(fromSurface * 4, min((1 - fromSurface) * 5, 1))
            guard fade > 0 else { continue }

            let r = 1.6 + CGFloat(seed.truncatingRemainder(dividingBy: 3)) * 0.9
            ctx.fill(
                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                with: .color(line.opacity(0.18 * fade))
            )
        }
    }
}
