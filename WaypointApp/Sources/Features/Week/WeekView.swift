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
            mode = target
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(mode == target ? theme.accentSwatch.color : .white.opacity(0.85))
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
        browsedGoalID = goal.objectID
        expandedWeekInGoal = Self.defaultExpandedWeek(among: weeks(for: goal))
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
                        index: weeksInMonth.firstIndex(of: monday) ?? 0,
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
                            index: weeks.firstIndex(of: monday) ?? 0,
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

    /// The current week's card always reads as the focal point — bigger title/meta/progress
    /// ring and a soft accent-tinted background, the same "this is the one happening right now"
    /// treatment as the in-progress task row on Today. Every other card stays compact and
    /// neutral, and tapping one swaps which card gets the treatment (falls out of `isExpanded`
    /// naturally, since only one week can be expanded per mode at a time).
    private func weekCard(
        index: Int,
        monday: Date,
        tasks: [TaskEntity],
        isExpanded: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        let sunday = Calendar.current.date(byAdding: .day, value: 6, to: monday) ?? monday
        let done = tasks.filter(\.isDone).count
        let total = tasks.count
        let rangeLabel = "\(monday.formatted(.dateTime.month(.abbreviated).day()))–\(sunday.formatted(.dateTime.day()))"
        let accentColor = isExpanded ? theme.accentSwatch.color : ColorTokens.textPrimary
        let accentMetaColor = isExpanded ? theme.accentSwatch.color.opacity(0.8) : ColorTokens.textSecondary
        let isCurrentWeek = monday == Self.mondayOfWeek(containing: .now)
        let titleLabel = isCurrentWeek ? "Current Week · Week \(index + 1)" : "Week \(index + 1)"

        return VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: isExpanded ? 16 : 14) {
                    VStack(alignment: .leading, spacing: isExpanded ? 5 : 3) {
                        Text(titleLabel)
                            .wpTypography(isExpanded ? .bigStat : .cardTitle)
                            .foregroundStyle(accentColor)
                        Text(total == 0 ? rangeLabel : "\(rangeLabel) · \(done) of \(total) done")
                            .wpTypography(isExpanded ? .cardTitle : .body)
                            .foregroundStyle(accentMetaColor)
                    }
                    Spacer(minLength: 8)
                    if total > 0 {
                        ProgressRing(
                            progress: Double(done) / Double(total),
                            lineWidth: isExpanded ? 5 : 4,
                            color: theme.accentSwatch.color,
                            showsLabel: false
                        )
                        .frame(width: isExpanded ? 44 : 32, height: isExpanded ? 44 : 32)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: isExpanded ? 14 : 12, weight: .semibold))
                        .foregroundStyle(isExpanded ? theme.accentSwatch.color : ColorTokens.textMuted)
                }
                .padding(isExpanded ? 20 : 16)
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
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(ColorTokens.surface1)
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 22 : 18, style: .continuous))
        .overlay(alignment: .leading) {
            // A left-edge accent stripe instead of a full tinted fill — the bigger size and
            // accent-colored title already say "this is the current one"; a full color wash on
            // top of that competed too much with the banner and tab bar's own solid accent.
            if isExpanded {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(theme.accentSwatch.color)
                    .frame(width: 4)
                    .padding(.vertical, 10)
            }
        }
        .id(monday)
    }

    private func dayGroup(_ group: (day: Date, tasks: [TaskEntity])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(Self.weekdayAbbrev[Self.weekdayIndex(for: group.day)]) \(group.day.formatted(.dateTime.day()))")
                    .wpTypography(.cardTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                Rectangle().fill(ColorTokens.border).frame(height: 1)
                Text("\(group.tasks.count) task\(group.tasks.count == 1 ? "" : "s")")
                    .wpTypography(.micro)
                    .foregroundStyle(ColorTokens.textMuted)
            }
            VStack(spacing: 8) {
                ForEach(group.tasks, id: \.objectID) { task in
                    compactTaskRow(task)
                }
            }
        }
    }

    private func compactTaskRow(_ task: TaskEntity) -> some View {
        Button {
            onSelectDay(task.resolvedDate)
        } label: {
            HStack(spacing: 9) {
                Circle().fill(taskDotColor(task)).frame(width: 6, height: 6)
                Text(task.title ?? "")
                    .wpTypography(.body)
                    .foregroundStyle(task.isDone ? ColorTokens.textSecondary : ColorTokens.textPrimary)
                    .strikethrough(task.isDone)
                    .lineLimit(1)
                Spacer()
                Text(task.timeRangeLabel)
                    .wpTypography(.micro)
                    .foregroundStyle(ColorTokens.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func taskDotColor(_ task: TaskEntity) -> Color {
        switch task.state {
        case .done: ColorTokens.success
        case .overdue: ColorTokens.warning
        case .future: ColorTokens.scheduled
        case .inProgress: theme.accentSwatch.inProgressColor
        case .pending: ColorTokens.textMuted
        }
    }
}
