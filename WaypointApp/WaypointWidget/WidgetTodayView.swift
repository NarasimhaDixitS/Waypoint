import SwiftUI
import WidgetKit

/// The Today banner, rebuilt at widget scale.
///
/// Shares the app's tokens rather than restating them, so the accent, the ink and the surfaces
/// stay in step — a widget drifting a shade away from the app it belongs to is the thing that
/// makes both look unfinished.
struct WidgetTodayView: View {
    let snapshot: DaySnapshot
    @Environment(\.widgetFamily) private var family

    private var accent: Color { AccentSwatch.current.markColor }

    /// Medium fits a header and about three rows; large about nine. Fixed, because a widget is
    /// a rectangle the system decides the size of — there is no scrolling to fall back on.
    private var rowLimit: Int { family == .systemLarge ? 9 : 3 }

    private var visible: [DaySnapshot.Item] { Array(snapshot.items.prefix(rowLimit)) }
    private var overflow: Int { max(0, snapshot.items.count - visible.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if snapshot.items.isEmpty {
                Spacer(minLength: 0)
                Text("Nothing scheduled today.")
                    .font(.system(size: 13))
                    .foregroundStyle(ColorTokens.textMuted)
                Spacer(minLength: 0)
            } else {
                Rectangle()
                    .fill(ColorTokens.border)
                    .frame(height: 1)
                VStack(alignment: .leading, spacing: family == .systemLarge ? 7 : 5) {
                    ForEach(visible) { item in
                        row(item)
                    }
                    if overflow > 0 {
                        Text("+\(overflow) more")
                            .font(.system(size: 11))
                            .foregroundStyle(ColorTokens.textMuted)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TODAY")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(ColorTokens.textSecondary)
                Text("\(snapshot.done) of \(snapshot.total) done")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ColorTokens.textPrimary)
                Text(snapshot.remainingLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(ColorTokens.textSecondary)
            }
            Spacer(minLength: 0)
            ring
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(ColorTokens.border, lineWidth: 5)
            Circle()
                .trim(from: 0, to: snapshot.fraction)
                .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(snapshot.fraction * 100))%")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ColorTokens.textPrimary)
        }
        .frame(width: 46, height: 46)
    }

    /// Each row is a link into the app's focus timer for that task. A widget can only open a
    /// URL or run a small background action, and starting a timer you then can't see or stop
    /// would be the wrong half of the job — so the tap takes you to the thing itself.
    private func row(_ item: DaySnapshot.Item) -> some View {
        Link(destination: URL(string: "waypoint://focus/\(item.id.uuidString)")!) {
            HStack(spacing: 8) {
                Text(item.start.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(ColorTokens.textMuted)
                    .frame(width: 52, alignment: .leading)

                Text(item.title)
                    .font(.system(size: 13, weight: item.isRunning ? .semibold : .regular))
                    .foregroundStyle(item.isDone ? ColorTokens.textMuted : ColorTokens.textPrimary)
                    .strikethrough(item.isDone)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if item.isRunning {
                    // Self-updating: `Text(timerInterval:)` ticks in place without spending a
                    // timeline refresh, which is the one way a widget can genuinely be live.
                    Text(timerInterval: Date.now...item.end, countsDown: true)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .padding(.vertical, 1)
        }
    }
}
