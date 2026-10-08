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
    @FetchRequest private var sessions: FetchedResults<FocusSessionEntity>

    /// The window every card on the page is drawn from. One setting rather than per-card
    /// controls: nine charts each with their own period would make the page impossible to read
    /// as a whole, since no two numbers would be comparable.
    enum Range: String, CaseIterable, Identifiable {
        case sinceStart, fourWeeks, threeMonths, allTime

        var id: String { rawValue }

        var label: String {
            switch self {
            case .sinceStart: "So far"
            case .fourWeeks: "4 weeks"
            case .threeMonths: "3 months"
            case .allTime: "All time"
            }
        }

        /// How much history a range needs before it's worth offering.
        ///
        /// Handing someone on day three a four-week window shows them twenty-five empty days
        /// and calls it their progress. A range nobody has the data for isn't a choice, it's a
        /// way to make the app look like a record of failure.
        var requiredDays: Int {
            switch self {
            case .sinceStart: 0
            // One week is enough to make any of these worth offering. The first pass demanded
            // two weeks, five weeks and two months, which meant someone with a month of real
            // history was still shown a single option and no way to look at it another way —
            // the gating existed to stop empty screens, not to withhold perspectives from
            // people who have the data for them.
            case .fourWeeks, .threeMonths, .allTime: 7
            }
        }

        /// `nil` means no lower bound.
        var days: Int? {
            switch self {
            case .sinceStart, .allTime: nil
            case .fourWeeks: 28
            case .threeMonths: 90
            }
        }

        /// How many weeks the effort chart plots. Capped for "all time" — a line with two years
        /// of weekly points on a phone is a smear, not a chart.
        var effortWeeks: Int {
            switch self {
            case .sinceStart: 4
            case .fourWeeks: 4
            case .threeMonths: 12
            case .allTime: 26
            }
        }

        func start(from now: Date = .now, firstActivity: Date? = nil) -> Date {
            if self == .sinceStart {
                return Calendar.current.startOfDay(for: firstActivity ?? now)
            }
            guard let days else { return .distantPast }
            return Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: now))!
        }
    }

