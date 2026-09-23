import SwiftUI
import CoreData

private struct PendingEdit {
    let draft: TaskDraft
    let task: TaskEntity
}

/// Payload for the "new task collided with something immovable" sheet — carried on the
/// `ActiveSheet` case itself (not a separate `@State` var) so it can never go out of sync
/// with which sheet is actually on screen.
private struct NewTaskBumpInfo {
    let draft: TaskDraft
    let collidingTasks: [TaskEntity]
    let blockedBy: String
    /// Non-nil when there's also room to just tack the new task onto the end of the day.
    let appendStart: Date?
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

/// Tracks a delete (one task, or a whole series) that hasn't been finalized yet — every task
/// involved stays in Core Data, just hidden from view, until the undo window elapses. Only one
/// pending deletion at a time: starting a new one immediately finalizes whichever was already
/// pending, matching the common "next toast replaces the last" pattern. `title` is the full
/// display phrase ("\u{201C}Task name\u{201D}" for one, "12 tasks" for a series) so the toast
/// itself doesn't need to know which case it's in.
private struct PendingDeletion {
    let id = UUID()
    let tasks: [TaskEntity]
    let title: String
}

private struct CompletionInfo: Identifiable {
    let id = UUID()
    var streak: Int
    var tasksDone: Int
    var tasksTotal: Int
    var progressBefore: Double?
    var progressAfter: Double?
}

/// A single driver for every sheet this screen can show. SwiftUI only reliably supports one
/// active sheet presentation per view — stacking many independent `.sheet(isPresented:)` /
/// `.sheet(item:)` modifiers on the same view invites exactly the bug this replaced: two of
/// them going true at once (e.g. an action inside "New Task" opening another sheet
/// while the New Task sheet itself is still showing) produces a second, blank sheet.
private enum ActiveSheet: Identifiable {
    case addTask
    case editTask(TaskEntity)
    case goalCreate
    case adhocBump(NewTaskBumpInfo)
    case cascadeConfirm(CascadeConfirmInfo)
    case editBump(EditBumpInfo)
    case completion(CompletionInfo)
    case pomodoro(TaskEntity)

    var id: String {
        switch self {
        case .addTask: "addTask"
        case .editTask(let t): "editTask-\(t.objectID)"
        case .goalCreate: "goalCreate"
        case .adhocBump: "adhocBump"
        case .cascadeConfirm: "cascadeConfirm"
        case .editBump: "editBump"
        case .completion(let info): "completion-\(info.id)"
        case .pomodoro(let t): "pomodoro-\(t.objectID)"
        }
    }
}

/// How `DayTimelineView` orders its rows top to bottom.
enum TaskSortMode: String, CaseIterable {
    case time
    case priority

    var label: String {
        switch self {
        case .time: "Time"
        case .priority: "Priority"
        }
    }

    var icon: String {
        switch self {
        case .time: "clock"
        case .priority: "flag"
        }
    }
}

private enum TimelineItem: Identifiable {
    case task(TaskEntity)
    case block(CommitmentEntity, Date, Date)
    /// Section label. Only ever present in pairs — see `DayTimelineView.timeline`.
    case header(String)

    var id: String {
        switch self {
        case .task(let t): "task-\(t.id?.uuidString ?? UUID().uuidString)"
        case .block(let c, let s, _): "block-\(c.id?.uuidString ?? UUID().uuidString)-\(s.timeIntervalSince1970)"
        case .header(let title): "header-\(title)"
        }
    }

    var sortDate: Date {
        switch self {
        case .task(let t): t.resolvedStartTime
        case .block(_, let s, _): s
        case .header: .distantPast
        }
    }

    var endDate: Date {
        switch self {
        case .task(let t): t.endTime
        case .block(_, _, let e): e
        case .header: .distantPast
        }
    }

    var taskEntity: TaskEntity? {
        if case .task(let t) = self { return t }
        return nil
    }
}

/// The day's own page in the carousel, shaped exactly like a goal card — eyebrow, title,
/// summary line, ring, and the same "Last 7 days" strip. The Today page previously carried an
/// accent block about a *goal* and a list of individual tasks, and nothing at all about the
/// day; this fills that slot in the vocabulary already established rather than inventing a
/// second kind of summary above it.
///
/// Anchored to today rather than to the browsed day, like every other page in this carousel:
/// "Last 7 days" is a today-relative idea, and goal progress isn't day-scoped either. Browsing
/// to another day changes the list below; this stays the standing picture of today.
private struct TodaySummaryCard: View {
    let now: Date
    /// Tasks mid-undo-window from a pending delete, so the count drops the moment the row does.
    let hiddenTaskIDs: Set<NSManagedObjectID>

    @EnvironmentObject private var theme: ThemeManager
    @FetchRequest private var recentTasks: FetchedResults<TaskEntity>

