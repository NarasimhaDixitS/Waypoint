import SwiftUI

/// A day's status at a glance, mirroring `TaskState`'s color language so the week view reads
/// consistently with task rows: green if you finished everything, warning if a past day was
/// left unfinished, the "upcoming" tone for future days with tasks planned.
private enum DayCardState {
    case done
    case missed
    case today
    case upcoming
    case empty
}

struct WeekView: View {
    @EnvironmentObject private var theme: ThemeManager

    /// The Monday this week starts on — the parent owns and animates this so the browsed
    /// week persists across tab switches, the same pattern as Today's `selectedDate`.
    let weekStart: Date
    var onSelectDay: (Date) -> Void = { _ in }
    var onNavigateWeek: (Date) -> Void = { _ in }

    private let weekDays: [Date]

    @FetchRequest private var weekTasks: FetchedResults<TaskEntity>
    /// At most one day expanded at a time — tapping its disclosure chevron shows that day's
    /// actual tasks inline, without leaving Week.
    @State private var expandedDay: Date?

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

    private var isCurrentWeek: Bool {
        Calendar.current.isDate(weekStart, inSameDayAs: Self.mondayOfWeek(containing: .now))
    }

    private var weekRangeLabel: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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

                dateStrip

                VStack(spacing: 10) {
                    ForEach(weekDays, id: \.self) { day in
                        dayCard(day)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(ColorTokens.surface0.ignoresSafeArea())
        .navigationBarHidden(true)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    let horizontal = value.translation.width
                    guard abs(horizontal) > abs(value.translation.height), abs(horizontal) > 40 else { return }
                    let cal = Calendar.current
                    let newStart = cal.date(byAdding: .day, value: horizontal < 0 ? 7 : -7, to: weekStart) ?? weekStart
                    onNavigateWeek(newStart)
                }
        )
    }

    private var dateStrip: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                let isToday = Calendar.current.isDateInToday(day)
                Button {
                    onSelectDay(day)
                } label: {
                    VStack(spacing: 6) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .wpTypography(.micro)
                            .foregroundStyle(ColorTokens.textSecondary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isToday ? Color.white : ColorTokens.textPrimary)
                            .frame(width: 28, height: 28)
                            .background(isToday ? theme.accentSwatch.color : stripDotColor(for: day))
                            .clipShape(Circle())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Today always wins in the strip regardless of its own completion status — it's an
    /// orientation landmark ("you are here"), not a status indicator. Every other day shows
    /// its actual state, same colors as the cards below.
    private func stripDotColor(for day: Date) -> Color {
        switch cardState(for: day) {
        case .done: ColorTokens.success
        case .missed: ColorTokens.warning
        case .upcoming: ColorTokens.scheduled
        case .today, .empty: .clear
        }
    }

    private func cardState(for day: Date) -> DayCardState {
        let cal = Calendar.current
        let total = tasksCount(for: day)
        guard total > 0 else { return .empty }
        let allDone = doneCount(for: day) == total
        if cal.isDateInToday(day) {
            return allDone ? .done : .today
        }
        if day < cal.startOfDay(for: .now) {
            return allDone ? .done : .missed
        }
        return .upcoming
    }

    private func cardTint(for state: DayCardState) -> Color {
        switch state {
        case .done: ColorTokens.successTint
        case .missed: ColorTokens.warningTint
        case .today: ColorTokens.surface1
        case .upcoming: ColorTokens.scheduledTint
        case .empty: ColorTokens.surface1
        }
    }

    private func cardTextColor(for state: DayCardState) -> Color {
        switch state {
        case .done: ColorTokens.textSuccess
        case .missed: ColorTokens.textWarning
        case .today: ColorTokens.textPrimary
        case .upcoming: ColorTokens.textScheduled
        case .empty: ColorTokens.textSecondary
        }
    }

    private func progressColor(for state: DayCardState) -> Color {
        switch state {
        case .done: ColorTokens.success
        case .missed: ColorTokens.warning
        case .today: theme.accentSwatch.color
        case .upcoming: ColorTokens.scheduled
        case .empty: ColorTokens.border
        }
    }

    private func dayCard(_ day: Date) -> some View {
        let state = cardState(for: day)
        let total = tasksCount(for: day)
        let done = doneCount(for: day)
        let isToday = Calendar.current.isDateInToday(day)
        let isExpanded = expandedDay == day

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    onSelectDay(day)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .wpTypography(.body)
                            .foregroundStyle(cardTextColor(for: state).opacity(0.85))
                        Text(state == .empty ? "No tasks" : "\(done) of \(total) tasks done")
                            .wpTypography(.cardTitle)
                            .foregroundStyle(cardTextColor(for: state))
                        if total > 0 {
                            MiniProgressBar(fraction: Double(done) / Double(total), color: progressColor(for: state))
                                .frame(width: 90)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if total > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedDay = isExpanded ? nil : day
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(cardTextColor(for: state).opacity(0.7))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(tasks(for: day), id: \.objectID) { task in
                        expandedTaskRow(task)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(cardTint(for: state))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isToday ? theme.accentSwatch.color : Color.clear, lineWidth: 1.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func expandedTaskRow(_ task: TaskEntity) -> some View {
        Button {
            onSelectDay(task.resolvedDate)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(taskDotColor(task))
                    .frame(width: 6, height: 6)
                Text(task.title ?? "")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .strikethrough(task.isDone)
                    .lineLimit(1)
                Spacer()
                Text(task.timeRangeLabel)
                    .wpTypography(.micro)
                    .foregroundStyle(ColorTokens.textSecondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(ColorTokens.surface1.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func taskDotColor(_ task: TaskEntity) -> Color {
        switch task.state {
        case .done: ColorTokens.success
        case .overdue: ColorTokens.warning
        case .future: ColorTokens.scheduled
        case .inProgress: ColorTokens.inProgress
        case .pending: ColorTokens.textMuted
        }
    }

    private func tasks(for day: Date) -> [TaskEntity] {
        let start = Calendar.current.startOfDay(for: day)
        return weekTasks.filter { Calendar.current.isDate($0.resolvedDate, inSameDayAs: start) }
    }

    private func tasksCount(for day: Date) -> Int { tasks(for: day).count }
    private func doneCount(for day: Date) -> Int { tasks(for: day).filter(\.isDone).count }
}

/// A compact status bar for a day card — deliberately not `ProgressRing`, which is too heavy
/// visually for a small list row.
private struct MiniProgressBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.25))
                Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 5)
    }
}
