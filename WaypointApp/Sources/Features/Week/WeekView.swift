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

    init(
        browsedMonth: Date,
        onSelectDay: @escaping (Date) -> Void = { _ in },
        onNavigateMonth: @escaping (Date) -> Void = { _ in }
    ) {
        self.browsedMonth = browsedMonth
        self.onSelectDay = onSelectDay
        self.onNavigateMonth = onNavigateMonth
        let cal = Calendar.current
        let monthInterval = cal.dateInterval(of: .month, for: browsedMonth) ?? DateInterval(start: browsedMonth, duration: 0)
        let gridStart = Self.mondayOfWeek(containing: monthInterval.start)
        let gridEnd = cal.date(byAdding: .day, value: 7, to: Self.mondayOfWeek(containing: monthInterval.end)) ?? monthInterval.end
        _gridTasks = FetchRequest(fetchRequest: TaskEntity.fetchRequest(from: gridStart, to: gridEnd))

        let weeks = Self.weeksOverlapping(month: browsedMonth)
        _expandedWeekInMonth = State(initialValue: Self.defaultExpandedWeek(among: weeks))
    }

    // MARK: - Date helpers

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

    private func daysWithTasks(in tasks: [TaskEntity]) -> [(day: Date, tasks: [TaskEntity])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: tasks) { cal.startOfDay(for: $0.resolvedDate) }
        return grouped.keys.sorted().map { day in
            (day, (grouped[day] ?? []).sorted { $0.resolvedStartTime < $1.resolvedStartTime })
        }
    }

    private var monthSummary: (done: Int, total: Int) {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: browsedMonth) else { return (0, 0) }
        let inMonth = gridTasks.filter { $0.resolvedDate >= interval.start && $0.resolvedDate < interval.end }
        return (inMonth.filter(\.isDone).count, inMonth.count)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Week")
                    .wpTypography(.screenTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .padding(.top, 8)

                banner
                cardsList
            }
            .padding(.horizontal, 20)
            // Big enough that even the LAST week card, fully expanded, can still scroll clear
            // of the floating tab bar — a plain 24pt was only ever enough when nothing below
            // the fold needed room, which breaks the moment the bottom card is the one that's
            // open.
            .padding(.bottom, 140)
        }
        .background(ColorTokens.surface0.ignoresSafeArea())
        .navigationBarHidden(true)
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

    private var banner: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
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
                navArrow(systemName: "chevron.right", disabled: mode == .byGoal && currentGoalIndex >= sortedGoals.count - 1) {
                    mode == .byWeek ? stepMonth(1) : stepGoal(1)
                }
            }
            modeToggle
        }
        .padding(20)
        .background(theme.accentSwatch.color)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var monthBannerCenter: some View {
        let summary = monthSummary
        return VStack(spacing: 2) {
            Text(browsedMonth.formatted(.dateTime.month(.wide)))
                .font(.system(size: 22, weight: .semibold))
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
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
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

    private func navArrow(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.18))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    private var modeToggle: some View {
        HStack(spacing: 6) {
            modeButton("By week", .byWeek)
            modeButton("By goal", .byGoal)
        }
        .padding(4)
        .background(Color.white.opacity(0.18))
        .clipShape(Capsule())
    }

    private func modeButton(_ label: String, _ target: Mode) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                mode = target
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(mode == target ? ColorTokens.textPrimary : .white.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(mode == target ? Color.white : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation actions

    private func stepMonth(_ delta: Int) {
        guard let newMonth = Calendar.current.date(byAdding: .month, value: delta, to: browsedMonth) else { return }
        onNavigateMonth(newMonth)
    }

    private func stepGoal(_ delta: Int) {
        guard !sortedGoals.isEmpty else { return }
        let newIndex = min(max(currentGoalIndex + delta, 0), sortedGoals.count - 1)
        let goal = sortedGoals[newIndex]
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
        tasks: [TaskEntity],
        isExpanded: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        let sunday = Calendar.current.date(byAdding: .day, value: 6, to: monday) ?? monday
        let done = tasks.filter(\.isDone).count
        let total = tasks.count
        let rangeLabel = "\(monday.formatted(.dateTime.month(.abbreviated).day()))–\(sunday.formatted(.dateTime.day()))"
        let isCurrentWeek = monday == Self.mondayOfWeek(containing: .now)

        return VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        // Neutral ink, deliberately. Accent-on-white measured 3.59–3.93:1 for
                        // three of the four swatches — below the 4.5:1 a 14.5pt label needs —
                        // and the 80%-opacity subtext was worse still, bottoming out at 2.73:1.
                        // The accent identifies the current week through the edge and the bar,
                        // which are shapes rather than text and answer to a 3:1 bar instead.
                        Text(rangeLabel)
                            .wpTypography(.cardTitle)
                            .foregroundStyle(ColorTokens.textPrimary)
                        if isCurrentWeek {
                            Text("CURRENT WEEK")
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
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ColorTokens.textMuted)
                    }
                    weekProgressBar(fraction: total == 0 ? 0 : Double(done) / Double(total))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Divider().background(ColorTokens.border)
                    if tasks.isEmpty {
                        Text("Nothing scheduled")
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textMuted)
                    }
                    ForEach(daysWithTasks(in: tasks), id: \.day) { group in
                        dayGroup(group)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(ColorTokens.surface1)
        .overlay(alignment: .leading) {
            // Flush and full-height rather than an inset floating pill: clipped by the card's
            // own corner radius below, it reads as the card's edge instead of a sticker stuck
            // onto it.
            if isCurrentWeek {
                theme.accentSwatch.markColor.frame(width: 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .id(monday)
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

    /// An agenda, not a stack of sub-lists. The day used to sit in its own header row with a
    /// hairline rule and a "3 tasks" count above every group, which cost three lines of chrome
    /// per day to say something the rows beneath already showed. Here the day lives in a fixed
    /// left gutter and the tasks flow beside it, so alignment does the grouping — no rules, no
    /// counts, no per-day header — and a week reads as one column of work instead of five
    /// nested lists.
    private func dayGroup(_ group: (day: Date, tasks: [TaskEntity])) -> some View {
        let isToday = Calendar.current.isDateInToday(group.day)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.weekdayAbbrev[Self.weekdayIndex(for: group.day)])
                    .wpTypography(.micro)
                    .foregroundStyle(isToday ? ColorTokens.textPrimary : ColorTokens.textSecondary)
                Text(group.day.formatted(.dateTime.day()))
                    .wpTypography(.cardTitle)
                    .foregroundStyle(isToday ? ColorTokens.textPrimary : ColorTokens.textSecondary)
            }
            .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(group.tasks, id: \.objectID) { task in
                    compactTaskRow(task)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .frame(width: 62, alignment: .leading)
                Text(task.title ?? "")
                    .wpTypography(.body)
                    .foregroundStyle(task.isDone ? ColorTokens.textSecondary : ColorTokens.textPrimary)
                    .strikethrough(task.isDone)
                    .lineLimit(1)
                Spacer(minLength: 4)
                stateDot(for: task)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Marks only what isn't already visible — the same rule the badges on Today follow. A done
    /// task is struck through and greyed, so a dot beside it says nothing a fourth time; a
    /// pending one needs no mark at all. What's left is the two states you'd actually want to
    /// spot while scanning a week, which is what makes a dot appearing mean something.
    @ViewBuilder
    private func stateDot(for task: TaskEntity) -> some View {
        switch task.state {
        case .overdue:
            Circle().fill(ColorTokens.warning).frame(width: 6, height: 6)
        case .inProgress:
            Circle().fill(theme.accentSwatch.inProgressColor).frame(width: 6, height: 6)
        case .done, .pending, .future:
            EmptyView()
        }
    }
}