    init(now: Date, hiddenTaskIDs: Set<NSManagedObjectID>) {
        self.now = now
        self.hiddenTaskIDs = hiddenTaskIDs
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -6, to: today)!
        let end = cal.date(byAdding: .day, value: 1, to: today)!
        _recentTasks = FetchRequest(fetchRequest: TaskEntity.fetchRequest(from: start, to: end))
    }

    private var visible: [TaskEntity] {
        recentTasks.filter { !hiddenTaskIDs.contains($0.objectID) }
    }

    /// Commitments are excluded by construction — they're a separate entity and never fetched
    /// here. A fixed Work or Gym block isn't something you tick off, so counting it would
    /// inflate both halves of the ratio with work you never chose and can never complete.
    private var todaysTasks: [TaskEntity] {
        let today = Calendar.current.startOfDay(for: now)
        return visible.filter { Calendar.current.startOfDay(for: $0.resolvedDate) == today }
    }

    private var done: Int { todaysTasks.filter(\.isDone).count }

    private var fraction: Double {
        todaysTasks.isEmpty ? 0 : Double(done) / Double(todaysTasks.count)
    }

    private var remainingMinutes: Int {
        todaysTasks.filter { !$0.isDone }.reduce(0) { $0 + Int($1.durationMinutes) }
    }

    /// Same meaning as the goal strip's: a day counts if you finished something on it. Keeping
    /// one definition across every page of the carousel matters more than a stricter rule here
    /// would — a strip that meant "anything done" on one card and "everything done" on the next
    /// would be unreadable.
    private var week: [(date: Date, done: Bool)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let doneDays = Set(visible.filter(\.isDone).map { cal.startOfDay(for: $0.resolvedDate) })
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            return (day, doneDays.contains(day))
        }
    }

    private var summaryLine: String {
        guard !todaysTasks.isEmpty else { return "Nothing scheduled" }
        let base = "\(done) of \(todaysTasks.count) done"
        guard remainingMinutes > 0 else { return base }
        let hours = remainingMinutes / 60
        let minutes = remainingMinutes % 60
        let span = hours > 0 ? (minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h") : "\(minutes)m"
        // "left" alone read as wall-clock time remaining, which this is not: it's the planned
        // effort still outstanding, so ticking off a 45-minute task drops it by 45 minutes
        // whenever you tick it. Naming the unit is the whole fix.
        return "\(base) · \(span) of work left"
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    // TODAY takes the title slot rather than the eyebrow one a goal card uses
                    // for "GOAL". A goal's name has to be the largest thing on its card because
                    // it's the only thing identifying which goal you're looking at; this card
                    // has no such name, so the eyebrow was the only word carrying identity and
                    // it was set in the smallest type on the card.
                    Text("TODAY")
                        .wpTypography(.screenTitle)
                        .tracking(1)
                        .foregroundStyle(.white)
                    Text(now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .wpTypography(.body)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    Text(summaryLine)
                        .wpTypography(.body)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                Spacer()
                ProgressRing(
                    progress: fraction,
                    lineWidth: 7,
                    color: .white,
                    trackColor: .white.opacity(0.3),
                    labelFont: .system(size: 17, weight: .bold),
                    labelColor: .white
                )
                .frame(width: 68, height: 68)
            }
            Rectangle().fill(Color.white.opacity(0.22)).frame(height: 1)
            VStack(spacing: 8) {
                Text("Last 7 days")
                    .wpTypography(.cardTitle)
                    .foregroundStyle(.white.opacity(0.75))
                GoalWeekStrip(days: week)
            }
            .frame(maxWidth: .infinity)
        }
        .wpCard(padding: 20, fill: theme.accentSwatch.color, shadow: .raised)
    }
}

/// Owns its own fresh `@FetchRequest` for exactly one day, established in `init` rather than
/// via a dynamically-reassigned predicate on a shared, already-active `@FetchRequest`. The
/// parent attaches `.id(day)` to this view, so changing days fully tears down and rebuilds it
/// — a genuinely fresh fetch every time, not a mutated one. This is the same fix already
/// proven for the goal-progress-ring staleness and the Week tab staleness earlier: an
/// already-active view's `@FetchRequest` doesn't reliably pick up changes made elsewhere
/// (e.g. a batch-created repeat series, or a delete) until it's rebuilt from scratch.
private struct DayTimelineView: View {
    let day: Date
    let isViewingToday: Bool
    /// The instant every row resolves its state against. Passed in rather than read per-row so
    /// the whole day agrees on one reading, and so this subtree actually re-renders when the
    /// clock moves — see `TodayView.clockTick`.
    let now: Date
    let commitments: FetchedResults<CommitmentEntity>
    /// Tasks mid-undo-window from a pending delete — kept out of Core Data deletion but
    /// hidden here so the row disappears immediately, before the delete actually finalizes.
    let hiddenTaskIDs: Set<NSManagedObjectID>
    let sortMode: TaskSortMode
    var onToggle: (TaskEntity) -> Void
    var onEditTask: (TaskEntity) -> Void
    var onStartFocus: (TaskEntity) -> Void
    var onReschedule: (TaskEntity) -> Void

