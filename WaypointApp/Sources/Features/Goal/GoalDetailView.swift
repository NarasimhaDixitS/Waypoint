import SwiftUI
import Charts

/// Single sheet driver — see TodayView's ActiveSheet for why this screen doesn't use
/// several independent `.sheet` modifiers.
private enum ActiveSheet: Identifiable {
    case editTask(TaskEntity)
    case newDraftBump(NewTaskBumpInfo)
    case cascadeConfirm(CascadeConfirmInfo)
    case editBump(EditBumpInfo)

    var id: String {
        switch self {
        case .editTask(let t): "editTask-\(t.objectID)"
        case .newDraftBump: "newDraftBump"
        case .cascadeConfirm: "cascadeConfirm"
        case .editBump: "editBump"
        }
    }
}

/// Payload for the "new task collided with something immovable" sheet — carried on the
/// `ActiveSheet` case itself (not a separate `@State` var) so it can never go out of sync
/// with which sheet is actually on screen. See TodayView's identical types for why.
private struct NewTaskBumpInfo {
    let draft: TaskDraft
    let collidingTasks: [TaskEntity]
    let blockedBy: String
    let appendStart: Date?
}

private struct PendingEdit {
    let draft: TaskDraft
    let task: TaskEntity
}

private struct CascadeConfirmInfo {
    let edit: PendingEdit
    let shifts: [CascadeShift]
}

private struct EditBumpInfo {
    let edit: PendingEdit
    let candidates: [TaskEntity]
    let blockedBy: String
}

