import SwiftUI
import CoreData

/// A goal's tasks, grouped by when they are, with selection for bulk edits.
///
/// **Why grouped rather than one long list.** A goal's tasks are mostly past — a 90-day goal
/// on day 60 has two months of history and a fortnight ahead. A flat chronological list buries
/// the only part you can still act on under everything you can't. Overdue first because it's
/// the only group that wants a decision, then today, then what's coming, then the record.
///
/// **Selection is forward-only**, same as Today's — `BulkEditPolicy` owns that rule and this
/// screen asks it per task rather than per day, because one goal's list spans both sides of
/// today. Past rows still render, and still open individually; they just can't be ticked. See
/// `BulkEditPolicy` for why.
struct SelectableTaskList: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var subscription: SubscriptionManager

    let title: String
    let subtitle: String
    let tasks: [TaskEntity]
    var emptyMessage: String = "No tasks yet."
    /// Drawn above the list — the goal page passes its rings and heatmap through here so the
    /// whole screen scrolls as one rather than pinning a header above a nested scroll view.
    /// Type-erased rather than generic: this is the only place it varies, and a generic
    /// parameter would spread through every caller for no gain.
    var summary: () -> AnyView = { AnyView(EmptyView()) }
    /// Opening one task is the parent's job, not this view's.
    ///
    /// A single edit can move a task in time, and moving it can collide with whatever else
    /// sits on that day — which needs the whole clash-and-cascade flow. `GoalDetailView`
    /// already owns that machinery; duplicating it here would be a third copy of it, and a
    /// copy that silently diverges is how two screens end up resolving collisions differently.
    ///
    /// Bulk edits stay here, because none of them can move a task in time. That was the point
    /// of leaving time out of bulk.
    var onEditTask: (TaskEntity) -> Void

    @State private var isEditing = false
    @State private var selectedTaskIDs: Set<NSManagedObjectID> = []
    @State private var showingBulkPriority = false
    @State private var showingBulkGoal = false
    @State private var bulkGoalBinding: GoalEntity?
    @State private var pendingDeletion: PendingBulkDeletion?
    /// Which groups are open. Done starts closed — on any goal with history it's the biggest
    /// group by far, and it's a record rather than a workload, so leaving it open means
    /// scrolling past three weeks of ticks to reach the one thing that still needs doing.
    /// The others start open because they *are* the workload.
    @State private var expanded: Set<TaskGroup.Kind> = [.overdue, .today, .upcoming]
    @State private var bulkDelete: BulkDeletePlan?
    @State private var seriesConfirm: BulkDeletePlan?
    @State private var hiddenTaskIDs: Set<NSManagedObjectID> = []

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \GoalEntity.createdAt, ascending: false)]
    )
    private var goals: FetchedResults<GoalEntity>

    private static let undoWindow: TimeInterval = 4

    private var visibleTasks: [TaskEntity] {
        tasks.filter { !hiddenTaskIDs.contains($0.objectID) }
    }

    /// Can this one task be selected? Asked per task, not per screen.
    private func isSelectable(_ task: TaskEntity) -> Bool {
        BulkEditPolicy.allowsBulkEditing(
            on: task.resolvedDate,
            canEditDay: subscription.status.canEditDay(task.resolvedDate)
        )
    }

    private var hasAnythingSelectable: Bool {
        visibleTasks.contains(where: isSelectable)
    }

    private var selectedTasks: [TaskEntity] {
        selectedTaskIDs.compactMap { try? context.existingObject(with: $0) as? TaskEntity }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    // Gone while selecting. The goal page's summary is a ring, a heatmap and
                    // three charts — about a screen and a half — so entering edit mode used to
                    // leave you at the top with nothing selectable in view and a scroll to do
                    // before the mode was any use. None of it is relevant to picking tasks.
                    if !isEditing {
                        summary()
                    }

                    if visibleTasks.isEmpty {
                        Text(emptyMessage)
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textMuted)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(TaskGroup.grouped(visibleTasks), id: \.kind) { group in
                            section(group)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, ColorTokens.tabBarClearance + barClearance)
            }

            if let pendingDeletion {
                undoToast(pendingDeletion)
                    .padding(.bottom, ColorTokens.tabBarClearance)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if isEditing, !selectedTaskIDs.isEmpty {
                BulkActionBar(
                    count: selectedTaskIDs.count,
                    onPriority: { showingBulkPriority = true },
                    onGoal: { showingBulkGoal = true },
                    onDelete: deleteSelected
                )
                .padding(.bottom, ColorTokens.tabBarClearance)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(ColorTokens.surface0.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeInOut(duration: 0.22), value: isEditing)
        .animation(.easeInOut(duration: 0.22), value: selectedTaskIDs.isEmpty)
        .animation(.easeInOut(duration: 0.22), value: pendingDeletion != nil)
        .sheet(item: $bulkDelete) { plan in
            BulkDeleteSheet(
                plan: plan,
                onDeleteTasks: {
                    commitDelete(plan.selected, title: plan.plainTitle)
                },
                // Series goes through a second screen rather than deleting on the spot. It is
                // the one action here that reaches tasks the user never ticked — up to several
                // months of them — so it's deliberately two decisions, not one.
                onDeleteSeries: { seriesConfirm = plan }
            )
        }
        .sheet(item: $seriesConfirm) { plan in
            SeriesDeleteConfirmSheet(
                plan: plan,
                onConfirm: { commitDelete(plan.seriesTasks, title: plan.seriesTitle) }
            )
        }
        .sheet(isPresented: $showingBulkPriority) {
            BulkPrioritySheet(count: selectedTaskIDs.count, onPick: applyBulkPriority)
        }
        .sheet(isPresented: $showingBulkGoal) {
            GoalPickerSheet(goals: goals, selectedGoal: $bulkGoalBinding, onPick: applyBulkGoal)
        }
    }

    private var barClearance: CGFloat {
        isEditing && !selectedTaskIDs.isEmpty ? 88 : 0
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            // The app hides the navigation bar everywhere, which also hides the back button
            // it would have supplied. This screen is always pushed, so it owns its own way
            // out — without it the only route back was the home gesture.
            if !isEditing {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ColorTokens.textSecondary)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .wpTypography(.appTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .lineLimit(2)
                Text(subtitle)
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
            }

            Spacer(minLength: 8)

            if isEditing {
                Button("Done") { exitEditMode() }
                    .wpTypography(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.accentSwatch.color)
                    .frame(height: 44)
                    .buttonStyle(.plain)
            } else if hasAnythingSelectable {
                // Hidden rather than disabled when nothing on screen can be selected — a goal
                // that finished last month has no forward tasks, and a pen that opens a mode
                // where every row refuses is worse than no pen.
                Button {
                    isEditing = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(ColorTokens.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select tasks")
            }
        }
    }

    @ViewBuilder
    private func section(_ group: TaskGroup) -> some View {
        let isOpen = expanded.contains(group.kind)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isOpen { expanded.remove(group.kind) } else { expanded.insert(group.kind) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(group.kind.label.uppercased())
                        .wpTypography(.micro)
                        .fontWeight(.semibold)
                        .tracking(0.6)
                        .foregroundStyle(group.kind == .overdue ? ColorTokens.textWarning : ColorTokens.textSecondary)
                    Text("\(group.tasks.count)")
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textMuted)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ColorTokens.textMuted)
                        .rotationEffect(.degrees(isOpen ? 0 : -90))
                    Spacer()
                }
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                ForEach(group.tasks, id: \.objectID) { task in
                    row(task)
                }
            }
        }
    }

    private func row(_ task: TaskEntity) -> some View {
        let selectable = isSelectable(task)
        return HStack(spacing: 12) {
            if isEditing {
                Image(systemName: selectedTaskIDs.contains(task.objectID) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        !selectable ? ColorTokens.textMuted.opacity(0.3)
                        : selectedTaskIDs.contains(task.objectID) ? theme.accentSwatch.color
                        : ColorTokens.textMuted
                    )
                    .transition(.scale.combined(with: .opacity))
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title ?? "Untitled task")
                        .wpTypography(.cardTitle)
                        .foregroundStyle(task.isDone ? ColorTokens.textSecondary : ColorTokens.textPrimary)
                        .strikethrough(task.isDone, color: ColorTokens.textMuted)
                        .lineLimit(1)
                    Text(metaLine(task))
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textSecondary)
                }

                Spacer(minLength: 8)

                if task.isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accentSwatch.markColor)
                }
            }
            .wpCard()
            // While selecting, an unselectable row says so by fading rather than by doing
            // nothing when tapped.
            .opacity(isEditing && !selectable ? 0.45 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing {
                guard selectable else { return }
                toggleSelection(task)
            } else {
                onEditTask(task)
            }
        }
    }

    private func metaLine(_ task: TaskEntity) -> String {
        let date = task.resolvedDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let time = task.resolvedStartTime.formatted(date: .omitted, time: .shortened)
        return "\(date) · \(time) · \(task.durationMinutes)m"
    }

    // MARK: - Actions

    private func exitEditMode() {
        isEditing = false
        selectedTaskIDs = []
    }

    private func toggleSelection(_ task: TaskEntity) {
        if selectedTaskIDs.contains(task.objectID) {
            selectedTaskIDs.remove(task.objectID)
        } else {
            selectedTaskIDs.insert(task.objectID)
        }
    }

    private func deleteSelected() {
        let tasks = selectedTasks
        guard !tasks.isEmpty else { return }
        let plan = BulkDeletePlan(selected: tasks, context: context)

        // Nothing selected repeats, so there's no choice to offer — Delete just deletes, and
        // the undo toast is the safety net, exactly as before.
        guard plan.hasSeries else {
            commitDelete(tasks, title: plan.plainTitle)
            return
        }
        bulkDelete = plan
    }

    private func commitDelete(_ tasks: [TaskEntity], title: String) {
        requestDelete(tasks: tasks, title: title)
        exitEditMode()
    }

    /// One batch, one toast, one undo — the same shape as Today's, for the same reason.
    private func requestDelete(tasks: [TaskEntity], title: String) {
        if let previous = pendingDeletion { finalizeDeletion(previous) }
        for task in tasks {
            if let id = task.id { NotificationManager.cancelReminder(taskID: id) }
        }
        hiddenTaskIDs.formUnion(tasks.map(\.objectID))
        let pending = PendingBulkDeletion(tasks: tasks, title: title)
        pendingDeletion = pending
        let token = pending.id
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.undoWindow) {
            guard pendingDeletion?.id == token else { return }
            finalizeDeletion(pending)
        }
    }

    private func finalizeDeletion(_ pending: PendingBulkDeletion) {
        hiddenTaskIDs.subtract(pending.tasks.map(\.objectID))
        if pendingDeletion?.id == pending.id { pendingDeletion = nil }
        for task in pending.tasks {
            // Same as Today: logged at the point the delete becomes real, never when it's
            // merely pending, so an undone delete isn't counted as a failure that happened.
            TaskEventLog.recordAbandonmentIfNeeded(task: task, in: context)
            context.delete(task)
        }
        try? context.save()
    }

    private func undoDelete() {
        guard let pending = pendingDeletion else { return }
        hiddenTaskIDs.subtract(pending.tasks.map(\.objectID))
        pendingDeletion = nil
    }

    private func applyBulkPriority(_ priority: Priority) {
        for task in selectedTasks {
            var draft = task.currentDraft
            draft.priority = priority
            task.apply(draft, in: context)
        }
        try? context.save()
        exitEditMode()
    }

    private func applyBulkGoal(_ goal: GoalEntity?) {
        for task in selectedTasks {
            var draft = task.currentDraft
            draft.goal = goal
            task.apply(draft, in: context)
        }
        try? context.save()
        exitEditMode()
    }

    private func undoToast(_ pending: PendingBulkDeletion) -> some View {
        HStack(spacing: 14) {
            Text("\(pending.title) deleted")
                .wpTypography(.body)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Undo") { undoDelete() }
                .wpTypography(.body)
                .fontWeight(.semibold)
                .foregroundStyle(theme.accentSwatch.color)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }
}

