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
    @EnvironmentObject private var subscription: SubscriptionManager
    @State private var showingPaywall = false
    @State private var activeSheet: ActiveSheet?
    /// See TodayView's identical property for why direct-swap between two non-nil
    /// sheets isn't safe and this queue exists.
    @State private var queuedSheet: ActiveSheet?
    @State private var showingDeleteConfirm = false
    /// Shown right after creating a task with a repeat attached — see `TodayView`'s identical
    /// `repeatCreationSummary` for why this needs to exist at all.
    @State private var repeatCreationSummary: String?


    var body: some View {
        SelectableTaskList(
            title: goal.name ?? "Untitled goal",
            subtitle: subtitle,
            tasks: goal.sortedTasks,
            emptyMessage: "No tasks under this goal yet. Add one from Today and pick this goal.",
            summary: { AnyView(summarySection) },
            onEditTask: requestEdit
        )
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
        .sheet(isPresented: $showingPaywall) { PaywallView() }
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
                TaskClashView(
                    subjectTitle: info.draft.title,
                    subjectRange: draftRangeLabel(info.draft),
                    conflicts: info.collidingTasks,
                    slots: openSlots(fitting: info.draft),
                    onPickSlot: { start in persist(appended(info.draft, at: start)) },
                    onBumpConflicts: { tasks in
                        tasks.forEach(bumpToTomorrow)
                        persist(info.draft)
                    }
                )
            case .cascadeConfirm(let info):
                CascadeConfirmView(
                    shifts: info.shifts,
                    onConfirm: { confirmCascade(info) },
                    onCancel: {}
                )
            case .editBump(let info):
                TaskClashView(
                    subjectTitle: info.edit.task.title ?? "This task",
                    subjectRange: draftRangeLabel(info.edit.draft),
                    conflicts: info.candidates,
                    // No alternative times offered on an edit. The person just chose this one
                    // deliberately, in a picker, so handing back a row of other times answers a
                    // question nobody asked — the only useful moves are clear the way, or don't.
                    slots: [],
                    onPickSlot: { _ in },
                    onBumpConflicts: { tasks in
                        tasks.forEach(bumpToTomorrow)
                        applyEdit(info.edit.draft, to: info.edit.task)
                    }
                )
            }
        }
    }

    private var subtitle: String {
        let remaining = goal.daysRemaining
        if goal.completionFraction >= 1 { return "Finished" }
        return remaining > 0
            ? "Day \(goal.currentDayNumber) of \(goal.totalDayCount) · \(remaining) to go"
            : "Past its date"
    }

    /// Everything above the task list: how far along, how it's been going, and what the charts
    /// say. Handed to `SelectableTaskList` so the page scrolls as one piece — a pinned header
    /// over a nested scroll view would mean two scrollbars and a heatmap you can't reach.
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                ProgressRing(
                    progress: goal.completionFraction,
                    lineWidth: 8,
                    color: theme.accentSwatch.markColor,
                    labelFont: .system(size: 18, weight: .semibold)
                )
                .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: 10) {
                    stat("\(goal.doneTaskCount)", "tasks done")
                    stat("\(goal.dayStreak)", "day streak")
                }

                Spacer(minLength: 0)
            }

            // The heatmap goes directly under the ring rather than down with the charts. The
            // ring says how far along; this says how it has actually gone — and together they
            // answer the two questions anyone opens a goal to ask, before any chart is needed.
            AnalyticsCard(
                title: "How it's gone",
                caption: "Each square is a day. Filled means you finished what that day asked."
            ) {
                GoalHeatmap(days: ProgressAnalytics.heatmap(for: goal))
            }

            goalCharts

            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Text("Delete goal")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .padding(.top, 4)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .wpTypography(.cardTitle)
                .foregroundStyle(ColorTokens.textPrimary)
            Text(label)
                .wpTypography(.body)
                .foregroundStyle(ColorTokens.textSecondary)
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

    /// The same chokepoint Today uses, for the same reason: a goal's task list is a third route
    /// into the editor, and gating the other two left this one open.
    private func requestEdit(_ task: TaskEntity) {
        guard subscription.status.canEditDay(task.resolvedDate) else {
            showingPaywall = true
            return
        }
        presentSheet(.editTask(task))
    }

    private func draftRangeLabel(_ draft: TaskDraft) -> String {
        "\(draft.startTime.formatted(.dateTime.hour().minute()))–\(draft.endTime.formatted(.dateTime.hour().minute()))"
    }

    private func openSlots(fitting draft: TaskDraft) -> [ScheduleEngine.OpenSlot] {
        let notBefore = Calendar.current.isDateInToday(draft.date) ? Date.now : .distantPast
        return Array(
            ScheduleEngine.openSlots(
                on: draft.date, minimumMinutes: draft.durationMinutes,
                notBefore: notBefore, context: context
            ).prefix(4)
        )
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

    /// Same wholesale rebuild Today does. This screen can edit a task scheduled for today, so
    /// it has to refresh the same set rather than patch one notification.
    private func rescheduleReminder(for task: TaskEntity) {
        NotificationManager.refreshTaskReminders(in: context, enabled: theme.notificationsEnabled)
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