/// Three questions, not three arbitrary piles.
    ///
    /// Ten cards of identical weight in an arbitrary order gave a reader no way to tell which
    /// two mattered, and whatever sat past the eighth was never reached. These group by the
    /// question you arrived with — and you arrive with one of them, not all three.
    enum Section: String, CaseIterable, Identifiable {
        case patterns, friction, goals

        var id: String { rawValue }

        var label: String {
            switch self {
            case .patterns: "Patterns"
            case .friction: "Friction"
            case .goals: "Goals"
            }
        }

        var question: String {
            switch self {
            case .patterns: "When and how you work"
            case .friction: "What gets in the way"
            case .goals: "Whether you finish"
            }
        }
    }

    @State private var section: Section = ProgressAnalyticsView.launchSection

    /// Lets a build be launched straight onto one of the three groups: `-wpSection friction`.
    ///
    /// Same reasoning as `MainTabView.launchTab`, and the same debug-only scope. Two of the three
    /// groups are otherwise only reachable by tapping, and the simulator here is driven by hand —
    /// which has meant shipping changes to cards nobody had looked at.
    private static var launchSection: Section {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-wpSection"), flag + 1 < args.count else { return .patterns }
        return Section(rawValue: args[flag + 1]) ?? .patterns
        #else
        return .patterns
        #endif
    }
    @State private var range: Range = .sinceStart
    @State private var didPickInitialRange = false

    /// Only the ranges this person has the history to fill.
    ///
    /// "So far" is always offered and is the honest default early on: it covers exactly what
    /// exists, so nothing on the page is padding. The wider ones appear as the data arrives,
    /// which turns waiting into something that visibly progresses rather than a screen of
    /// empty charts that never explains itself.
    private var availableRanges: [Range] {
        guard let first = firstActivity else { return [.sinceStart] }
        let days = Calendar.current.dateComponents([.day], from: first, to: .now).day ?? 0
        let usable = Range.allCases.filter { days >= $0.requiredDays }
        // `sinceStart` stops being a separate answer once a real window covers the same ground.
        return usable.count > 1 ? usable.filter { $0 != .sinceStart } : usable
    }

    private var firstActivity: Date? {
        TaskEntity.firstActivityDate(in: PersistenceController.shared.container.viewContext)
    }

    /// Tasks scheduled ahead still matter to the current week's effort figures, so the window
    /// runs forward regardless of which range is chosen.
    private static func end(from now: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: 90, to: Calendar.current.startOfDay(for: now))!
    }

    init() {
        // Widest possible at init; `applyRange` narrows it once the real range is chosen, which
        // can't happen here because the context isn't reachable from an initialiser.
        let start = Range.allTime.start()
        _recentTasks = FetchRequest(fetchRequest: TaskEntity.fetchRequest(from: start, to: Self.end()))
        _events = FetchRequest(fetchRequest: TaskEventEntity.fetchRequest(kind: nil, since: start))
        _sessions = FetchRequest(fetchRequest: FocusSessionEntity.fetchRequest(since: start))
    }

    /// `@FetchRequest` is built in `init` and won't follow a changed value on its own, so the
    /// predicates are retargeted here rather than the view being rebuilt around a new identity —
    /// rebuilding would throw away scroll position and every chart's entry animation.
    private func applyRange(_ newRange: Range) {
        let start = newRange.start(firstActivity: firstActivity)
        recentTasks.nsPredicate = NSPredicate(
            format: "date >= %@ AND date < %@", start as NSDate, Self.end() as NSDate
        )
        events.nsPredicate = NSPredicate(format: "occurredAt >= %@", start as NSDate)
        sessions.nsPredicate = NSPredicate(format: "endedAt >= %@", start as NSDate)
    }

    /// A menu rather than a row of pills, and it carries the period label instead of repeating
    /// it underneath. Three pills spent a full-width row saying what one word says, and left two
    /// dead options on screen permanently; the menu states the current window and hides the
    /// alternatives until they're wanted.
    ///
    /// Deliberately the same shape as Today's `Sort:` control — same type size, same capsule,
    /// same muted ink. A second, differently-styled dropdown would read as a different kind of
    /// control doing a different kind of thing.
    private var rangeMenu: some View {
        Menu {
            ForEach(availableRanges) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { range = option }
                } label: {
                    Text(option.label)
                    if range == option { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(range.label)
                    .contentTransition(.opacity)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .wpTypography(.micro)
            .fontWeight(.semibold)
            .foregroundStyle(ColorTokens.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(ColorTokens.surface1)
            .clipShape(Capsule())
        }
    }

    private var tasks: [TaskEntity] { Array(recentTasks) }
    private var allEvents: [TaskEventEntity] { Array(events) }
    /// What's left to arrive — a count going up, not a page quietly getting shorter.
    ///
    /// Hiding the empty cards on their own would make Progress *look* like a thin feature
    /// during exactly the fortnight someone is deciding whether to pay for it. A number that
    /// climbs is a reason to come back; a blank card is a reason not to.
    ///
    /// On a genuinely new account it carries the pitch instead: three specific things the app
    /// will be able to tell them, in the words it will use when it does. Three promises it can
    /// keep beat eleven apologies.
    @ViewBuilder
    private var stillComing: some View {
        let ready = readyCharts
        let waiting = ProgressChart.allCases.filter { !ready.contains($0) }

        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if ready.isEmpty {
                    Text("Waypoint is already recording this.")
                        .wpTypography(.cardTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                    // Named promises rather than a feature list, and the same three every time
                    // so the page doesn't reshuffle its pitch between launches.
                    Text("Give it about a week and it can tell you \(waiting.prefix(3).map(\.promise).joined(separator: ", ")) — from what you actually do, not what you meant to.")
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(ready.count) of \(ProgressChart.allCases.count) ready")
                        .wpTypography(.cardTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                    Text(waiting.count == 1
                         ? "One more appears once there's enough to read: \(waiting[0].promise)."
                         : "\(waiting.count) more appear as you log more days — starting with \(waiting[0].promise).")
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .wpCard()
        }
    }

    private var readyCharts: Set<ProgressChart> {
        ProgressReadiness.ready(
            tasks: tasks,
            events: allEvents,
            sessions: Array(sessions),
            goal: goals.first { !$0.sortedTasks.isEmpty },
            effortWeeks: range.effortWeeks
        )
    }

    private func isReady(_ chart: ProgressChart) -> Bool { readyCharts.contains(chart) }

    private var accent: Color { theme.accentSwatch.markColor }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // The control sits on the title line and states the window itself, so the page
                // still says what period every figure covers — "71%" with no period attached is
                // unreadable — without spending a second line to repeat it.
                HStack(alignment: .firstTextBaseline) {
                    Text("Progress")
                        .wpTypography(.appTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                    Spacer(minLength: 8)
                    rangeMenu
                }
                .padding(.top, 8)

                sectionPicker
                headline

                // **Only the charts that have something to say.** An empty card is a title, a
                // paragraph explaining a chart, and a line admitting it isn't there — and a new
                // user met four or five of them at once, none of which were about them.
                switch section {
                case .patterns:
                    if isReady(.weekday) { weekdayCard }
                    if isReady(.timeOfDay) { timeOfDayCard }
                    if isReady(.effort) { effortCard }
                    if isReady(.goalSplit) { goalSplitCard }
                case .friction:
                    if isReady(.deferral) { deferralCard }
                    if isReady(.underestimate) { underestimateCard }
                    if isReady(.slip) { slipCard }
                    if isReady(.priority) { priorityCard }
                    if isReady(.habit) { habitCard }
                case .goals:
                    goalOutcomeTiles
                    if isReady(.burndown) { burndownCard }
                    if isReady(.estimate) { estimateCard }
                }

                stillComing
            }
            .animation(.easeInOut(duration: 0.22), value: section)
            .padding(.horizontal, 20)
            .padding(.bottom, ColorTokens.tabBarClearance)
        }
        .background(ColorTokens.surface0.ignoresSafeArea())
        .navigationBarHidden(true)
        .onChange(of: range) { _, newRange in applyRange(newRange) }
        .onAppear {
            // The default is the *narrowest* range that has data, not the widest — opening on
            // "3 months" with nine days of history is exactly the empty screen this avoids.
            guard !didPickInitialRange else { return }
            didPickInitialRange = true
            range = availableRanges.first ?? .sinceStart
            applyRange(range)
        }
    }

private var sectionPicker: some View {
        HStack(spacing: 4) {
            ForEach(Section.allCases) { option in
                let selected = section == option
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { section = option }
                } label: {
                    Text(option.label)
                        .wpTypography(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(selected ? ColorTokens.surface0 : ColorTokens.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selected ? ColorTokens.textPrimary : Color.clear)
                        .clipShape(Capsule())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(ColorTokens.surface1)
        .clipShape(Capsule())
    }

    // MARK: - Headline

    private var headline: some View {
        let elapsed = tasks.filter { Calendar.current.startOfDay(for: $0.resolvedDate) <= Calendar.current.startOfDay(for: .now) }
        let done = elapsed.filter(\.isDone).count
        let rate = elapsed.isEmpty ? 0 : Double(done) / Double(elapsed.count)
        // Distinct titles, not raw events. One task pushed six times is six rows in the log
        // but one thing you keep avoiding, and "tasks pushed off" has to mean tasks — the
        // per-task counts live on the leaderboard card below.
        let pushed = Set(allEvents.filter { $0.kindValue == .deferred }.map { $0.title ?? "" }).count
        return HStack(spacing: 10) {
            statTile(value: "\(Int(rate * 100))%", label: "Of work done")
            statTile(value: "\(done)", label: "Tasks done")
            statTile(value: "\(pushed)", label: "Tasks pushed off")
        }
    }

/// Goals finished against goals given up on.
    ///
    /// A pair of tiles rather than a card — it's two numbers, and a chart of two numbers is a
    /// chart pretending. They belong side by side because the app recorded only the second of
    /// them until recently, which made the whole picture a scoreboard of failure.
    private var goalOutcomeTiles: some View {
        let outcomes = ProgressAnalytics.goalOutcomes(allEvents)
        return HStack(spacing: 10) {
            statTile(value: "\(outcomes.finished)", label: "Goals finished")
            statTile(value: "\(outcomes.abandoned)", label: "Goals dropped")
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
        let data = ProgressAnalytics.effortByWeek(tasks, weeks: range.effortWeeks)
        let latest = data.last
        let caption: String = if let latest, latest.plannedHours > 0 {
            // A running total has to be worded as one. "You planned 20h and completed 9.6h" is a
            // verdict, and on a Tuesday it's a verdict on a week that has five days left to run.
            latest.isPartial
                ? "You've planned \(hours(latest.plannedHours)) this week and done \(hours(latest.completedHours)) of it so far. Task counts hide this — a short errand and a long block count the same."
                : "Last week you planned \(hours(latest.plannedHours)) and completed \(hours(latest.completedHours)). Task counts hide this — a short errand and a long block count the same."
        } else {
            "Hours planned against hours completed, week by week."
        }
        let emptyMessage = "Nothing scheduled in this period."
        return AnalyticsCard(title: "Hours planned vs done", caption: caption) {
            if data.allSatisfy({ $0.plannedMinutes == 0 }) {
                AnalyticsEmpty(message: emptyMessage)
            } else {
                // One bar per week, completed drawn inside planned rather than beside it.
                //
                // This was two lines over a filled area — three marks for two series, and the
                // fill was *planned* tinted with the accent while the accent line meant
                // *completed*, so the one colour on the card carried both meanings and the eye
                // bound the big tinted region to the wrong one. Lines also drew slopes between
                // week-starts, describing values that don't exist: these are four discrete
                // totals, not a continuous signal. And the quantity actually worth reading is
                // the shortfall, which a reader of two lines has to measure by eye — as the
                // unfilled top of a bar it needs no measuring at all.
                Chart(data) { week in
                    BarMark(
                        x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Planned", week.plannedHours),
                        stacking: .unstacked
                    )
                    .foregroundStyle(ColorTokens.textMuted.opacity(week.isPartial ? 0.13 : 0.24))
                    .cornerRadius(3)

                    BarMark(
                        x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Done", week.completedHours),
                        stacking: .unstacked
                    )
                    // The week in progress is drawn faint rather than hidden or filled solid:
                    // its number is real, it just isn't final, and a bar that looks settled
                    // invites a conclusion the week hasn't earned yet.
                    .foregroundStyle(week.isPartial ? accent.opacity(0.5) : accent)
                    .cornerRadius(3)
                }
                .chartXAxis {
                    // A label per point is fine at four weeks and illegible at twenty-six —
                    // twenty-six dates across three hundred points is eleven points each, and
                    // they print straight over one another. Thinned to roughly five, with the
                    // spacing chosen so the labels that survive are evenly spread rather than
                    // whichever ones happened to land first.
                    AxisMarks(values: Self.axisDates(for: data.map(\.weekStart))) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(.dateTime.day().month(.abbreviated)))
                                    .wpTypography(.micro)
                            }
                        }
                    }
                }
                .chartYAxis { AxisMarks { _ in
                    AxisGridLine().foregroundStyle(ColorTokens.border)
                    AxisValueLabel().font(WPTypography.micro.font)
                } }
                .frame(height: 160)
                ChartLegend(items: [
                    ("Planned", .swatch(ColorTokens.textMuted.opacity(0.24))),
                    ("Completed", .swatch(accent)),
                    ("This week, still running", .swatch(accent.opacity(0.5)))
                ])
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
        let balance = ProgressAnalytics.replanBalance(allEvents)
        let caption: String = if total == 0 {
            "How far you move things when you move them."
        } else if balance.pulled > 0 {
            "\(long) of \(total) moved work more than three days out. You also pulled \(balance.pulled) forward — replanning runs both ways."
        } else {
            "\(long) of \(total) moved work more than three days out. Short moves are scheduling; long ones are avoidance."
        }
        // "Replanning", not "pushing". The log records work pulled forward as well now, and a
        // card that counts only the slips turns every history into a scoreboard of failure —
        // moving something up is the same decision taken well.
        return AnalyticsCard(title: "How far you move things", caption: caption) {
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
                ChartLegend(items: [
                    ("\(balance.pushed) pushed back", .swatch(accent)),
                    ("\(balance.pulled) pulled forward", .swatch(ColorTokens.textMuted))
                ])
            }
        }
    }

    // MARK: - 4b. What you keep underestimating

    private var underestimateCard: some View {
        let data = ProgressAnalytics.underestimates(allEvents)
        let caption: String = if let worst = data.first {
            "\"\(worst.title)\" started at \(worst.originalMinutes) minutes and is now \(worst.currentMinutes). You've raised it \(worst.raises) \(worst.raises == 1 ? "time" : "times")."
        } else {
            "Work whose time budget kept going up."
        }
        return AnalyticsCard(
            title: "What you keep underestimating",
            caption: caption,
            footnote: "Only visible because the change is recorded — a task holds one duration, the current one, so the first guess is gone the moment you correct it."
        ) {
            if data.isEmpty {
                AnalyticsEmpty(message: "Nothing has had its time budget changed yet.")
            } else {
                VStack(spacing: 12) {
                    ForEach(data) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(row.title)
                                    .wpTypography(.body)
                                    .foregroundStyle(ColorTokens.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(row.originalMinutes)m → \(row.currentMinutes)m")
                                    .wpTypography(.body)
                                    .foregroundStyle(ColorTokens.textSecondary)
                                    .monospacedDigit()
                            }
                            // The original estimate stays visible under the current one rather
                            // than being replaced by it — the gap between the two *is* the point.
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(ColorTokens.border)
                                    Capsule()
                                        .fill(ColorTokens.warning.opacity(0.85))
                                        .frame(width: geo.size.width)
                                    Capsule()
                                        .fill(accent)
                                        .frame(width: geo.size.width / max(row.growth, 1))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
                ChartLegend(items: [
                    ("First guess", .swatch(accent)),
                    ("Where it ended up", .swatch(ColorTokens.warning.opacity(0.85)))
                ])
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
        return AnalyticsCard(
            title: "When you get things done",
            caption: caption,
            footnote: "Only counts tasks you ticked off yourself. Ones completed automatically record the time they were scheduled to end, not when you actually stopped."
        ) {
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
                ChartLegend(items: [("Fewer finished", .fade(accent)), ("More", .swatch(accent))])
            }
        }
    }

    private func intensity(_ count: Int, in cells: [ProgressAnalytics.HeatCell]) -> Double {
        let peak = cells.map(\.count).max() ?? 1
        guard peak > 0 else { return 0.06 }
        return 0.18 + 0.82 * (Double(count) / Double(peak))
    }

    // MARK: - 9. Estimate accuracy

    private var estimateCard: some View {
        // The median comes off *everything* measured, the chart off the six worst. Taking both
        // from the top six made the headline describe only the disasters — "work takes 60%
        // longer than you book" when the typical task was within a few minutes.
        let all = ProgressAnalytics.estimateAccuracy(sessions: Array(sessions), tasks: tasks, limit: .max)
        let data = Array(all.prefix(6))
        let median = ProgressAnalytics.medianEstimateRatio(all)
        let caption: String = if let median, median > 1.1 {
            "Work typically takes \(Int((median - 1) * 100))% longer than you book for it. Adding that to new estimates is the fastest way to make a plan hold."
        } else if let median, median < 0.9 {
            "You typically finish in \(Int((1 - median) * 100))% less time than you book. There's room to plan more into a day."
        } else if median != nil {
            "Your estimates are close to what work actually takes."
        } else {
            "How long work really takes, against how long you booked for it."
        }
        return AnalyticsCard(
            title: "How good are your estimates?",
            caption: caption,
            footnote: "Measured from focus timer sessions. Repeats of the same task are averaged, so both figures are per sitting. Paused time doesn't count."
        ) {
            if data.isEmpty {
                AnalyticsEmpty(message: "Run the focus timer on a task to start measuring this.")
            } else {
                Chart(data) { row in
                    BarMark(
                        x: .value("Minutes", row.plannedMinutes),
                        y: .value("Task", row.title),
                        stacking: .unstacked
                    )
                    .foregroundStyle(ColorTokens.textMuted.opacity(0.45))
                    .cornerRadius(4)
                    BarMark(
                        x: .value("Minutes", row.actualMinutes),
                        y: .value("Task", row.title),
                        stacking: .unstacked
                    )
                    .foregroundStyle(row.ratio > 1 ? ColorTokens.warning : accent)
                    .cornerRadius(4)
                }
                .chartXAxis { AxisMarks { _ in
                    AxisGridLine().foregroundStyle(ColorTokens.border)
                    AxisValueLabel().font(WPTypography.micro.font)
                } }
                .chartYAxis { AxisMarks { _ in AxisValueLabel().font(WPTypography.micro.font) } }
                .frame(height: CGFloat(data.count) * 34 + 24)
                ChartLegend(items: [
                    ("Booked", .swatch(ColorTokens.textMuted.opacity(0.45))),
                    ("Actually took", .swatch(accent)),
                    ("Overran", .swatch(ColorTokens.warning))
                ])
            }
        }
    }

    // MARK: - 10. Burn-down

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
        return AnalyticsCard(
            title: "Will you make the deadline?",
            caption: caption,
            footnote: "The dotted line is where you'd be finishing an equal share of the work every day between starting and the target date."
        ) {
            if points.isEmpty {
                AnalyticsEmpty(message: "Create a goal with a target date to see its pace.")
            } else {
                GoalBurndownChart(points: points, accent: accent)
            }
        }
    }

    // MARK: - Bits

    /// At most five labels, evenly spaced, and always including the most recent — the right
    /// edge is where the eye lands and an axis that stops short of it reads as truncated.
    private static func axisDates(for dates: [Date]) -> [Date] {
        guard dates.count > 5 else { return dates }
        let stride = Int(ceil(Double(dates.count) / 5))
        // Taken from the end so the newest week always gets a label, then put back in order.
        return dates.reversed().enumerated()
            .filter { $0.offset.isMultiple(of: stride) }
            .map(\.element)
            .reversed()
    }

    private func hours(_ value: Double) -> String {
        value >= 10 ? "\(Int(value.rounded()))h" : String(format: "%.1fh", value)
    }

}

/// Shared with `GoalDetailView`, which draws the same chart for one specific goal.
struct GoalBurndownChart: View {
    let points: [ProgressAnalytics.BurndownPoint]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

        ChartLegend(items: [
            ("Tasks left", .line(accent)),
            ("Pace needed", .dashed(ColorTokens.textMuted))
        ])
        }
    }
}
