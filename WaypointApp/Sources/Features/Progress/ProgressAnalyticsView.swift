import SwiftUI
import Charts
import CoreData

/// Nine analyses, each in its own card, each stating its own conclusion above its evidence.
///
/// The screen this replaced drew four numbers from a single field (`isDone`) — a four-week bar
/// chart, an average, a streak and one canned sentence. Everything here comes out of
/// `ProgressAnalytics`, which is pure and tested; this file is layout and wording only.
struct ProgressAnalyticsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @FetchRequest private var recentTasks: FetchedResults<TaskEntity>
    @FetchRequest private var events: FetchedResults<TaskEventEntity>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \GoalEntity.createdAt, ascending: true)])
    private var goals: FetchedResults<GoalEntity>

    /// 120 days rather than 60: weekday and time-of-day breakdowns divide the window into 7 and
    /// 42 buckets respectively, so a two-month window leaves single figures in each and noise
    /// that looks like signal.
    init() {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 90, to: cal.startOfDay(for: .now))!
        let start = cal.date(byAdding: .day, value: -120, to: cal.startOfDay(for: .now))!
        _recentTasks = FetchRequest(fetchRequest: TaskEntity.fetchRequest(from: start, to: end))
        _events = FetchRequest(fetchRequest: TaskEventEntity.fetchRequest(kind: nil, since: start))
    }

    private var tasks: [TaskEntity] { Array(recentTasks) }
    private var allEvents: [TaskEventEntity] { Array(events) }
    private var accent: Color { theme.accentSwatch.markColor }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Progress")
                    .wpTypography(.appTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .padding(.top, 8)

                headline
                weekdayCard
                effortCard
                deferralCard
                slipCard
                priorityCard
                goalSplitCard
                habitCard
                timeOfDayCard
                burndownCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 140)
        }
        .background(ColorTokens.surface0.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    // MARK: - Headline

    private var headline: some View {
        let elapsed = tasks.filter { Calendar.current.startOfDay(for: $0.resolvedDate) <= Calendar.current.startOfDay(for: .now) }
        let done = elapsed.filter(\.isDone).count
        let rate = elapsed.isEmpty ? 0 : Double(done) / Double(elapsed.count)
        let deferrals = allEvents.filter { $0.kindValue == .deferred }.count
        return HStack(spacing: 10) {
            statTile(value: "\(Int(rate * 100))%", label: "Completed")
            statTile(value: "\(done)", label: "Tasks done")
            statTile(value: "\(deferrals)", label: "Times put off")
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).wpTypography(.bigStat).foregroundStyle(ColorTokens.textPrimary).monospacedDigit()
            Text(label).wpTypography(.micro).foregroundStyle(ColorTokens.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .wpCard(padding: 0)
    }

    // MARK: - 1. Weekday

    private var weekdayCard: some View {
        let data = ProgressAnalytics.completionByWeekday(tasks)
        let withWork = data.filter { $0.total > 0 }
        let best = withWork.max { $0.fraction < $1.fraction }
        let worst = withWork.min { $0.fraction < $1.fraction }
        let caption: String = if let best, let worst, best.id != worst.id {
            "\(best.label) is your strongest day at \(Int(best.fraction * 100))%. \(worst.label) is your weakest at \(Int(worst.fraction * 100))%."
        } else {
            "How much of what you schedule actually gets done, by day of the week."
        }
        return AnalyticsCard(title: "Which days you deliver", caption: caption) {
            if withWork.isEmpty {
                AnalyticsEmpty(message: "No days have come round yet.")
            } else {
                Chart(data) { row in
                    BarMark(x: .value("Day", row.label), y: .value("Completed", row.fraction))
                        .foregroundStyle(row.id == worst?.id ? ColorTokens.warning : accent)
                        .cornerRadius(5)
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.5, 1]) { value in
                        AxisGridLine().foregroundStyle(ColorTokens.border)
                        AxisValueLabel {
                            if let raw = value.as(Double.self) {
                                Text("\(Int(raw * 100))%").wpTypography(.micro)
                            }
                        }
                    }
                }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().font(WPTypography.micro.font) } }
                .frame(height: 150)
            }
        }
    }

    // MARK: - 2. Effort

    private var effortCard: some View {
        let data = ProgressAnalytics.effortByWeek(tasks)
        let latest = data.last
        let caption: String = if let latest, latest.plannedHours > 0 {
            "This week you planned \(hours(latest.plannedHours)) and completed \(hours(latest.completedHours)). Task counts hide this — a short errand and a long block count the same."
        } else {
            "Hours planned against hours completed, week by week."
        }
        return AnalyticsCard(title: "Hours planned vs done", caption: caption) {
            if data.allSatisfy({ $0.plannedMinutes == 0 }) {
                AnalyticsEmpty(message: "Nothing scheduled in the last six weeks.")
            } else {
                Chart(data) { week in
                    AreaMark(x: .value("Week", week.weekStart), y: .value("Planned", week.plannedHours))
                        .foregroundStyle(accent.opacity(0.16))
                    LineMark(x: .value("Week", week.weekStart), y: .value("Planned", week.plannedHours))
                        .foregroundStyle(ColorTokens.textMuted)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    LineMark(x: .value("Week", week.weekStart), y: .value("Done", week.completedHours))
                        .foregroundStyle(accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .symbol(.circle)
                }
                .chartXAxis {
                    AxisMarks(values: data.map(\.weekStart)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(.dateTime.day().month(.abbreviated))).wpTypography(.micro)
                            }
                        }
                    }
                }
                .chartYAxis { AxisMarks { _ in
                    AxisGridLine().foregroundStyle(ColorTokens.border)
                    AxisValueLabel().font(WPTypography.micro.font)
                } }
                .frame(height: 160)
                legend(items: [("Planned", ColorTokens.textMuted), ("Completed", accent)])
            }
        }
    }

    // MARK: - 3. Deferrals

    private var deferralCard: some View {
        let data = ProgressAnalytics.deferralLeaderboard(allEvents)
        let caption: String = if let top = data.first {
            "\"\(top.title)\" has been pushed \(top.times) \(top.times == 1 ? "time" : "times"), \(top.totalDays) days in total."
        } else {
            "Nothing has been pushed to a later day yet."
        }
        return AnalyticsCard(title: "What you keep putting off", caption: caption) {
            if data.isEmpty {
                AnalyticsEmpty(message: "No deferrals recorded.")
            } else {
                Chart(data) { row in
                    BarMark(
                        x: .value("Days", row.totalDays),
                        y: .value("Task", row.title)
                    )
                    .foregroundStyle(ColorTokens.warning)
                    .cornerRadius(5)
                    .annotation(position: .trailing) {
                        Text("\(row.times)×").wpTypography(.micro).foregroundStyle(ColorTokens.textMuted)
                    }
                }
                .chartXAxis { AxisMarks { _ in
                    AxisGridLine().foregroundStyle(ColorTokens.border)
                    AxisValueLabel().font(WPTypography.micro.font)
                } }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().font(WPTypography.micro.font) } }
                .frame(height: CGFloat(data.count) * 34 + 24)
            }
        }
    }

    // MARK: - 4. Slip sizes

    private var slipCard: some View {
        let data = ProgressAnalytics.slipDistribution(allEvents)
        let total = data.reduce(0) { $0 + $1.count }
        let long = data.filter { $0.id == "4–7" || $0.id == "Over a week" }.reduce(0) { $0 + $1.count }
        let caption: String = total == 0
            ? "How far you push things when you push them."
            : "\(long) of \(total) deferrals moved work more than three days. Short slips are scheduling; long ones are avoidance."
        return AnalyticsCard(title: "How far you push things", caption: caption) {
            if total == 0 {
                AnalyticsEmpty(message: "No deferrals recorded.")
            } else {
                Chart(data) { bucket in
                    BarMark(x: .value("Slip", bucket.label), y: .value("Count", bucket.count))
                        .foregroundStyle(bucket.id == "Over a week" ? ColorTokens.warning : accent)
                        .cornerRadius(5)
                }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().font(WPTypography.micro.font) } }
                .chartYAxis { AxisMarks { _ in
                    AxisGridLine().foregroundStyle(ColorTokens.border)
                    AxisValueLabel().font(WPTypography.micro.font)
                } }
                .frame(height: 130)
            }
        }
    }

    // MARK: - 5. Priority

    private var priorityCard: some View {
        let data = ProgressAnalytics.priorityFollowThrough(tasks)
        let high = data.first { $0.id == Priority.high.rawValue }
        let low = data.first { $0.id == Priority.low.rawValue }
        let caption: String = if let high, let low, high.total > 0, low.total > 0, low.fraction > high.fraction {
            "You finish \(Int(low.fraction * 100))% of low-priority work but only \(Int(high.fraction * 100))% of high. The easy things are winning."
        } else {
            "Completion rate by the priority you gave the task."
        }
        return AnalyticsCard(title: "Do you do the important things?", caption: caption) {
            if data.allSatisfy({ $0.total == 0 }) {
                AnalyticsEmpty(message: "Not enough finished work yet.")
            } else {
                VStack(spacing: 12) {
                    ForEach(data) { row in
                        RatioBar(
                            label: row.label, done: row.done, total: row.total,
                            fraction: row.fraction,
                            tint: row.id == Priority.high.rawValue ? ColorTokens.warning : accent
                        )
                    }
                }
            }
        }
    }

    // MARK: - 6. Effort split by goal (donut)

    private var goalSplitCard: some View {
        let data = ProgressAnalytics.effortByGoal(tasks)
        let total = data.reduce(0) { $0 + $1.value }
        let caption: String = if let top = data.first, total > 0 {
            "\(top.label) took \(Int(top.value / total * 100))% of the \(hours(total)) you finished."
        } else {
            "Where your completed hours actually went."
        }
        return AnalyticsCard(title: "Where your time went", caption: caption) {
            if data.isEmpty {
                AnalyticsEmpty(message: "No completed work to divide up yet.")
            } else {
                HStack(spacing: 18) {
                    Chart(data) { slice in
                        SectorMark(
                            angle: .value("Hours", slice.value),
                            innerRadius: .ratio(0.58),
                            angularInset: 1.5
                        )
                        .foregroundStyle(by: .value("Goal", slice.label))
                        .cornerRadius(3)
                    }
                    .chartLegend(.hidden)
                    .chartForegroundStyleScale(range: donutColors(count: data.count))
                    .frame(width: 132, height: 132)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(data.enumerated()), id: \.element.id) { index, slice in
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(donutColors(count: data.count)[index])
                                    .frame(width: 8, height: 8)
                                Text(slice.label)
                                    .wpTypography(.micro)
                                    .foregroundStyle(ColorTokens.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(hours(slice.value))
                                    .wpTypography(.micro)
                                    .foregroundStyle(ColorTokens.textMuted)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
    }

    /// Tints of the accent rather than a rainbow: the slices are one quantity split up, not
    /// unrelated categories, and a fixed palette would collide with whichever accent is active.
    private func donutColors(count: Int) -> [Color] {
        guard count > 1 else { return [accent] }
        return (0..<count).map { index in
            accent.opacity(1 - (Double(index) / Double(count)) * 0.72)
        }
    }

    // MARK: - 7. Habits

    private var habitCard: some View {
        let data = ProgressAnalytics.seriesAdherence(tasks)
        let caption: String = if let weakest = data.min(by: { $0.fraction < $1.fraction }), data.count > 1 {
            "\(weakest.label) is the habit slipping most — \(weakest.done) of \(weakest.total)."
        } else {
            "How reliably your repeating tasks actually happen."
        }
        return AnalyticsCard(title: "Habits, kept and missed", caption: caption) {
            if data.isEmpty {
                AnalyticsEmpty(message: "No repeating tasks yet — set one up to track a habit.")
            } else {
                VStack(spacing: 12) {
                    ForEach(data) { row in
                        RatioBar(
                            label: row.label, done: row.done, total: row.total,
                            fraction: row.fraction,
                            tint: row.fraction < 0.5 ? ColorTokens.warning : accent
                        )
                    }
                }
            }
        }
    }

    // MARK: - 8. Time of day

    private var timeOfDayCard: some View {
        let observed = ProgressAnalytics.observedCompletionCount(tasks)
        let cells = ProgressAnalytics.completionsByTimeOfDay(tasks)
        let peak = cells.max { $0.count < $1.count }
        let caption: String = if observed < 8 {
            "Needs a few more tasks ticked off by hand — automatic completions are stamped with the scheduled end time, not when you actually stopped."
        } else if let peak, peak.count > 0 {
            "You finish most work \(peak.bandLabel.lowercased()) on \(ProgressAnalytics.weekdayNames[peak.weekday - 1])."
        } else {
            "When in the week you actually finish things."
        }
        return AnalyticsCard(title: "When you get things done", caption: caption) {
            if observed < 8 {
                AnalyticsEmpty(message: "Only \(observed) completions carry a real timestamp so far.")
            } else {
                Chart(cells) { cell in
                    RectangleMark(
                        x: .value("Day", ProgressAnalytics.weekdayNames[cell.weekday - 1]),
                        y: .value("Time", cell.bandLabel)
                    )
                    .foregroundStyle(accent.opacity(cell.count == 0 ? 0.06 : intensity(cell.count, in: cells)))
                    .cornerRadius(3)
                }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().font(WPTypography.micro.font) } }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().font(WPTypography.micro.font) } }
                .frame(height: 190)
            }
        }
    }

    private func intensity(_ count: Int, in cells: [ProgressAnalytics.HeatCell]) -> Double {
        let peak = cells.map(\.count).max() ?? 1
        guard peak > 0 else { return 0.06 }
        return 0.18 + 0.82 * (Double(count) / Double(peak))
    }

    // MARK: - 9. Burn-down

    private var burndownCard: some View {
        let goal = goals.first { !$0.sortedTasks.isEmpty }
        let points = goal.map { ProgressAnalytics.burndown(for: $0) } ?? []
        let last = points.last
        let caption: String = if let goal, let last {
            Double(last.remaining) <= last.idealRemaining
                ? "\(goal.name ?? "This goal") is on or ahead of the pace it needs."
                : "\(goal.name ?? "This goal") is behind pace — \(last.remaining) left where an even run would have \(Int(last.idealRemaining))."
        } else {
            "Work remaining against the pace the deadline needs."
        }
        return AnalyticsCard(title: "Will you make the deadline?", caption: caption) {
            if points.isEmpty {
                AnalyticsEmpty(message: "Create a goal with a target date to see its pace.")
            } else {
                GoalBurndownChart(points: points, accent: accent)
            }
        }
    }

    // MARK: - Bits

    private func hours(_ value: Double) -> String {
        value >= 10 ? "\(Int(value.rounded()))h" : String(format: "%.1fh", value)
    }

    private func legend(items: [(String, Color)]) -> some View {
        HStack(spacing: 14) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 6) {
                    Capsule().fill(item.1).frame(width: 14, height: 3)
                    Text(item.0).wpTypography(.micro).foregroundStyle(ColorTokens.textSecondary)
                }
            }
        }
    }
}

/// Shared with `GoalDetailView`, which draws the same chart for one specific goal.
struct GoalBurndownChart: View {
    let points: [ProgressAnalytics.BurndownPoint]
    let accent: Color

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Ideal", point.idealRemaining),
                    series: .value("Series", "Ideal")
                )
                .foregroundStyle(ColorTokens.textMuted)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Remaining", point.remaining)
                )
                .foregroundStyle(accent.opacity(0.14))
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Remaining", point.remaining),
                    series: .value("Series", "Actual")
                )
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
        }
        .chartXAxis { AxisMarks { _ in
            AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(WPTypography.micro.font)
        } }
        .chartYAxis { AxisMarks { _ in
            AxisGridLine().foregroundStyle(ColorTokens.border)
            AxisValueLabel().font(WPTypography.micro.font)
        } }
        .frame(height: 170)
    }
}
