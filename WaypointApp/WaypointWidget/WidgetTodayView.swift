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

    /// Medium fits a header and about three rows; large about nine. Fixed, because a widget is
    /// a rectangle the system sizes — there is no scrolling to fall back on.
    private var rowLimit: Int { family == .systemLarge ? 6 : 3 }

    private var visible: [DaySnapshot.Item] { Array(snapshot.items.prefix(rowLimit)) }
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
                rule.padding(.vertical, 11)
                VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 6) {
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
                    .font(.system(size: 19, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.white)
                Text(snapshot.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                Text("\(snapshot.done) of \(snapshot.total) done · \(snapshot.remainingLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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
            Circle().stroke(.white.opacity(0.3), lineWidth: 6)

            Circle()
                .trim(from: 0, to: snapshot.fraction)
                .stroke(.white, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .blur(radius: 5)
                .opacity(0.55)

            Circle()
                .trim(from: 0, to: snapshot.fraction)
                .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int(snapshot.fraction * 100))%")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 56, height: 56)
    }

    /// Each row links into the app's focus timer for that task. A widget can only open a URL or
    /// run a small background action, and starting a timer the user can't then see or stop
    /// would be the wrong half of the job — so the tap brings them to the timer itself.
    private func row(_ item: DaySnapshot.Item) -> some View {
        Link(destination: URL(string: "waypoint://focus/\(item.id.uuidString)")!) {
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
}