struct GoalDetailView: View {
    @ObservedObject var goal: GoalEntity
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager
    @State private var activeSheet: ActiveSheet?
    /// See TodayView's identical property for why direct-swap between two non-nil
    /// sheets isn't safe and this queue exists.
    @State private var queuedSheet: ActiveSheet?
    @State private var showingDeleteConfirm = false
    /// Shown right after creating a task with a repeat attached — see `TodayView`'s identical
    /// `repeatCreationSummary` for why this needs to exist at all.
    @State private var repeatCreationSummary: String?


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goal")
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textSecondary)
                    Text(goal.name ?? "")
                        .wpTypography(.screenTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                }
                .padding(.top, 12)

                VStack(spacing: 8) {
                    ProgressRing(
                        progress: goal.completionFraction,
                        lineWidth: 9,
                        color: theme.accentSwatch.markColor,
                        labelFont: .system(size: 22, weight: .semibold)
                    )
                    .frame(width: 148, height: 148)

                    Text("Day \(goal.currentDayNumber) of \(goal.totalDayCount) · \(goal.daysRemaining) days to go")
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textSecondary)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    statCard(value: "\(goal.doneTaskCount)", label: "Tasks done")
                    statCard(value: "\(goal.dayStreak)", label: "Day streak")
                }

                goalCharts

                VStack(alignment: .leading, spacing: 8) {
                    Text("Upcoming")
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textSecondary)

                    if goal.upcomingTasks.isEmpty {
                        Text("Nothing scheduled yet.")
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textMuted)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(goal.upcomingTasks.prefix(10)) { task in
                                Button {
                                    presentSheet(.editTask(task))
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(task.title ?? "")
                                                .wpTypography(.cardTitle)
                                                .foregroundStyle(ColorTokens.textPrimary)
                                            Text(task.resolvedDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                                .wpTypography(.body)
                                                .foregroundStyle(ColorTokens.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(ColorTokens.textMuted)
                                    }
                                    .wpCard()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Text("Delete goal")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .background(ColorTokens.surface0.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this goal?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete goal and its tasks", role: .destructive) {
                // One row for the goal, not one per task: the cascade below wipes out every
                // task under it, and logging each of those as its own abandonment would drown
                // the single decision that actually happened in up to a few hundred rows.
                TaskEventLog.recordGoalAbandonmentIfNeeded(goal: goal, in: context)
                context.delete(goal)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the goal and every task linked to it. This can't be undone.")
        }
        .alert("Repeat", isPresented: Binding(get: { repeatCreationSummary != nil }, set: { if !$0 { repeatCreationSummary = nil } })) {
            Button("OK") { repeatCreationSummary = nil }
        } message: {
            Text(repeatCreationSummary ?? "")
        }
        .sheet(item: $activeSheet, onDismiss: handleSheetDismissed) { sheet in
            switch sheet {
            case .editTask(let task):
                NewTaskView(
                    existingTask: task,
                    defaultDate: task.resolvedDate,
                    onSave: handleSave,
                    onDelete: {
                        if let id = task.id { NotificationManager.cancelReminder(taskID: id) }
                        TaskEventLog.recordAbandonmentIfNeeded(task: task, in: context)
                        context.delete(task)
                        try? context.save()
                    },
                    onDeleteSeries: { deleteSeries(from: task) },
                    onDuplicate: { draft in handleNewDraft(draft) }
                )
            case .newDraftBump(let info):
                AdhocBumpView(
                    headline: "Needs a slot",
                    message: newDraftMessage(for: info),
                    collidingTasks: info.collidingTasks,
                    onBumpExisting: { existing in
                        bumpToTomorrow(existing)
                        persist(info.draft)
                    },
                    secondaryLabel: "Move \u{201C}\(info.draft.title)\u{201D} to tomorrow instead",
                    onSecondaryAction: {
                        persist(bumped(info.draft))
                    },
                    appendStart: info.appendStart,
                    onAppendToEnd: info.appendStart.map { start in
                        { persist(appended(info.draft, at: start)) }
                    }
                )
            case .cascadeConfirm(let info):
                CascadeConfirmView(
                    shifts: info.shifts,
                    onConfirm: { confirmCascade(info) },
                    onCancel: {}
                )
            case .editBump(let info):
                AdhocBumpView(
                    headline: "Can't fit that change",
                    message: "Extending \"\(info.edit.task.title ?? "this task")\" runs into \(info.blockedBy). Pick a task to move to tomorrow, or keep the original time.",
                    collidingTasks: info.candidates,
                    onBumpExisting: { candidate in
                        bumpToTomorrow(candidate)
                        applyEdit(info.edit.draft, to: info.edit.task)
                    },
                    secondaryLabel: "Keep the original time",
                    onSecondaryAction: {}
                )
            }
        }
    }

    // MARK: - Actions

    private func handleSave(_ draft: TaskDraft, existing: TaskEntity?) {
        guard let existing else { return }
        let startUnchanged = abs(draft.startTime.timeIntervalSince(existing.resolvedStartTime)) < 60
        let isDurationIncrease = startUnchanged && draft.durationMinutes > Int(existing.durationMinutes)

        let resolution: EditResolution = isDurationIncrease
            ? ScheduleEngine.resolveDurationIncrease(task: existing, newDurationMinutes: draft.durationMinutes, context: context)
            : ScheduleEngine.resolveTimeMove(task: existing, newStart: draft.startTime, newDurationMinutes: draft.durationMinutes, context: context)

        switch resolution {
        case .none:
            applyEdit(draft, to: existing)
            activeSheet = nil
        case .cascade(let shifts):
            presentSheet(.cascadeConfirm(CascadeConfirmInfo(edit: PendingEdit(draft: draft, task: existing), shifts: shifts)))
        case .hardBump(let candidates, let blockedBy):
            presentSheet(.editBump(EditBumpInfo(edit: PendingEdit(draft: draft, task: existing), candidates: candidates, blockedBy: blockedBy)))
        }
    }

    private func handleNewDraft(_ draft: TaskDraft) {
        let resolution = ScheduleEngine.resolveNewTask(start: draft.startTime, end: draft.endTime, on: draft.date, context: context)
        switch resolution {
        case .none:
            persist(draft)
            activeSheet = nil
        case .appendable(let appendStart, let candidates, let blockedBy):
            presentSheet(.newDraftBump(NewTaskBumpInfo(draft: draft, collidingTasks: candidates, blockedBy: blockedBy, appendStart: appendStart)))
        case .hardBump(let candidates, let blockedBy):
            presentSheet(.newDraftBump(NewTaskBumpInfo(draft: draft, collidingTasks: candidates, blockedBy: blockedBy, appendStart: nil)))
        }
    }

    private func bumped(_ draft: TaskDraft) -> TaskDraft {
        var copy = draft
        let cal = Calendar.current
        copy.date = cal.date(byAdding: .day, value: 1, to: draft.date) ?? draft.date
        copy.startTime = cal.date(byAdding: .day, value: 1, to: draft.startTime) ?? draft.startTime
        return copy
    }

    private func appended(_ draft: TaskDraft, at start: Date) -> TaskDraft {
        var copy = draft
        copy.startTime = start
        return copy
    }

    private func newDraftMessage(for info: NewTaskBumpInfo) -> String {
        "\u{201C}\(info.draft.title)\u{201D} overlaps \(info.blockedBy)."
    }

    private func presentSheet(_ sheet: ActiveSheet) {
        if activeSheet == nil {
            activeSheet = sheet
        } else {
            queuedSheet = sheet
            activeSheet = nil
        }
    }

    private func handleSheetDismissed() {
        guard let queuedSheet else { return }
        self.queuedSheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            activeSheet = queuedSheet
        }
    }

    /// Deletes this occurrence and every future one in the same repeat series, leaving past
    /// occurrences (and their completion history) untouched.
    private func deleteSeries(from task: TaskEntity) {
        guard let seriesID = task.seriesID else {
            if let id = task.id { NotificationManager.cancelReminder(taskID: id) }
            TaskEventLog.recordAbandonmentIfNeeded(task: task, in: context)
            context.delete(task)
            try? context.save()
            return
        }
        let request = TaskEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "seriesID == %@ AND date >= %@",
            seriesID as CVarArg,
            Calendar.current.startOfDay(for: task.resolvedDate) as NSDate
        )
        let matches = (try? context.fetch(request)) ?? []
        for match in matches {
            if let id = match.id { NotificationManager.cancelReminder(taskID: id) }
            TaskEventLog.recordAbandonmentIfNeeded(task: match, in: context)
            context.delete(match)
        }
        try? context.save()
    }

    private func persist(_ draft: TaskDraft) {
        let task = TaskEntity.create(
            in: context,
            title: draft.title,
            date: draft.date,
            startTime: draft.startTime,
            durationMinutes: draft.durationMinutes,
            priority: draft.priority,
            goal: draft.goal,
            notes: draft.notes
        )
        try? context.save()
        rescheduleReminder(for: task)
        if !draft.repeatWeekdays.isEmpty {
            let result = TaskReplicator.repeatWeekly(task, onWeekdays: draft.repeatWeekdays, forWeeks: draft.repeatWeeks, context: context)
            repeatCreationSummary = TaskReplicator.summaryText(created: result.created, skipped: result.skipped, lastDate: result.lastDate)
        }
    }

    private func applyEdit(_ draft: TaskDraft, to existing: TaskEntity) {
        existing.apply(draft, in: context)
        try? context.save()
        rescheduleReminder(for: existing)
    }

    private func confirmCascade(_ info: CascadeConfirmInfo) {
        for shift in info.shifts {
            shift.task.startTime = shift.newStart
        }
        applyEdit(info.edit.draft, to: info.edit.task)
        for shift in info.shifts {
            rescheduleReminder(for: shift.task)
        }
    }

    private func bumpToTomorrow(_ task: TaskEntity) {
        let cal = Calendar.current
        task.date = cal.date(byAdding: .day, value: 1, to: task.resolvedDate) ?? task.date
        task.startTime = cal.date(byAdding: .day, value: 1, to: task.resolvedStartTime) ?? task.startTime
        try? context.save()
        rescheduleReminder(for: task)
    }

    private func rescheduleReminder(for task: TaskEntity) {
        guard let id = task.id else { return }
        NotificationManager.cancelReminder(taskID: id)
        guard theme.notificationsEnabled, !task.isDone else { return }
        NotificationManager.scheduleReminder(taskID: id, title: task.title ?? "Task", startTime: task.resolvedStartTime)
    }

    /// The same analyses the Progress tab runs, narrowed to one goal. A goal's own page is where
    /// "am I actually going to finish this" is a live question, and a ring showing 43% answers a
    /// different one — it says how far along you are, not whether that is far enough by now.
    @ViewBuilder
    private var goalCharts: some View {
        let tasks = goal.sortedTasks
        let burndown = ProgressAnalytics.burndown(for: goal)
        let weekday = ProgressAnalytics.completionByWeekday(tasks)
        let effort = ProgressAnalytics.effortByWeek(tasks, weeks: 6)
        let priorities = ProgressAnalytics.priorityFollowThrough(tasks)
        let accent = theme.accentSwatch.markColor

        AnalyticsCard(title: "Will you make the deadline?", caption: paceCaption(burndown)) {
            if burndown.isEmpty {
                AnalyticsEmpty(message: "Needs a target date and at least one task.")
            } else {
                GoalBurndownChart(points: burndown, accent: accent)
            }
        }

        AnalyticsCard(
            title: "Which days you show up",
            caption: "How much of this goal's work gets done, by day of the week."
        ) {
            let withWork = weekday.filter { $0.total > 0 }
            if withWork.isEmpty {
                AnalyticsEmpty(message: "No days have come round yet.")
            } else {
                Chart(weekday) { row in
                    BarMark(x: .value("Day", row.label), y: .value("Completed", row.fraction))
                        .foregroundStyle(accent)
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
                .frame(height: 140)
            }
        }

        AnalyticsCard(
            title: "Hours put in",
            caption: "What this goal has actually cost you, week by week."
        ) {
            if effort.allSatisfy({ $0.plannedMinutes == 0 }) {
                AnalyticsEmpty(message: "No work scheduled in the last six weeks.")
            } else {
                Chart(effort) { week in
                    BarMark(x: .value("Week", week.weekStart, unit: .weekOfYear), y: .value("Done", week.completedHours))
                        .foregroundStyle(accent)
                        .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: effort.map(\.weekStart)) { value in
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
                .frame(height: 140)
            }
        }

        AnalyticsCard(
            title: "Priorities within this goal",
            caption: "Whether the work you called important is the work getting done."
        ) {
            if priorities.allSatisfy({ $0.total == 0 }) {
                AnalyticsEmpty(message: "Not enough finished work yet.")
            } else {
                VStack(spacing: 12) {
                    ForEach(priorities) { row in
                        RatioBar(
                            label: row.label, done: row.done, total: row.total, fraction: row.fraction,
                            tint: row.id == Priority.high.rawValue ? ColorTokens.warning : accent
                        )
                    }
                }
            }
        }
    }

    private func paceCaption(_ points: [ProgressAnalytics.BurndownPoint]) -> String {
        guard let last = points.last else { return "Work remaining against the pace the deadline needs." }
        if Double(last.remaining) <= last.idealRemaining {
            return "On or ahead of pace — \(last.remaining) left, where an even run would still have \(Int(last.idealRemaining))."
        }
        return "Behind pace — \(last.remaining) left, where an even run would be down to \(Int(last.idealRemaining))."
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).wpTypography(.bigStat).foregroundStyle(ColorTokens.textPrimary)
            Text(label).wpTypography(.micro).foregroundStyle(ColorTokens.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .wpCard(padding: 0)
    }
}
