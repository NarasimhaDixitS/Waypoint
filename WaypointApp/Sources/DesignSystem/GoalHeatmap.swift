import SwiftUI

/// A goal's history as a calendar grid: weeks across, weekdays down.
///
/// **Why a grid and not another chart.** The goal page already has a burndown (are you on
/// pace?) and a weekday bar chart (which days you show up). Neither answers "what did the last
/// two months actually look like", which is the question a heatmap is uniquely good at — you
/// see the fortnight you lost without reading a single number.
///
/// **Days with no tasks are drawn differently from days you missed.** An empty day gets a faint
/// outline; a day with work gets filled by how much of it you did. Collapsing those two into
/// one ramp would tell you that a goal asking nothing of you on Sunday was a Sunday you failed.
/// Same instinct as `GoalWeekStrip`, which leaves a missed day hollow rather than quietly
/// resetting a streak.
///
/// Colour comes from the accent, which is already monochrome in paper — so this needs no
/// palette branch of its own. See `PaletteContrastTests`.
struct GoalHeatmap: View {
    @EnvironmentObject private var theme: ThemeManager

    let days: [ProgressAnalytics.HeatDay]

    private let gap: CGFloat = 3
    /// Squares grow to fill the card and stop at `maxCell`, rather than sitting at one fixed
    /// size. A goal two weeks old has three columns, and three 13pt squares stranded in the
    /// corner of a full-width card read as a rendering fault rather than as a short history.
    /// Growing them says the same true thing and looks deliberate at any age.
    private let minCell: CGFloat = 11
    private let maxCell: CGFloat = 26
    /// Width of the weekday label gutter plus the gap after it.
    private let gutter: CGFloat = 16
    /// The grid never draws narrower than this many weeks.
    ///
    /// A goal two weeks old otherwise fills a fifth of the card and leaves the rest blank,
    /// which reads as something failing to render. The padding is drawn as faint dots, not
    /// empty squares — exactly the distinction `GoalWeekStrip` makes, and for the same reason:
    /// a day before this goal existed is not a day you missed, and an outlined square sitting
    /// in a grid of outlined squares would say it was.
    private let minWeeks = 9

    /// Monday-first, matching the rest of the app. Hardcoded rather than taken from the
    /// calendar's symbols: the simulator's `en_IN` locale returns blanks for
    /// `veryShortWeekdaySymbols`, which is how the goal strip lost its letters once.
    private let rowLabels = ["M", "", "W", "", "F", "", "S"]

    /// Columns of seven, each starting on a Monday. The first column is padded with blanks so
    /// a goal that began on a Thursday still lines up under the right weekday.
    private var weeks: [[ProgressAnalytics.HeatDay?]] {
        guard let first = days.first else { return [] }
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let leading = (calendar.component(.weekday, from: first.date) + 5) % 7

        var padded: [ProgressAnalytics.HeatDay?] = Array(repeating: nil, count: leading)
        padded.append(contentsOf: days.map { Optional($0) })
        while padded.count % 7 != 0 { padded.append(nil) }

        var columns = stride(from: 0, to: padded.count, by: 7).map { Array(padded[$0..<$0 + 7]) }
        // Padded at the front, so the goal's history stays flush right against today.
        while columns.count < minWeeks {
            columns.insert(Array(repeating: nil, count: 7), at: 0)
        }
        return columns
    }

    private func cellSize(forWidth width: CGFloat) -> CGFloat {
        let columns = max(weeks.count, 1)
        let available = width - gutter - gap * CGFloat(columns - 1)
        return min(maxCell, max(minCell, available / CGFloat(columns)))
    }

    var body: some View {
        if days.isEmpty {
            Text("Nothing scheduled for this goal yet.")
                .wpTypography(.body)
                .foregroundStyle(ColorTokens.textMuted)
        } else {
            // Measured rather than assumed: the card's width differs between devices, and a
            // heatmap that overflows its card is worse than one that's slightly small.
            GeometryReader { geo in
                grid(cell: cellSize(forWidth: geo.size.width))
            }
            .frame(height: gridHeight)
        }
    }

    /// Seven rows of squares plus the legend beneath, at whatever size fits.
    private var gridHeight: CGFloat {
        // Resolved against the narrowest phone so the frame is never shorter than the content
        // it has to hold; a wider screen just leaves a little air under the legend.
        let cell = cellSize(forWidth: 320)
        return cell * 7 + gap * 6 + 28
    }

    @ViewBuilder
    private func grid(cell: CGFloat) -> some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(spacing: gap) {
                        ForEach(rowLabels.indices, id: \.self) { index in
                            Text(rowLabels[index])
                                .wpTypography(.micro)
                                .foregroundStyle(ColorTokens.textMuted)
                                .frame(width: 10, height: cell)
                        }
                    }

                    // Scrolls, and starts at the right: a long goal's recent weeks are what
                    // you came to look at, not its first fortnight.
                    ScrollView(.horizontal, showsIndicators: false) {
                        ScrollViewReader { proxy in
                            HStack(spacing: gap) {
                                ForEach(weeks.indices, id: \.self) { column in
                                    VStack(spacing: gap) {
                                        ForEach(0..<7, id: \.self) { row in
                                            square(weeks[column][row], cell: cell)
                                        }
                                    }
                                    .id(column)
                                }
                            }
                            .onAppear { proxy.scrollTo(weeks.count - 1, anchor: .trailing) }
                        }
                    }
                }

                legend
            }
        }
    }

    @ViewBuilder
    private func square(_ day: ProgressAnalytics.HeatDay?, cell: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cell > 18 ? 5 : 3, style: .continuous)
        if let day, let fraction = day.fraction {
            shape
                .fill(theme.accentSwatch.markColor.opacity(0.22 + 0.78 * fraction))
                .frame(width: cell, height: cell)
                .accessibilityLabel("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(day.done) of \(day.total) done")
        } else if day != nil {
            // A day inside the goal that asked nothing of you.
            shape
                .stroke(ColorTokens.border, lineWidth: 1)
                .frame(width: cell, height: cell)
                .accessibilityHidden(true)
        } else {
            // Outside the goal entirely — before it started, or after today. A dot, not a
            // ring: a ring is a container with nothing in it, which is what "missed" looks
            // like. This just holds the place.
            Circle()
                .fill(ColorTokens.textMuted.opacity(0.22))
                .frame(width: max(3, cell * 0.22), height: max(3, cell * 0.22))
                .frame(width: cell, height: cell)
                .accessibilityHidden(true)
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less")
                .wpTypography(.micro)
                .foregroundStyle(ColorTokens.textMuted)
            ForEach([0.0, 0.33, 0.66, 1.0], id: \.self) { step in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(theme.accentSwatch.markColor.opacity(0.22 + 0.78 * step))
                    .frame(width: 10, height: 10)
            }
            Text("More")
                .wpTypography(.micro)
                .foregroundStyle(ColorTokens.textMuted)
        }
        .accessibilityHidden(true)
    }
}