struct PendingBulkDeletion {
    let id = UUID()
    let tasks: [TaskEntity]
    let title: String
}

/// Tasks split into the four groups this screen shows, in the order it shows them.
struct TaskGroup {
    enum Kind: String, CaseIterable {
        case overdue, today, upcoming, done

        var label: String {
            switch self {
            case .overdue: "Overdue"
            case .today: "Today"
            case .upcoming: "Upcoming"
            case .done: "Done"
            }
        }
    }

    let kind: Kind
    let tasks: [TaskEntity]

    /// Done is its own group rather than a state inside the others, because a finished task is
    /// a record and the rest are a workload — mixing them means scrolling past three weeks of
    /// ticks to reach the one thing that needs doing.
    static func grouped(_ tasks: [TaskEntity], now: Date = .now) -> [TaskGroup] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        var buckets: [Kind: [TaskEntity]] = [:]
        for task in tasks {
            let day = calendar.startOfDay(for: task.resolvedDate)
            let kind: Kind
            if task.isDone {
                kind = .done
            } else if day < today {
                kind = .overdue
            } else if day == today {
                kind = .today
            } else {
                kind = .upcoming
            }
            buckets[kind, default: []].append(task)
        }

        return Kind.allCases.compactMap { kind in
            guard let group = buckets[kind], !group.isEmpty else { return nil }
            // Overdue and done read newest-first: the most recent miss is the one you'd act on,
            // and the most recent win is the one worth seeing. The future reads soonest-first.
            let sorted = (kind == .overdue || kind == .done)
                ? group.sorted { $0.resolvedStartTime > $1.resolvedStartTime }
                : group.sorted { $0.resolvedStartTime < $1.resolvedStartTime }
            return TaskGroup(kind: kind, tasks: sorted)
        }
    }
}
