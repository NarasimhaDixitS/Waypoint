import SwiftUI
import CoreData
import UIKit

/// Week, rebuilt around two navigable units instead of one flat week-at-a-time list:
/// **By week** browses months (prev/next), showing that month's weeks as collapsed cards —
/// one open at a time, so a month with several weeks of history doesn't dump everything on
/// screen at once. **By goal** browses goals the same way, showing that goal's weeks. Whichever
/// week actually contains today auto-opens when it's present in the browsed scope; otherwise
/// the earliest week does — so landing on the current month/a goal with activity this week
/// costs zero taps, and browsing away just shows quiet collapsed rows until you tap one open.
struct WeekView: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    /// First-of-month anchor for "By week" mode — the parent owns and animates this so the
    /// browsed month persists across tab switches, same pattern as Today's `selectedDate`.
    let browsedMonth: Date
    var onSelectDay: (Date) -> Void = { _ in }
    var onNavigateMonth: (Date) -> Void = { _ in }

    enum Mode { case byWeek, byGoal }

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \GoalEntity.createdAt, ascending: true)])
    private var allGoals: FetchedResults<GoalEntity>

    /// Covers the full display grid (the browsed month plus whatever adjacent-month days its
    /// first/last week rows spill into), not just the calendar month itself.
    @FetchRequest private var gridTasks: FetchedResults<TaskEntity>

    @State private var mode: Mode = .byWeek
    @State private var expandedWeekInMonth: Date?
    @State private var expandedWeekInGoal: Date?
    @State private var browsedGoalID: NSManagedObjectID?
    @State private var didInitGoalDefaults = false

    /// Which days inside an expanded week are open. `nil` means "nothing has been touched yet",
    /// which resolves to today alone — expressed as absence rather than as a seeded set so the
    /// default is recomputed from the clock, and a session left open across midnight rolls onto
    /// the new day instead of holding yesterday open forever.
    @State private var expandedDays: Set<Date>?

    /// Which way the next month/goal change should travel; set by whichever control caused it.
    @State private var navEdge: Edge = .trailing

    /// Week derives task state from the clock the same way Today does, so it needs the same
    /// invalidation: without it a task would keep its 9am state all afternoon and the running
    /// row would appear late and linger. The wave itself is self-driving (`TimelineView`), so
    /// what this actually fixes is *which* row is chosen as running, not the fill inside it.
    private let clockTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()
    @State private var clockTick = Date.now

    init(
        browsedMonth: Date,
        onSelectDay: @escaping (Date) -> Void = { _ in },
        onNavigateMonth: @escaping (Date) -> Void = { _ in }
    ) {
        self.browsedMonth = browsedMonth
        self.onSelectDay = onSelectDay
        self.onNavigateMonth = onNavigateMonth
        let span = Self.gridSpan(for: browsedMonth)
        _gridTasks = FetchRequest(fetchRequest: TaskEntity.fetchRequest(from: span.start, to: span.end))

        let weeks = Self.weeksOverlapping(month: browsedMonth)
        _expandedWeekInMonth = State(initialValue: Self.defaultExpandedWeek(among: weeks))
    }

    // MARK: - Date helpers

    /// The full display grid: the browsed month plus whatever adjacent-month days its first and
    /// last week rows spill into.
    static func gridSpan(for month: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let interval = cal.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 0)
        let start = mondayOfWeek(containing: interval.start)
        let end = cal.date(byAdding: .day, value: 7, to: mondayOfWeek(containing: interval.end)) ?? interval.end
        return (start, end)
    }

    static func mondayOfWeek(containing date: Date) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: today) // 1 = Sun
        let mondayOffset = (weekday + 5) % 7
        return cal.date(byAdding: .day, value: -mondayOffset, to: today)!
    }

    static func firstOfMonth(containing date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }

    static func weeksOverlapping(month: Date) -> [Date] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        var mondays: [Date] = []
        var cursor = mondayOfWeek(containing: interval.start)
        while cursor < interval.end {
            mondays.append(cursor)
            cursor = cal.date(byAdding: .day, value: 7, to: cursor) ?? interval.end
        }
        return mondays
    }

    /// The week containing today if it's actually in this scope, else the earliest one —
    /// covers both "land on the current month" and "browse to a different month/goal" with one
    /// rule instead of two.
    static func defaultExpandedWeek(among weeks: [Date]) -> Date? {
        let todayMonday = mondayOfWeek(containing: .now)
        return weeks.contains(todayMonday) ? todayMonday : weeks.first
    }

    private static let weekdayAbbrev = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private static func weekdayIndex(for date: Date) -> Int {
        (Calendar.current.component(.weekday, from: date) + 5) % 7
    }

    /// Hardcoded rather than `NumberFormatter(.ordinal)`: the simulator and a good share of
    /// users run a non-US English locale, and the formatter's ordinals follow the locale rather
    /// than the app's own English copy. The 11th–13th exception is the one everybody gets wrong.
    private static func ordinalDay(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        let suffix: String
        if (11...13).contains(day % 100) {
            suffix = "th"
        } else {
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }

    // MARK: - Derived data

    private var weeksInMonth: [Date] { Self.weeksOverlapping(month: browsedMonth) }

    /// Pins the current week to the front of whatever list is being displayed — so it's always
    /// the first thing you see, already open, with zero scrolling — rather than sitting wherever
    /// it naturally falls in chronological order (which, deep into a month, could be several
    /// cards down). Every other week follows below in its normal order. Falls back to plain
    /// chronological order untouched when the current week isn't in this scope at all (browsing
    /// a different month, or a goal with no activity this week).
    private func orderedForDisplay(_ weeks: [Date]) -> [Date] {
        let todayMonday = Self.mondayOfWeek(containing: .now)
        guard let idx = weeks.firstIndex(of: todayMonday), idx != 0 else { return weeks }
        var result = weeks
        let current = result.remove(at: idx)
        result.insert(current, at: 0)
        return result
    }

    private var sortedGoals: [GoalEntity] { Array(allGoals) }

    private var currentGoal: GoalEntity? {
        if let browsedGoalID, let match = sortedGoals.first(where: { $0.objectID == browsedGoalID }) {
            return match
        }
        return sortedGoals.first
    }

    private var currentGoalIndex: Int {
        guard let currentGoal else { return 0 }
        return sortedGoals.firstIndex(of: currentGoal) ?? 0
    }

    private func weeks(for goal: GoalEntity) -> [Date] {
        Set(goal.sortedTasks.map { Self.mondayOfWeek(containing: $0.resolvedDate) }).sorted()
    }

    private func tasks(forWeekStarting monday: Date, in pool: [TaskEntity]) -> [TaskEntity] {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 7, to: monday) ?? monday
        return pool.filter { $0.resolvedDate >= monday && $0.resolvedDate < end }
    }

    /// All seven days, including the empty ones. Skipping blank days would be more compact, but
    /// a week where nothing was scheduled on Wednesday is telling you something, and a list that
    /// silently omits it reads as a week with no gaps. The empty row also keeps the seven-row
    /// shape identical from week to week, so the eye can compare two cards by position.
    private func allDays(inWeekStarting monday: Date, tasks: [TaskEntity]) -> [(day: Date, tasks: [TaskEntity])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: tasks) { cal.startOfDay(for: $0.resolvedDate) }
        return (0..<7).compactMap { offset in
            guard let raw = cal.date(byAdding: .day, value: offset, to: monday) else { return nil }
            let day = cal.startOfDay(for: raw)
            return (day, (grouped[day] ?? []).sorted { $0.resolvedStartTime < $1.resolvedStartTime })
        }
    }

    /// Today is open, everything else is shut, until the reader says otherwise.
    private var effectiveExpandedDays: Set<Date> {
        expandedDays ?? [Calendar.current.startOfDay(for: clockTick)]
    }

    /// Days are a disclosure, not a navigation mode, so several can stand open at once —
    /// unlike weeks, which are one-at-a-time because they're large. Forcing Tuesday shut to
    /// read Thursday would turn comparing them into a memory test.
    private func toggleDay(_ day: Date) {
        var set = effectiveExpandedDays
        if set.contains(day) { set.remove(day) } else { set.insert(day) }
        expandedDays = set
    }

    private var monthSummary: (done: Int, total: Int) {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: browsedMonth) else { return (0, 0) }
        let inMonth = gridTasks.filter { $0.resolvedDate >= interval.start && $0.resolvedDate < interval.end }
        return (inMonth.filter(\.isDone).count, inMonth.count)
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { page in
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Week")
                    .wpTypography(.appTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .padding(.top, 8)

                banner
                    .onChange(of: expandedWeek) { _, newValue in
                        // Tapping a week in the strip has to bring its card into view, or the
                        // strip silently opens something below the fold and looks inert.
                        guard let newValue else { return }
                        withAnimation(.easeInOut(duration: 0.3)) { page.scrollTo(newValue, anchor: .top) }
                    }
                cardsList
                    .id(bannerIdentity)
                    .transition(slide)
            }
            // On the stack rather than on the sliding views themselves: `.animation(value:)`
            // resets along with the identity it is watching, so attached to the same view as
            // `.id` it would never see a change. The month lives in `MainTabView`, which does
            // wrap its own mutation, but relying on a caller's transaction is what made this
            // silently do nothing — here the animation is owned by the view that transitions.
            .animation(.easeInOut(duration: 0.32), value: bannerIdentity)
            .padding(.horizontal, 20)
            // Big enough that even the LAST week card, fully expanded, can still scroll clear
            // of the floating tab bar — a plain 24pt was only ever enough when nothing below
            // the fold needed room, which breaks the moment the bottom card is the one that's
            // open.
            .padding(.bottom, 140)
        }
        }
        .background(ColorTokens.surface0.ignoresSafeArea())
        .navigationBarHidden(true)
        .onChange(of: browsedMonth) { _, newMonth in
            // What the `.id` in MainTabView used to buy by force. A `@FetchRequest` is built in
            // `init` and won't follow a changed parameter on its own, so retargeting it here is
            // what lets the view survive a month step rather than being replaced by a new one.
            let span = Self.gridSpan(for: newMonth)
            gridTasks.nsPredicate = NSPredicate(
                format: "date >= %@ AND date < %@", span.start as NSDate, span.end as NSDate
            )
            expandedWeekInMonth = Self.defaultExpandedWeek(among: Self.weeksOverlapping(month: newMonth))
        }
        .onReceive(clockTimer) { tick in
            withAnimation(.easeInOut(duration: 0.3)) { clockTick = tick }
        }
        .onAppear {
            guard !didInitGoalDefaults, !sortedGoals.isEmpty else { return }
            didInitGoalDefaults = true
            let goal = sortedGoals.first { candidate in
                weeks(for: candidate).contains(Self.mondayOfWeek(containing: .now))
            } ?? sortedGoals[0]
            browsedGoalID = goal.objectID
            expandedWeekInGoal = Self.defaultExpandedWeek(among: weeks(for: goal))
        }
    }

    // MARK: - Banner

    /// Three attempts at a tab in this banner failed, and the reference that settled it has no
    /// tabs at all: a nav row, a strip of selectable units under it, and one full-width control
    /// at the foot. The strip is the piece that was missing — it turns the banner from a label
    /// into an instrument, since the weeks it lists are the same weeks stacked below it.
    private var banner: some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                navArrow(systemName: "chevron.left", disabled: mode == .byGoal && currentGoalIndex == 0) {
                    mode == .byWeek ? stepMonth(-1) : stepGoal(-1)
                }
                Group {
                    if mode == .byWeek {
                        monthBannerCenter
                    } else {
                        goalBannerCenter
                    }
                }
                .frame(maxWidth: .infinity)
                .id(bannerIdentity)
                .transition(slide)
                navArrow(systemName: "chevron.right", disabled: mode == .byGoal && currentGoalIndex >= sortedGoals.count - 1) {
                    mode == .byWeek ? stepMonth(1) : stepGoal(1)
                }
            }
            .clipped()

            modeToggle
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(bannerFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: ColorTokens.ShadowTier.raised.color, radius: ColorTokens.ShadowTier.raised.radius, x: 0, y: ColorTokens.ShadowTier.raised.y)
    }

    private var bannerFill: Color {
        ColorTokens.elevatedFill(theme.accentSwatch.color, tier: .raised, isDark: colorScheme == .dark)
    }

    /// One full-width control at the foot, where the reference puts its primary button.
    private var modeToggle: some View {
        HStack(spacing: 4) {
            modeButton("By week", .byWeek)
            modeButton("By goal", .byGoal)
        }
        .padding(4)
        .background(Color.white.opacity(0.16))
        .clipShape(Capsule())
    }

    private func modeButton(_ label: String, _ target: Mode) -> some View {
        let selected = mode == target
        return Button {
            navEdge = .trailing
            withAnimation(.easeInOut(duration: 0.28)) { mode = target }
        } label: {
            Text(label)
                .wpTypography(.body)
                .fontWeight(.semibold)
                // Not `textPrimary`: the pill is white in both schemes, but that token inverts
                // with the scheme, so in dark mode it turned warm off-white on white.
                .foregroundStyle(selected ? ColorTokens.inkOnLight : .white.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selected ? Color.white : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Whichever week is open in the mode currently being browsed.
    private var expandedWeek: Date? {
        mode == .byWeek ? expandedWeekInMonth : expandedWeekInGoal
    }

    private func select(week monday: Date) {
        withAnimation(.easeInOut(duration: 0.25)) {
            if mode == .byWeek {
                expandedWeekInMonth = monday
            } else {
                expandedWeekInGoal = monday
            }
        }
    }

    /// What a sideways step actually changes — the browsed month, or the browsed goal.
    private var bannerIdentity: AnyHashable {
        mode == .byWeek ? AnyHashable(browsedMonth) : AnyHashable(currentGoal?.objectID)
    }

    /// Direction comes from the button that was pressed, so stepping forward moves content
    /// leftward and stepping back reverses it — a slide that always went one way would say
    /// "something changed" without saying which way you went.
    private var slide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: navEdge).combined(with: .opacity),
            removal: .move(edge: navEdge == .trailing ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var monthBannerCenter: some View {
        let summary = monthSummary
        return VStack(spacing: 2) {
            Text(browsedMonth.formatted(.dateTime.month(.wide)))
                .wpTypography(.screenTitle)
                .foregroundStyle(.white)
            Text("\(browsedMonth.formatted(.dateTime.year())) · \(summary.done) of \(summary.total) tasks done")
                .wpTypography(.body)
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private var goalBannerCenter: some View {
        Group {
            if let goal = currentGoal {
                VStack(spacing: 2) {
                    Text(goal.name ?? "Goal")
                        .wpTypography(.screenTitle)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Day \(goal.currentDayNumber) of \(goal.totalDayCount) · \(goal.doneTaskCount) of \(goal.sortedTasks.count) tasks done")
                        .wpTypography(.body)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            } else {
                Text("No goals yet")
                    .wpTypography(.body)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    /// Bare chevrons on a 44pt target rather than filled discs. The discs were two more solid
    /// shapes competing with the month name they flanked, and inside the panel they now sit on
    /// they'd be a third shade of the same accent — the tap area does the work a disc was doing.
    private func navArrow(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }

    // MARK: - Navigation actions

    private func stepMonth(_ delta: Int) {
        guard let newMonth = Calendar.current.date(byAdding: .month, value: delta, to: browsedMonth) else { return }
        navEdge = delta > 0 ? .trailing : .leading
        onNavigateMonth(newMonth)
    }

    private func stepGoal(_ delta: Int) {
        guard !sortedGoals.isEmpty else { return }
        let newIndex = min(max(currentGoalIndex + delta, 0), sortedGoals.count - 1)
        let goal = sortedGoals[newIndex]
        navEdge = delta > 0 ? .trailing : .leading
        // Month-stepping was already animated (wrapped one level up, in MainTabView); this was
        // the one navigation control here that wasn't, snapping instead of transitioning.
        withAnimation(.easeInOut(duration: 0.3)) {
            browsedGoalID = goal.objectID
            expandedWeekInGoal = Self.defaultExpandedWeek(among: weeks(for: goal))
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private var cardsList: some View {
        switch mode {
        case .byWeek:
            VStack(spacing: 12) {
                if weeksInMonth.isEmpty {
                    Text("No weeks to show")
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textSecondary)
                }
                ForEach(orderedForDisplay(weeksInMonth), id: \.self) { monday in
                    weekCard(
                        monday: monday,
                        number: (weeksInMonth.firstIndex(of: monday) ?? 0) + 1,
                        tasks: tasks(forWeekStarting: monday, in: Array(gridTasks)),
                        isExpanded: expandedWeekInMonth == monday
                    ) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            expandedWeekInMonth = (expandedWeekInMonth == monday) ? nil : monday
                        }
                    }
                }
            }
        case .byGoal:
            VStack(spacing: 12) {
                if let goal = currentGoal {
                    let weeks = weeks(for: goal)
                    if weeks.isEmpty {
                        Text("No tasks for this goal yet")
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textSecondary)
                    }
                    ForEach(orderedForDisplay(weeks), id: \.self) { monday in
                        weekCard(
                            monday: monday,
                            number: (weeks.firstIndex(of: monday) ?? 0) + 1,
                            tasks: tasks(forWeekStarting: monday, in: goal.sortedTasks),
                            isExpanded: expandedWeekInGoal == monday
                        ) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                expandedWeekInGoal = (expandedWeekInGoal == monday) ? nil : monday
                            }
                        }
                    }
                } else {
                    Text("Create a goal to see it here")
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textSecondary)
                }
            }
        }
    }

    /// Every card carries the same summary in the same shape — date range, done count, and a
    /// progress bar of identical size — so a month can be compared in one glance instead of one
    /// tap per week. The expanded card used to jump type sizes and ring sizes as well, which
    /// made the current week unmistakable but meant no two cards could be read against each
    /// other. Expansion and the accent edge carry "this is the one you're in" on their own.
    ///
    /// A bar, not a ring: a ring is for a single focal value. A stack of weeks is a comparison,
    /// and bars line up so two lengths can be compared at sight — arcs don't.
    private func weekCard(
        monday: Date,
        number: Int,
        tasks: [TaskEntity],
        isExpanded: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        let done = tasks.filter(\.isDone).count
        let total = tasks.count
        let currentMonday = Self.mondayOfWeek(containing: clockTick)
        let isCurrentWeek = monday == currentMonday
        let isNextWeek = monday == Calendar.current.date(byAdding: .day, value: 7, to: currentMonday)

        return VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        // Neutral ink, deliberately. Accent-on-white measured 3.59–3.93:1 for
                        // three of the four swatches — below the 4.5:1 a 14.5pt label needs —
                        // and the 80%-opacity subtext was worse still, bottoming out at 2.73:1.
                        // The accent identifies the current week through the edge and the bar,
                        // which are shapes rather than text and answer to a 3:1 bar instead.
                        // "Week 3" rather than "31 Aug–6": a date range is an answer to a
                        // question nobody asked of a week card, and the dates come back for
                        // free the moment it opens, since every day row carries its own.
                        Text("Week \(number)")
                            .wpTypography(.cardTitle)
                            .foregroundStyle(ColorTokens.textPrimary)
                        if isCurrentWeek || isNextWeek {
                            // At `.body` this was a full-stop nobody noticed. A separator has to
                            // be seen to separate — sized to the label it sits between and given
                            // the same ink as the text on either side of it.
                            Text("·")
                                .wpTypography(.cardTitle)
                                .foregroundStyle(ColorTokens.textSecondary)
                            Text(isCurrentWeek ? "CURRENT WEEK" : "NEXT WEEK")
                                .wpTypography(.micro)
                                .fontWeight(.semibold)
                                .tracking(0.6)
                                .foregroundStyle(ColorTokens.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Text(total == 0 ? "—" : "\(done) of \(total)")
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textSecondary)
                            .monospacedDigit()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ColorTokens.textMuted)
                            .rotationEffect(.degrees(isExpanded ? -180 : 0))
                    }
                    weekProgressBar(fraction: total == 0 ? 0 : Double(done) / Double(total))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    dayDivider
                    let days = allDays(inWeekStarting: monday, tasks: tasks)
                    ForEach(Array(days.enumerated()), id: \.element.day) { index, group in
                        if index > 0 { dayDivider }
                        dayGroup(group)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        // Exactly what `wpCard(shadow: .resting)` does — fill, radius, shadow — spelled out by
        // hand only because the header and the expanded body carry their own padding, so the
        // modifier's single padding value doesn't fit. `elevatedFill` is a no-op at this tier
        // and is here so the call stays correct if the tier ever rises, not because it lightens
        // anything today.
        .background(ColorTokens.elevatedFill(ColorTokens.surface1, tier: .resting, isDark: colorScheme == .dark))
        .overlay(alignment: .leading) {
            // Flush and full-height rather than an inset floating pill: clipped by the card's
            // own corner radius below, it reads as the card's edge instead of a sticker stuck
            // onto it.
            if isCurrentWeek {
                theme.accentSwatch.markColor.frame(width: 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: ColorTokens.ShadowTier.resting.color, radius: ColorTokens.ShadowTier.resting.radius, x: 0, y: ColorTokens.ShadowTier.resting.y)
        .id(monday)
    }

    /// Inset and faded at both ends rather than a full-bleed rule. A hairline that runs wall to
    /// wall cuts the card into slices — it reads as a table border, and seven of them turn a
    /// list into a grid. Fading it out before the edges lets it separate without enclosing.
    private var dayDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: ColorTokens.border, location: 0.22),
                        .init(color: ColorTokens.border, location: 0.78),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.vertical, 3)
    }

    private func weekProgressBar(fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(ColorTokens.border)
                if fraction > 0 {
                    Capsule()
                        .fill(theme.accentSwatch.markColor)
                        // Floored at the bar's own height so a single task out of thirty still
                        // shows as a dot rather than vanishing into a sliver.
                        .frame(width: max(geo.size.width * fraction, 5))
                }
            }
        }
        .frame(height: 5)
        .animation(.easeInOut(duration: 0.35), value: fraction)
    }

    /// A disclosure list, not an agenda. The previous pass put the day in a fixed left gutter
    /// with its tasks flowing beside it, which grouped correctly but showed every task in the
    /// week at once — thirty-odd rows the moment a card opened, with nothing to rest the eye on.
    /// Now each day is a single line that opens on demand, so an expanded week is seven rows
    /// until you ask for more, and the day headers do the separating that hairlines were being
    /// considered for.
    private func dayGroup(_ group: (day: Date, tasks: [TaskEntity])) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(group.day)
        let isExpanded = effectiveExpandedDays.contains(group.day)
        let done = group.tasks.filter(\.isDone).count
        // A Friday that hasn't happened yet reading "0 of 3" looks exactly like failure, when
        // in fact nothing has gone wrong. Completion is only meaningful once a day has arrived.
        let isFuture = cal.startOfDay(for: group.day) > cal.startOfDay(for: clockTick)
        let summary: String = if group.tasks.isEmpty {
            "Nothing scheduled"
        } else if isFuture {
            group.tasks.count == 1 ? "1 task" : "\(group.tasks.count) tasks"
        } else {
            "\(done) of \(group.tasks.count)"
        }
        let hasRunning = group.tasks.contains { $0.state(at: clockTick) == .inProgress }
        let hasOverdue = group.tasks.contains { $0.state(at: clockTick) == .overdue }

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { toggleDay(group.day) }
            } label: {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Text(Self.weekdayAbbrev[Self.weekdayIndex(for: group.day)])
                            .wpTypography(.micro)
                        Text(Self.ordinalDay(group.day))
                            .wpTypography(.cardTitle)
                    }
                    // A fixed cell so all seven day labels start and end together — "1st" and
                    // "31st" alike — rather than the separator beside them shifting by a
                    // character's width from one row to the next.
                    .frame(width: 68, alignment: .leading)
                    .foregroundStyle(isToday ? ColorTokens.textPrimary : ColorTokens.textSecondary)

                    Text("·")
                        .wpTypography(.cardTitle)
                        .foregroundStyle(ColorTokens.textMuted)

                    Text(summary)
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textMuted)
                        .monospacedDigit()

                    Spacer(minLength: 6)

                    // Only what a closed row would otherwise hide. A day you can't see into
                    // still has to be able to say "something is running" and "something is
                    // late" — the two states worth opening it for.
                    if hasRunning {
                        Circle().fill(theme.accentSwatch.inProgressColor).frame(width: 6, height: 6)
                    }
                    if hasOverdue {
                        Circle().fill(ColorTokens.warning).frame(width: 6, height: 6)
                    }
                    if !group.tasks.isEmpty {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ColorTokens.textMuted)
                            .rotationEffect(.degrees(isExpanded ? -180 : 0))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(group.tasks.isEmpty)
            .accessibilityLabel("\(group.day.formatted(.dateTime.weekday(.wide).month().day())), \(group.tasks.count) tasks")

            if isExpanded, !group.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(group.tasks, id: \.objectID) { task in
                        if task.state(at: clockTick) == .inProgress {
                            inProgressRow(task)
                        } else {
                            compactTaskRow(task)
                        }
                    }
                }
                // Stepped in from its own header, so a day's work is visibly subordinate to the
                // day rather than merely adjacent to it.
                .padding(.leading, 18)
                .padding(.bottom, 4)
            }
        }
    }

    private func compactTaskRow(_ task: TaskEntity) -> some View {
        Button {
            onSelectDay(task.resolvedDate)
        } label: {
            HStack(spacing: 10) {
                // Start time only. The full range was the single biggest source of text on this
                // screen, and a week overview is asking "what's on" — durations are a question
                // you go to the day itself for.
                Text(task.resolvedStartTime.formatted(.dateTime.hour().minute()))
                    .wpTypography(.micro)
                    .monospacedDigit()
                    .foregroundStyle(ColorTokens.textMuted)
                    .frame(width: 52, alignment: .leading)
                Text(task.title ?? "")
                    .wpTypography(.body)
                    .foregroundStyle(task.isDone ? ColorTokens.textSecondary : ColorTokens.textPrimary)
                    .strikethrough(task.isDone)
                    .lineLimit(1)
                Spacer(minLength: 4)
                stateDot(for: task)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The running task, borrowed from Today but deliberately not a copy of it. Today's card
    /// carries in-progress three ways at once — wave, aura, raised shadow — which is right for
    /// the focal element of its own screen. Dropped inside an already-elevated week card that
    /// becomes a card within a card, two shadow layers deep, so only the wave survives here.
    /// It's the part that actually says something: the waterline is where the hour has got to.
    private func inProgressRow(_ task: TaskEntity) -> some View {
        Button {
            onSelectDay(task.resolvedDate)
        } label: {
            HStack(spacing: 10) {
                Text(task.resolvedStartTime.formatted(.dateTime.hour().minute()))
                    .wpTypography(.micro)
                    .monospacedDigit()
                    .foregroundStyle(ColorTokens.textSecondary)
                    .frame(width: 52, alignment: .leading)
                Text(task.title ?? "")
                    .wpTypography(.cardTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("NOW")
                    .wpTypography(.micro)
                    .fontWeight(.semibold)
                    .tracking(0.6)
                    .foregroundStyle(ColorTokens.textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .background {
                TaskProgressWave(
                    start: task.resolvedStartTime,
                    end: task.endTime,
                    tint: theme.accentSwatch.inProgressTintColor,
                    line: theme.accentSwatch.inProgressColor
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Marks only what isn't already visible — the same rule the badges on Today follow. A done
    /// task is struck through and greyed, so a dot beside it says nothing a fourth time; a
    /// pending one needs no mark at all. In-progress is gone from here too, now that it gets a
    /// row of its own, which leaves overdue as the one state a dot has to carry.
    @ViewBuilder
    private func stateDot(for task: TaskEntity) -> some View {
        switch task.state(at: clockTick) {
        case .overdue:
            Circle().fill(ColorTokens.warning).frame(width: 6, height: 6)
        case .done, .pending, .future, .inProgress:
            EmptyView()
        }
    }
}
