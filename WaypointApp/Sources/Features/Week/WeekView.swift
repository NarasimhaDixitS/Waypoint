import SwiftUI

struct WeekView: View {
    @EnvironmentObject private var theme: ThemeManager

    /// The Monday this week starts on — the parent owns and animates this so the browsed
    /// week persists across tab switches, the same pattern as Today's `selectedDate`.
    let weekStart: Date
    var onSelectDay: (Date) -> Void = { _ in }
    var onNavigateWeek: (Date) -> Void = { _ in }

    private let weekDays: [Date]

    @FetchRequest private var weekTasks: FetchedResults<TaskEntity>
    /// Which month's weeks the week-chip row is showing — independent of `weekStart` itself,
    /// so browsing the month strip doesn't navigate until a specific week chip is tapped.
    /// `MainTabView` rebuilds this whole view via `.id()` whenever `weekStart` changes, so
    /// seeding this once from `weekStart` in `init` is enough to stay in sync.
    @State private var selectedMonth: Date

    init(
        weekStart: Date,
        onSelectDay: @escaping (Date) -> Void = { _ in },
        onNavigateWeek: @escaping (Date) -> Void = { _ in }
    ) {
        self.weekStart = weekStart
        self.onSelectDay = onSelectDay
        self.onNavigateWeek = onNavigateWeek
        let cal = Calendar.current
        let monday = cal.startOfDay(for: weekStart)
        let nextMonday = cal.date(byAdding: .day, value: 7, to: monday)!
        weekDays = (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday)! }
        _weekTasks = FetchRequest(fetchRequest: TaskEntity.fetchRequest(from: monday, to: nextMonday))
        _selectedMonth = State(initialValue: cal.date(from: cal.dateComponents([.year, .month], from: monday)) ?? monday)
    }

    /// The Monday of the week containing `date` — used both to know if we're viewing the
    /// real current week, and to compute where "Jump to this week" should go.
    static func mondayOfWeek(containing date: Date) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: today) // 1 = Sun
        let mondayOffset = (weekday + 5) % 7 // days since Monday
        return cal.date(byAdding: .day, value: -mondayOffset, to: today)!
    }

    /// Hardcoded rather than `.formatted(.dateTime.weekday(...))` or `Calendar` symbol
    /// APIs — both read the device's region (this simulator is `en_IN`), whose weekday
    /// data has produced wrong/blank output here before. Index 0 = Monday, matching
    /// `weekDays`.
    private static let weekdayAbbrev = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let weekdayLetter = ["M", "T", "W", "T", "F", "S", "S"]

    private static func weekdayIndex(for date: Date) -> Int {
        (Calendar.current.component(.weekday, from: date) + 5) % 7
    }

    private var isCurrentWeek: Bool {
        Calendar.current.isDate(weekStart, inSameDayAs: Self.mondayOfWeek(containing: .now))
    }

    private var weekRangeLabel: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// Adjacent months centered on today — a fixed range keeps the strip simple (no
    /// virtualization) while still covering far more than anyone browses in practice.
    private var monthOptions: [Date] {
        let cal = Calendar.current
        let base = cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now
        return (-6...6).compactMap { cal.date(byAdding: .month, value: $0, to: base) }
    }

    /// Every Monday whose week overlaps `selectedMonth`, in order.
    private var weekOptions: [Date] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: selectedMonth) else { return [] }
        var mondays: [Date] = []
        var cursor = Self.mondayOfWeek(containing: interval.start)
        while cursor < interval.end {
            mondays.append(cursor)
            cursor = cal.date(byAdding: .day, value: 7, to: cursor) ?? interval.end
        }
        return mondays
    }

    /// This week's tasks grouped by goal, goal groups sorted by name, ungoaled tasks (if
    /// any) always last as "Other tasks" — ad-hoc tasks stay visible rather than silently
    /// dropping out of a goal-first layout.
    private var goalGroups: [(goal: GoalEntity?, tasks: [TaskEntity])] {
        let grouped = Dictionary(grouping: weekTasks, by: { $0.goal })
        let namedGoals = grouped.keys.compactMap { $0 }.sorted { ($0.name ?? "") < ($1.name ?? "") }
        var result: [(GoalEntity?, [TaskEntity])] = namedGoals.map { goal in
            (goal, (grouped[goal] ?? []).sorted { $0.resolvedStartTime < $1.resolvedStartTime })
        }
        if let ungoaled = grouped[Optional<GoalEntity>.none], !ungoaled.isEmpty {
            result.append((nil, ungoaled.sorted { $0.resolvedStartTime < $1.resolvedStartTime }))
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                monthStrip
                weekChipStrip

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(goalGroups.enumerated()), id: \.offset) { _, group in
                        goalSection(goal: group.goal, tasks: group.tasks)
                    }
                    if goalGroups.isEmpty {
                        Text("No tasks this week")
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textSecondary)
                            .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(CurvedBackground(topHeight: 210))
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(isCurrentWeek ? "This week" : weekRangeLabel)
                .wpTypography(.screenTitle)
                .foregroundStyle(ColorTokens.textPrimary)
            Spacer()
            if !isCurrentWeek {
                Button {
                    onNavigateWeek(Self.mondayOfWeek(containing: .now))
                } label: {
                    Text("Jump to this week")
                        .wpTypography(.body)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(theme.accentSwatch.color)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private var monthStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(monthOptions, id: \.self) { month in
                        let isSelected = Calendar.current.isDate(month, equalTo: selectedMonth, toGranularity: .month)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedMonth = month }
                        } label: {
                            Text(month.formatted(.dateTime.month(.abbreviated)))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : ColorTokens.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(isSelected ? theme.accentSwatch.color : Color.clear)
                                .overlay(
                                    Capsule().stroke(isSelected ? Color.clear : ColorTokens.border, lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(month)
                    }
                }
            }
            .onAppear { proxy.scrollTo(selectedMonth, anchor: .center) }
        }
    }

    private var weekChipStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(weekOptions.enumerated()), id: \.offset) { index, monday in
                        let isSelected = Calendar.current.isDate(monday, inSameDayAs: weekStart)
                        Button {
                            onNavigateWeek(monday)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Wk \(index + 1)")
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(chipRangeLabel(monday))
                                    .font(.system(size: 10.5))
                                    .opacity(0.75)
                            }
                            .foregroundStyle(isSelected ? theme.accentSwatch.color : ColorTokens.textSecondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(isSelected ? theme.accentSwatch.color.opacity(0.14) : ColorTokens.surface1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(isSelected ? theme.accentSwatch.color : Color.clear, lineWidth: 1.4)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .id(monday)
                    }
                }
            }
            .onAppear { proxy.scrollTo(weekStart, anchor: .center) }
        }
    }

    private func chipRangeLabel(_ monday: Date) -> String {
        let sunday = Calendar.current.date(byAdding: .day, value: 6, to: monday) ?? monday
        return "\(monday.formatted(.dateTime.month(.abbreviated).day()))–\(sunday.formatted(.dateTime.day()))"
    }

    private func goalSection(goal: GoalEntity?, tasks: [TaskEntity]) -> some View {
        let doneCount = tasks.filter(\.isDone).count

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal?.name ?? "Other tasks")
                    .wpTypography(.cardTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                Spacer()
                if goal != nil {
                    Text("\(doneCount) of \(tasks.count) this week")
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textSecondary)
                }
            }

            if goal != nil {
                weekRing(for: tasks)
                    .padding(.top, 10)
                Divider()
                    .background(ColorTokens.border)
                    .padding(.vertical, 10)
            } else {
                Spacer().frame(height: 10)
            }

            VStack(spacing: 8) {
                ForEach(tasks, id: \.objectID) { task in
                    goalTaskRow(task)
                }
            }
        }
        .padding(14)
        .background(ColorTokens.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// This goal's week-strip ring, keyed to the browsed week's actual seven days — not the
    /// trailing-7-from-today window `GoalEntity.recentCompletion` uses elsewhere, since this
    /// row sits directly above a task list for these specific dates.
    private func weekRing(for tasks: [TaskEntity]) -> some View {
        HStack(spacing: 9) {
            ForEach(weekDays, id: \.self) { day in
                let hasDoneTask = tasks.contains { $0.isDone && Calendar.current.isDate($0.resolvedDate, inSameDayAs: day) }
                let isToday = Calendar.current.isDateInToday(day)
                VStack(spacing: 4) {
                    ZStack {
                        if isToday {
                            Circle().fill(theme.accentSwatch.color.opacity(0.18)).frame(width: 21, height: 21)
                        }
                        Circle()
                            .strokeBorder(theme.accentSwatch.color.opacity(hasDoneTask || isToday ? 1 : 0.35), lineWidth: isToday ? 2 : 1.6)
                            .background(Circle().fill(hasDoneTask ? theme.accentSwatch.color : .clear))
                            .frame(width: 15, height: 15)
                    }
                    .frame(width: 21, height: 21)
                    Text(Self.weekdayLetter[Self.weekdayIndex(for: day)])
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ColorTokens.textMuted)
                }
            }
        }
    }

    private func goalTaskRow(_ task: TaskEntity) -> some View {
        Button {
            onSelectDay(task.resolvedDate)
        } label: {
            HStack(spacing: 9) {
                Text(Self.weekdayAbbrev[Self.weekdayIndex(for: task.resolvedDate)])
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Calendar.current.isDateInToday(task.resolvedDate) ? theme.accentSwatch.color : ColorTokens.textMuted)
                    .frame(width: 30, alignment: .leading)
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
}