    @FetchRequest private var dayTasks: FetchedResults<TaskEntity>

    init(
        day: Date,
        isViewingToday: Bool,
        now: Date,
        commitments: FetchedResults<CommitmentEntity>,
        hiddenTaskIDs: Set<NSManagedObjectID>,
        sortMode: TaskSortMode,
        onToggle: @escaping (TaskEntity) -> Void,
        onEditTask: @escaping (TaskEntity) -> Void,
        onStartFocus: @escaping (TaskEntity) -> Void,
        onReschedule: @escaping (TaskEntity) -> Void
    ) {
        self.day = day
        self.isViewingToday = isViewingToday
        self.now = now
        self.commitments = commitments
        self.hiddenTaskIDs = hiddenTaskIDs
        self.sortMode = sortMode
        self.onToggle = onToggle
        self.onEditTask = onEditTask
        self.onStartFocus = onStartFocus
        self.onReschedule = onReschedule
        _dayTasks = FetchRequest(fetchRequest: TaskEntity.fetchRequest(on: day, context: PersistenceController.shared.container.viewContext))
    }

    private var timeline: [TimelineItem] {
        var items = dayTasks
            .filter { !hiddenTaskIDs.contains($0.objectID) }
            .map(TimelineItem.task)
        for commitment in commitments where commitment.occurs(on: day) {
            let (start, end) = commitment.instance(on: day)
            items.append(.block(commitment, start, end))
        }
        let timeSorted = items.sorted { $0.sortDate < $1.sortDate }
        guard sortMode == .priority else { return timeSorted }

        // Fixed schedule blocks stay exactly where the time-sorted order puts them — sorting by
        // priority only reshuffles which TASK fills each non-block slot, so a block never moves
        // just because the sort mode changed.
        let tasksByPriority = timeSorted
            .filter { if case .task = $0 { return true } else { return false } }
            .sorted { lhs, rhs in
                let lRank = lhs.taskEntity?.priorityValue.sortWeight ?? 0
                let rRank = rhs.taskEntity?.priorityValue.sortWeight ?? 0
                if lRank != rRank { return lRank < rRank }
                return lhs.sortDate < rhs.sortDate
            }
        var nextTask = tasksByPriority.makeIterator()
        return timeSorted.map { item in
            if case .block = item { return item }
            return nextTask.next() ?? item
        }
    }

    /// Whatever is running right now is hoisted out of the day's order and pinned to the top,
    /// under its own heading, with everything else — schedule blocks included — left in place
    /// below. Blocks stay where the clock puts them because they're context, not work.
    ///
    /// Built as one flat array rather than two stacks so the promotion is a *reorder* inside a
    /// single `ForEach`. That animates by itself; moving a row between two separate containers
    /// would read as one card vanishing and another appearing, and would need matched geometry
    /// to look like the movement it actually is.
    ///
    /// No section headings when nothing is running: a task is only in progress during its own
    /// scheduled window, which on an ordinary day is a small slice of it, so a standing "In
    /// progress" heading would sit empty most of the time. `nextTaskID` marks the next thing
    /// due in place instead.
    private var sectionedTimeline: [TimelineItem] {
        let ordered = timeline
        guard isViewingToday else { return ordered }
        let running = ordered.filter { $0.taskEntity?.state(at: now) == .inProgress }
        guard !running.isEmpty else { return ordered }
        let rest = ordered.filter { item in
            guard let task = item.taskEntity else { return true }
            return task.state(at: now) != .inProgress
        }
        return [.header("IN PROGRESS")] + running + [.header("TODAY")] + rest
    }

    /// The next thing due — the earliest unfinished task that hasn't ended yet. Marked only when
    /// nothing is running, since an in-progress card at the top already answers "what now?".
    /// It earns its keep because the list is time-ordered: on a morning-heavy day the next thing
    /// to do sits below everything already finished.
    private var nextTaskID: NSManagedObjectID? {
        guard isViewingToday else { return nil }
        let tasks = timeline.compactMap(\.taskEntity)
        guard !tasks.contains(where: { $0.state(at: now) == .inProgress }) else { return nil }
        let outstanding = tasks.filter { !$0.isDone }
        guard !outstanding.isEmpty else { return nil }
        // Prefer something whose slot hasn't passed. Late in the evening nothing qualifies, and
        // the answer to "what now?" is still the earliest thing left undone rather than nothing
        // at all — so fall back to that instead of dropping the marker exactly when the day is
        // getting away from you.
        let upcoming = outstanding.filter { $0.endTime > now }
        let pool = upcoming.isEmpty ? outstanding : upcoming
        return pool.min { $0.resolvedStartTime < $1.resolvedStartTime }?.objectID
    }

