import SwiftUI
import WidgetKit

/// The Today card from the app, at widget scale.
///
/// Accent-filled with white ink rather than a neutral surface — the first pass drew a grey card
/// with an accent ring, which read as a different app's widget sitting next to the one it came
/// from. A widget is the app's face on the home screen: if it doesn't look like the thing it
/// opens, it looks like it belongs to nobody.
///
/// Tokens come from the app rather than being restated here, so the accent, the ink and the
/// ring's weights stay in step by construction.
struct WidgetTodayView: View {
    let snapshot: DaySnapshot
    @Environment(\.widgetFamily) private var family

    /// Each family gets its own proportions rather than one layout squeezed into both.
    ///
    /// Medium was running past its content area, which is why it ended up pressed against the
    /// edges: a widget doesn't scroll or clip gracefully, it just fills and touches the sides.
    /// The margin isn't decoration — it's the thing that makes it read as a card rather than a
    /// coloured rectangle, so the content has to be sized to leave it alone.
    private struct Metrics {
        let rowLimit: Int
        let ringSize: CGFloat
        let ringWidth: CGFloat
        let titleSize: CGFloat
        /// Medium has no room for both the date and the counts, and the counts say more.
        let showsDate: Bool
        let rulePadding: CGFloat
        let rowSpacing: CGFloat
    }

    private var metrics: Metrics {
        family == .systemLarge
            ? Metrics(rowLimit: 6, ringSize: 58, ringWidth: 6, titleSize: 20,
                      showsDate: true, rulePadding: 12, rowSpacing: 8)
            : Metrics(rowLimit: 3, ringSize: 48, ringWidth: 5, titleSize: 17,
                      showsDate: false, rulePadding: 8, rowSpacing: 5)
    }

    private var visible: [DaySnapshot.Item] { Array(snapshot.items.prefix(metrics.rowLimit)) }
    private var overflow: Int { max(0, snapshot.items.count - visible.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if snapshot.items.isEmpty {
                Spacer(minLength: 0)
                Text("Nothing scheduled today.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            } else {
                rule.padding(.vertical, metrics.rulePadding)
                VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                    ForEach(visible) { item in
                        row(item)
                    }
                    if overflow > 0 {
                        Text("+\(overflow) more")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }

            // Large left a dead half-screen under a short list. The strip fills it with the
            // same thing the app's card puts there rather than padding — and on a day with two
            // tasks, a week of context is more use than white space.
            if family == .systemLarge {
                Spacer(minLength: 12)
                rule.padding(.bottom, 10)
                weekStrip
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private var rule: some View {
        Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
    }

    private var weekStrip: some View {
        VStack(spacing: 8) {
            Text("Last 7 days")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            HStack(spacing: 0) {
                ForEach(Array(zip(snapshot.week, snapshot.weekLetters()).enumerated()), id: \.offset) { index, pair in
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .strokeBorder(.white.opacity(pair.0 ? 1 : 0.4), lineWidth: 1.6)
                                .frame(width: 15, height: 15)
                            if pair.0 {
                                Circle().fill(.white).frame(width: 15, height: 15)
                            }
                            // Today gets a ring around it, the same mark the app's strip uses.
                            if index == snapshot.week.count - 1 {
                                Circle()
                                    .strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
                                    .frame(width: 21, height: 21)
                            }
                        }
                        .frame(height: 21)
                        Text(pair.1)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TODAY")
                    .font(.system(size: metrics.titleSize, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.white)
                if metrics.showsDate {
                    Text(snapshot.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Text("\(snapshot.done) of \(snapshot.total) done · \(snapshot.remainingLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            ring
        }
    }

    /// The app's ring, aura and all. The glow is a wider, blurred copy of the same arc — it
    /// survives into a widget because a widget is rendered once as a static image, so a blur
    /// costs nothing at display time.
    private var ring: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.3), lineWidth: metrics.ringWidth)

            Circle()
                .trim(from: 0, to: snapshot.fraction)
                .stroke(.white, style: StrokeStyle(lineWidth: metrics.ringWidth * 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .blur(radius: metrics.ringWidth * 0.85)
                .opacity(0.55)

            Circle()
                .trim(from: 0, to: snapshot.fraction)
                .stroke(.white, style: StrokeStyle(lineWidth: metrics.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int(snapshot.fraction * 100))%")
                .font(.system(size: metrics.ringSize * 0.25, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: metrics.ringSize, height: metrics.ringSize)
        // The aura is a blur, so it paints past the circle's own bounds. Without room reserved
        // for it the system margin clips the glow flat on the trailing edge.
        .padding(2)
    }

    /// Only the running task links to its focus timer, matching the app — a task row there
    /// shows the play button for `.inProgress` and nothing else. Offering it on finished work
    /// was the widget inventing an action the app doesn't have, and a focus timer for something
    /// already done has nothing to time.
    ///
    /// Every other row still opens the app on Today, via the widget-wide URL. A widget where
    /// most of the surface does nothing reads as broken rather than as deliberate.
    @ViewBuilder
    private func row(_ item: DaySnapshot.Item) -> some View {
        if item.isRunning {
            Link(destination: URL(string: "waypoint://focus/\(item.id.uuidString)")!) {
                rowContent(item)
            }
        } else {
            rowContent(item)
        }
    }

    private func rowContent(_ item: DaySnapshot.Item) -> some View {
            HStack(spacing: 8) {
                Text(item.start.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(item.isDone ? 0.6 : 0.78))
                    .frame(width: 54, alignment: .leading)

                Text(item.title)
                    .font(.system(size: 13, weight: item.isRunning ? .semibold : .regular))
                    // Done work recedes rather than disappearing, so a finished day still reads
                    // as a full day. Only to 0.8 though: the strikethrough already says "done",
                    // and dimming further was doing that job a second time at the cost of
                    // legibility — on the blue accent it measured 1.97:1, which isn't a faded
                    // row, it's an unreadable one.
                    .foregroundStyle(.white.opacity(item.isDone ? 0.8 : 1))
                    .strikethrough(item.isDone)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if item.isRunning {
                    // Self-updating: `Text(timerInterval:)` ticks in place without spending a
                    // timeline refresh, which is the one way a widget can genuinely be live.
                    Text(timerInterval: Date.now...item.end, countsDown: true)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .padding(.vertical, 1)
    }
}