    /// A past day has no "+" (see `MainTabView.isViewingPastDay`), so say why rather than
    /// leaving an empty screen that just looks like the button went missing.
    private var emptyStateMessage: String {
        if isViewingToday { return "No tasks yet today. Tap + to add one." }
        let cal = Calendar.current
        if cal.startOfDay(for: day) < cal.startOfDay(for: .now) {
            return "Nothing was scheduled. Past days are a record — they can't be added to."
        }
        return "No tasks scheduled for this day."
    }

    var body: some View {
        Group {
            VStack(spacing: 8) {
                ForEach(sectionedTimeline) { item in
                    row(for: item)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: sectionedTimeline.map(\.id))

            if timeline.isEmpty {
                Text(emptyStateMessage)
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            }
        }
    }

    @ViewBuilder
    private func row(for item: TimelineItem) -> some View {
        switch item {
        case .task(let task):
            TaskRowView(
                task: task,
                onToggle: { onToggle(task) },
                onStartFocus: { onStartFocus(task) },
                onReschedule: { onReschedule(task) },
                isCompletionLocked: !Calendar.current.isDateInToday(task.resolvedDate),
                isNext: task.objectID == nextTaskID
            )
            .onTapGesture { onEditTask(task) }
        case .block(let commitment, let start, let end):
            ScheduleBlockRow(commitment: commitment, start: start, end: end)
        case .header(let title):
            Text(title)
                .wpTypography(.micro)
                .fontWeight(.semibold)
                .tracking(0.6)
                .foregroundStyle(ColorTokens.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 6)
        }
    }
}

struct TodayView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var dateStore: DateNavigationStore

    /// Bumped by MainTabView's own "+" button (docked beside the custom tab bar, not floating
    /// over this screen's content) to request the new-task sheet — see the `.onChange` in
    /// `body`. A plain trigger count rather than a bound Bool so tapping it again while the
    /// sheet is already open (e.g. after switching tabs and back) still re-fires reliably.
    var addTaskTrigger: Int = 0

    /// Always the *real* current day's tasks, regardless of `selectedDate` — auto-complete
    /// and the streak/completion celebration must never act on whatever day is being
    /// browsed, only on today.
    @FetchRequest(fetchRequest: TaskEntity.fetchRequest(on: .now, context: PersistenceController.shared.container.viewContext))
    private var realTodayTasks: FetchedResults<TaskEntity>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CommitmentEntity.createdAt, ascending: true)])
    private var commitments: FetchedResults<CommitmentEntity>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \GoalEntity.createdAt, ascending: false)], animation: .default)
    private var goals: FetchedResults<GoalEntity>

    /// The day currently being browsed — defaults to today, but swiping left/right (or
    /// tapping a day in Week) moves it. Lives in `dateStore` so Week can jump Today to a
    /// specific date.
    private var selectedDate: Date {
        get { dateStore.selectedDate }
        nonmutating set { dateStore.selectedDate = newValue }
    }

    /// How today's task cards are ordered top to bottom — persists across day navigation, not
    /// per-day, since it's a viewing preference rather than something tied to one day's data.
    @State private var sortMode: TaskSortMode = .time

    @State private var activeSheet: ActiveSheet?
    /// SwiftUI's `.sheet(item:)` doesn't reliably support swapping the item directly from
    /// one non-nil case to another (the presentation layer can get stuck mid-transition) —
    /// so replacing the current sheet with a different one always dismisses first and only
    /// presents the next one once that dismissal has actually finished. See `presentSheet`.
    @State private var queuedSheet: ActiveSheet?

    /// Shown right after creating a task with a repeat attached — the moment a mismatch
    /// between the intended and actual end date would be visible, instead of only discoverable
    /// later by browsing Week.
    @State private var repeatCreationSummary: String?

    @State private var goalRefreshTrigger = 0
    /// Which edge new day content should slide in from — set right before changing
    /// `selectedDate` so the transition direction matches the swipe/jump direction.
    @State private var dayTransitionEdge: Edge = .trailing

    /// The delete currently showing its "Undo" toast, if any — see `requestDelete`.
    @State private var pendingDeletion: PendingDeletion?
    /// Every task hidden by an in-flight pending deletion, regardless of which day it's on —
    /// kept separate from `pendingDeletion` (singular) so `DayTimelineView` has a simple set
    /// to filter against without knowing about the toast itself.
    @State private var hiddenTaskIDs: Set<NSManagedObjectID> = []

    private static let undoWindow: TimeInterval = 4

    /// Drives both auto-complete and the screen's sense of time. Task state is derived from the
    /// clock, and a view can't re-render on a clock it never observes: before this, a task's row
    /// only became "in progress" when something *else* rebuilt the screen — a tab switch, a
    /// sheet closing — so sitting on Today and watching, nothing ever happened. 20s keeps a
    /// boundary from being visibly late without waking the screen constantly.
    private let clockTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()
    /// Bumped by `clockTimer`; the only reason this is state is to invalidate the body.
    @State private var clockTick = Date.now

    private var isViewingToday: Bool { Calendar.current.isDateInToday(selectedDate) }


    private var daysFromToday: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: selectedDate)).day ?? 0
    }

    /// Every place that changes `selectedDate` should go through this so the slide direction
    /// and animation stay consistent everywhere (swipe, Week tap, "Today" jump-back).
    private func navigate(to newDate: Date) {
        // Guards against replaying the slide animation for a same-day no-op (e.g. `.now` is a
        // new Date value on every call, down to the second, so without this it would still
        // look like a "change" even when the calendar day hasn't actually moved).
        guard !Calendar.current.isDate(newDate, inSameDayAs: selectedDate) else { return }
        dayTransitionEdge = newDate > selectedDate ? .trailing : .leading
        withAnimation(.easeInOut(duration: 0.32)) {
            selectedDate = newDate
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                HStack {
                    if isViewingToday {
                        Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textSecondary)
                    } else if abs(daysFromToday) > 2 {
                        Button {
                            navigate(to: .now)
                        } label: {
                            Text("Jump to Today")
                                .wpTypography(.body)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(theme.accentSwatch.color)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    sortMenuButton
                }
                .padding(.top, -8)

                goalSection

                DayTimelineView(
                    day: selectedDate,
                    isViewingToday: isViewingToday,
                    now: clockTick,
                    commitments: commitments,
                    hiddenTaskIDs: hiddenTaskIDs,
                    sortMode: sortMode,
                    onToggle: { task in toggleTask(task) },
                    onEditTask: { task in presentSheet(.editTask(task)) },
                    onStartFocus: { task in presentSheet(.pomodoro(task)) },
                    onReschedule: { task in presentSheet(.editTask(task)) }
                )
                .id(selectedDate)
                .transition(.asymmetric(
                    insertion: .move(edge: dayTransitionEdge).combined(with: .opacity),
                    removal: .move(edge: dayTransitionEdge == .trailing ? .leading : .trailing).combined(with: .opacity)
                ))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
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
                    navigate(to: cal.date(byAdding: .day, value: horizontal < 0 ? 1 : -1, to: selectedDate) ?? selectedDate)
                }
        )
        .sheet(item: $activeSheet, onDismiss: handleSheetDismissed) { sheet in
            switch sheet {
            case .addTask:
                NewTaskView(
                    defaultDate: selectedDate,
                    goal: goals.first,
                    onSave: handleSave
                )
            case .editTask(let task):
                NewTaskView(
                    existingTask: task,
                    defaultDate: task.resolvedDate,
                    onSave: handleSave,
                    onDelete: { requestDelete(task) },
                    onDeleteSeries: { deleteSeries(from: task) },
                    onDuplicate: { draft in handleNewDraft(draft) }
                )
            case .goalCreate:
                GoalCreateView(onCreated: { _ in })
            case .adhocBump(let info):
                AdhocBumpView(
                    headline: "New task needs a slot",
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
            case .completion(let info):
                CompletionView(
                    streak: info.streak,
                    tasksDone: info.tasksDone,
                    tasksTotal: info.tasksTotal,
                    progressBefore: info.progressBefore,
                    progressAfter: info.progressAfter
                )
            case .pomodoro(let task):
                NavigationStack {
                    PomodoroView(focusTitle: task.title)
                }
            }
        }
        .alert("Repeat", isPresented: Binding(get: { repeatCreationSummary != nil }, set: { if !$0 { repeatCreationSummary = nil } })) {
            Button("OK") { repeatCreationSummary = nil }
        } message: {
            Text(repeatCreationSummary ?? "")
        }
        .onReceive(clockTimer) { tick in
            withAnimation(.easeInOut(duration: 0.3)) { clockTick = tick }
            runAutoComplete()
        }
        .onChange(of: addTaskTrigger) { _, _ in presentSheet(.addTask) }

        if let pendingDeletion {
            undoToast(pendingDeletion)
                // Fixed clearance for the custom tab bar (MainTabView.CustomTabBar) — a
                // `.safeAreaInset` on the ancestor ZStack does NOT propagate through this view's
                // `NavigationStack` boundary the way it would for a plain sibling view, so this
                // can't just be a small offset relying on inherited safe area like it could when
                // the native TabView provided it automatically. Verified empirically: an
                // inherited safe area here silently failed to clear the bar at all.
                .padding(.bottom, 100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        }
        .animation(.easeInOut(duration: 0.22), value: pendingDeletion != nil)
    }

    private func undoToast(_ pending: PendingDeletion) -> some View {
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

    /// Use this instead of assigning `activeSheet` directly whenever the target might not be
    /// nil — see the doc comment on `queuedSheet` for why.
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            Text(isViewingToday ? "Today" : selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .wpTypography(.appTitle)
                .foregroundStyle(ColorTokens.textPrimary)
            Spacer()
            Button {
                theme.appearanceMode = theme.appearanceMode == .dark ? .light : .dark
            } label: {
                Image(systemName: theme.appearanceMode == .dark ? "moon.fill" : "sun.max.fill")
                    .foregroundStyle(ColorTokens.textSecondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle dark mode")
        }
        .padding(.top, 8)
    }

    /// Folded into the existing weekday-label row (trailing end) rather than a row of its own,
    /// so switching sort modes doesn't push the goal carousel and task list down the screen.
    /// Fixed schedule blocks never move regardless of `sortMode` — see the pinned-position
    /// comment on `timeline` — so this only ever reorders the task cards themselves.
    private var sortMenuButton: some View {
        Menu {
            ForEach(TaskSortMode.allCases, id: \.self) { mode in
                Button {
                    // Task rows keep a stable identity (TimelineItem.id) across a sort-mode
                    // change, so wrapping this in withAnimation lets SwiftUI slide each row to
                    // its new position instead of the list snapping into the new order.
                    withAnimation(.easeInOut(duration: 0.3)) {
                        sortMode = mode
                    }
                } label: {
                    Label(mode.label, systemImage: mode.icon)
                    if sortMode == mode {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                // Direct Image, not Label — `.contentTransition` needs to target the symbol
                // itself to morph it; applied to a compound Label it has no visible effect.
                Image(systemName: sortMode.icon)
                    .contentTransition(.symbolEffect(.replace))
                Text("Sort: \(sortMode.label)")
                    .contentTransition(.opacity)
            }
            .wpTypography(.micro)
            .foregroundStyle(ColorTokens.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(ColorTokens.surface1)
            .clipShape(Capsule())
        }
    }

    private static let goalBannerHeight: CGFloat = 264

    /// The page margin every screen's scroll content uses. Named here because the carousel has
    /// to cancel it and re-apply it one level down.
    static let pageMargin: CGFloat = 20

    /// One page of the goal carousel: the page margin lives here rather than on the TabView, so
    /// each card sits inset from the clip boundary with room for its shadow. The bottom inset
    /// lifts the card clear of the paging dots.
    private func carouselPage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, Self.pageMargin)
            .padding(.bottom, 24)
    }

    /// Always ends with an "Add another goal" page — swiping to it is the one, always-
    /// reachable place to start a new goal, whether you have zero goals or several already.
    private var goalSection: some View {
        TabView {
            carouselPage {
                TodaySummaryCard(now: clockTick, hiddenTaskIDs: hiddenTaskIDs)
            }

            ForEach(goals) { goal in
                carouselPage {
                    NavigationLink {
                        GoalDetailView(goal: goal)
                    } label: {
                        goalCard(goal)
                    }
                    .buttonStyle(.plain)
                }
            }

            carouselPage {
                Button { presentSheet(.goalCreate) } label: {
                    addGoalCard
                }
                .buttonStyle(.plain)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(height: Self.goalBannerHeight)
        // Full-bleed, then the margin is re-applied per page in `carouselPage`.
        //
        // A paging TabView clips to its own bounds. Inset by the page margin it was exactly as
        // wide as the card inside it, so the card's shadow — which has to extend past the card
        // to be a shadow at all — was sliced off flush with the card's edge, leaving a hard
        // vertical line down both sides. Capping the blur against the *scroll view's* margin
        // didn't help, because this is a second, tighter clip inside that one. Widening the
        // carousel to the screen edge puts the margin inside the clip bounds, where the shadow
        // can fall on actual page background. It also makes the swipe feel right: a carousel
        // should page edge to edge, not inside a 40pt-narrower window.
        .padding(.horizontal, -Self.pageMargin)
    }

    private func goalCard(_ goal: GoalEntity) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GOAL")
                        .wpTypography(.micro)
                        .foregroundStyle(.white.opacity(0.75))
                        .tracking(0.6)
                    Text(goal.name ?? "")
                        .wpTypography(.screenTitle)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Day \(goal.currentDayNumber) of \(goal.totalDayCount) · \(goal.daysRemaining) days left")
                        .wpTypography(.body)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                ProgressRing(
                    progress: goal.completionFraction,
                    lineWidth: 7,
                    color: .white,
                    trackColor: .white.opacity(0.3),
                    labelFont: .system(size: 17, weight: .bold),
                    labelColor: .white
                )
                .id(goalRefreshTrigger)
                .frame(width: 68, height: 68)
            }
            Rectangle().fill(Color.white.opacity(0.22)).frame(height: 1)
            VStack(spacing: 8) {
                Text("Last 7 days")
                    .wpTypography(.cardTitle)
                    .foregroundStyle(.white.opacity(0.75))
                GoalWeekStrip(days: goal.recentCompletion())
                    .id(goalRefreshTrigger)
            }
            .frame(maxWidth: .infinity)
        }
        .wpCard(padding: 20, fill: theme.accentSwatch.color, shadow: .raised)
    }

    /// Mirrors `goalCard`'s shape (a leading label + a 68×68 circular element, plus the same
    /// week strip row) so both pages in the carousel render at the same height — and so this
    /// empty state previews what the strip looks like instead of leaving blank space.
    private var addGoalCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                Text("New goal")
                    .wpTypography(.screenTitle)
                    .foregroundStyle(.white)
                Spacer()
                ZStack {
                    Circle().stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 68, height: 68)
            }
            Rectangle().fill(Color.white.opacity(0.22)).frame(height: 1)
            VStack(spacing: 8) {
                Text("Last 7 days")
                    .wpTypography(.cardTitle)
                    .foregroundStyle(.white.opacity(0.75))
                GoalWeekStrip(days: Self.emptyWeekPreview)
            }
            .frame(maxWidth: .infinity)
        }
        .wpCard(padding: 20, fill: theme.accentSwatch.color, shadow: .raised)
    }

    private static var emptyWeekPreview: [(date: Date, done: Bool)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<7).reversed().map { offset in
            (cal.date(byAdding: .day, value: -offset, to: today)!, false)
        }
    }

    // MARK: - Actions

    private func handleSave(_ draft: TaskDraft, existing: TaskEntity?) {
        if let existing {
            let startUnchanged = abs(draft.startTime.timeIntervalSince(existing.resolvedStartTime)) < 60
            let isDurationIncrease = startUnchanged && draft.durationMinutes > Int(existing.durationMinutes)

            let resolution: EditResolution = isDurationIncrease
                ? ScheduleEngine.resolveDurationIncrease(task: existing, newDurationMinutes: draft.durationMinutes, context: context)
                : ScheduleEngine.resolveTimeMove(task: existing, newStart: draft.startTime, newDurationMinutes: draft.durationMinutes, context: context)
            applyResolution(resolution, draft: draft, task: existing)
            return
        }
        handleNewDraft(draft)
    }

    private func applyResolution(_ resolution: EditResolution, draft: TaskDraft, task: TaskEntity) {
        switch resolution {
        case .none:
            applyEdit(draft, to: task)
            activeSheet = nil
        case .cascade(let shifts):
            presentSheet(.cascadeConfirm(CascadeConfirmInfo(edit: PendingEdit(draft: draft, task: task), shifts: shifts)))
        case .hardBump(let candidates, let blockedBy):
            presentSheet(.editBump(EditBumpInfo(edit: PendingEdit(draft: draft, task: task), candidates: candidates, blockedBy: blockedBy)))
        }
    }

    /// Collision check for a brand-new (not-yet-persisted) task, which might land on any
    /// day — used both for the "+" button (always today) and duplicating a task to another day.
    /// Checks other tasks *and* anything immovable (fixed commitments, sleep).
    private func handleNewDraft(_ draft: TaskDraft) {
        let resolution = ScheduleEngine.resolveNewTask(start: draft.startTime, end: draft.endTime, on: draft.date, context: context)
        switch resolution {
        case .none:
            persist(draft)
            activeSheet = nil
        case .appendable(let appendStart, let candidates, let blockedBy):
            presentSheet(.adhocBump(NewTaskBumpInfo(draft: draft, collidingTasks: candidates, blockedBy: blockedBy, appendStart: appendStart)))
        case .hardBump(let candidates, let blockedBy):
            presentSheet(.adhocBump(NewTaskBumpInfo(draft: draft, collidingTasks: candidates, blockedBy: blockedBy, appendStart: nil)))
        }
    }

    private func appended(_ draft: TaskDraft, at start: Date) -> TaskDraft {
        var copy = draft
        copy.startTime = start
        return copy
    }

    private func newDraftMessage(for info: NewTaskBumpInfo) -> String {
        "\u{201C}\(info.draft.title)\u{201D} overlaps \(info.blockedBy)."
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

    /// Soft-deletes this occurrence and every future one in the same repeat series — same
    /// undo window as a single delete, leaving past occurrences (and their completion
    /// history) untouched.
    private func deleteSeries(from task: TaskEntity) {
        guard let seriesID = task.seriesID else {
            requestDelete(task)
            return
        }
        let request = TaskEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "seriesID == %@ AND date >= %@",
            seriesID as CVarArg,
            Calendar.current.startOfDay(for: task.resolvedDate) as NSDate
        )
        let matches = (try? context.fetch(request)) ?? []
        guard !matches.isEmpty else { return }
        requestDelete(tasks: matches, title: "\(matches.count) task\(matches.count == 1 ? "" : "s")")
    }

    /// Hides the task and starts its undo window instead of deleting immediately. Only one
    /// pending deletion is tracked at a time — starting a new one finalizes whichever was
    /// already pending, the same "next toast replaces the last" behavior most apps use.
    private func requestDelete(_ task: TaskEntity) {
        requestDelete(tasks: [task], title: "\u{201C}\(task.title ?? "Task")\u{201D}")
    }

    /// Shared by both the single-task delete and the whole-series delete — the mechanics
    /// (hide, start the undo window, cancel notifications up front so they don't fire during
    /// it) don't depend on how many tasks are involved.
    private func requestDelete(tasks: [TaskEntity], title: String) {
        if let previous = pendingDeletion {
            finalizeDeletion(previous)
        }
        for task in tasks {
            if let id = task.id { NotificationManager.cancelReminder(taskID: id) }
        }
        hiddenTaskIDs.formUnion(tasks.map(\.objectID))
        let pending = PendingDeletion(tasks: tasks, title: title)
        pendingDeletion = pending
        let token = pending.id
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.undoWindow) {
            guard pendingDeletion?.id == token else { return }
            finalizeDeletion(pending)
        }
    }

    private func finalizeDeletion(_ pending: PendingDeletion) {
        hiddenTaskIDs.subtract(pending.tasks.map(\.objectID))
        if pendingDeletion?.id == pending.id {
            pendingDeletion = nil
        }
        for task in pending.tasks {
            // Logged here rather than in `requestDelete` on purpose: this is the point the
            // delete becomes real. A delete the user undid inside the toast window is a
            // decision they reversed, and recording it would count a failure that didn't happen.
            TaskEventLog.recordAbandonmentIfNeeded(task: task, in: context)
            context.delete(task)
        }
        try? context.save()
    }

    private func undoDelete() {
        guard let pending = pendingDeletion else { return }
        hiddenTaskIDs.subtract(pending.tasks.map(\.objectID))
        pendingDeletion = nil
        for task in pending.tasks {
            rescheduleReminder(for: task)
        }
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

    private func bumped(_ draft: TaskDraft) -> TaskDraft {
        var copy = draft
        let cal = Calendar.current
        copy.date = cal.date(byAdding: .day, value: 1, to: draft.date) ?? draft.date
        copy.startTime = cal.date(byAdding: .day, value: 1, to: draft.startTime) ?? draft.startTime
        return copy
    }

    private func bumpToTomorrow(_ task: TaskEntity) {
        let cal = Calendar.current
        task.date = cal.date(byAdding: .day, value: 1, to: task.resolvedDate) ?? task.date
        task.startTime = cal.date(byAdding: .day, value: 1, to: task.resolvedStartTime) ?? task.startTime
        try? context.save()
        rescheduleReminder(for: task)
    }

    private func toggleTask(_ task: TaskEntity) {
        // Only today's own tasks are completable — past tasks must be rescheduled instead of
        // completed late, and future ones aren't due yet.
        guard Calendar.current.isDateInToday(task.resolvedDate) else { return }
        let goal = task.goal
        let progressBefore = goal?.completionFraction ?? 0
        task.toggleDone()
        try? context.save()
        // Completing/un-completing a task changes a goal's completionFraction, but that's a
        // *related* object's computed value, not an attribute of the goal itself — Core Data
        // won't fire a change notification on the goal, and the goal carousel's TabView(.page)
        // pages can keep showing stale progress until something else forces a full rebuild
        // (a theme toggle, leaving and returning). Bumping this forces that rebuild right here.
        goalRefreshTrigger += 1
        if task.isDone {
            checkDayCompletion(progressBefore: progressBefore, goal: goal)
        }
        rescheduleReminder(for: task)
    }

    private func checkDayCompletion(progressBefore: Double, goal: GoalEntity?) {
        let realTasks = Array(realTodayTasks)
        guard !realTasks.isEmpty, realTasks.allSatisfy(\.isDone) else { return }
        let streak = goal?.dayStreak ?? 1
        let info = CompletionInfo(
            streak: streak,
            tasksDone: realTasks.filter(\.isDone).count,
            tasksTotal: realTasks.count,
            progressBefore: goal != nil ? progressBefore : nil,
            progressAfter: goal?.completionFraction
        )
        presentSheet(.completion(info))
        if theme.notificationsEnabled {
            NotificationManager.scheduleStreakNudge(streak: streak)
        }
    }

    /// Cancels any pending reminder for the task, then re-schedules one if it's still
    /// pending, in the future, and notifications are on.
    private func rescheduleReminder(for task: TaskEntity) {
        guard let id = task.id else { return }
        NotificationManager.cancelReminder(taskID: id)
        guard theme.notificationsEnabled, !task.isDone else { return }
        NotificationManager.scheduleReminder(taskID: id, title: task.title ?? "Task", startTime: task.resolvedStartTime)
    }

    private func runAutoComplete() {
        guard theme.completionMode == .autoByTime else { return }
        var didChange = false
        for task in realTodayTasks where !task.isDone && Date.now >= task.endTime {
            task.markAutoCompleted()
            didChange = true
        }
        if didChange { try? context.save() }
    }
}
