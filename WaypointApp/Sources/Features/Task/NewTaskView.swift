import SwiftUI

struct NewTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var theme: ThemeManager

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \GoalEntity.createdAt, ascending: false)])
    private var allGoals: FetchedResults<GoalEntity>

    var existingTask: TaskEntity?
    var defaultDate: Date = .now
    var goal: GoalEntity?
    var onSave: (TaskDraft, TaskEntity?) -> Void
    var onDelete: (() -> Void)?
    /// Only offered when `existingTask` is part of a repeat series — deletes this occurrence
    /// and every future one in the same series, leaving past occurrences (and their history)
    /// untouched.
    var onDeleteSeries: (() -> Void)?
    var onDuplicate: ((TaskDraft) -> Void)?
    var onRequestPaywall: () -> Void = {}

    @State private var title: String
    @State private var selectedDay: Date
    @State private var startTime: Date
    @State private var durationMinutes: Int
    @State private var priority: Priority
    @State private var selectedGoal: GoalEntity?
    @State private var notes: String
    @State private var showingNotesEditor = false
    @State private var showingGoalCreate = false
    @State private var showingGoalPicker = false
    /// Set by the goal picker's "Create new goal" row right before it dismisses itself —
    /// only acted on once that dismissal has actually finished, same reasoning as
    /// `pendingRepeatResult` below (chaining straight into a second sheet mid-dismissal is
    /// unreliable).
    @State private var pendingGoalCreateRequest = false
    @State private var showingTimeSheet = false
    @State private var showingDurationSheet = false
    @State private var showingDeleteConfirm = false
    /// Set by the delete sheet right before it dismisses itself, then run from that sheet's
    /// `onDismiss` — deleting (and dismissing this whole Task detail sheet) while the delete
    /// confirmation sheet is still animating out is the same unreliable double-sheet timing
    /// as everywhere else in this codebase that chains sheets.
    @State private var pendingDeleteAction: (() -> Void)?
    @State private var showingRepeatSheet = false
    @State private var repeatSummary: String?
    @State private var pendingRepeatResult: (created: Int, skipped: Int, lastDate: Date?)?
    /// Only used at creation time — see the "Repeat" section below. Editing an existing task
    /// still uses the separate "Repeat on other days" sheet.
    @State private var repeatDays: Set<String> = []
    @State private var repeatWeeks = 4
    /// Guards `applySmartDefaultsIfNeeded` so it only ever adjusts the initial guess once,
    /// even if `onAppear` were to somehow fire again — it must never clobber edits the user
    /// has since made.
    @State private var didApplySmartDefaults = false
    /// Guards the goal-linked repeat-length default the same way — only sets `repeatWeeks`
    /// once, the first time repeat days are picked while a goal is already selected, so it
    /// never overwrites a value the user has since chosen deliberately.
    @State private var didApplySmartRepeatWeeks = false

    init(
        existingTask: TaskEntity? = nil,
        defaultDate: Date = .now,
        goal: GoalEntity? = nil,
        onSave: @escaping (TaskDraft, TaskEntity?) -> Void,
        onDelete: (() -> Void)? = nil,
        onDeleteSeries: (() -> Void)? = nil,
        onDuplicate: ((TaskDraft) -> Void)? = nil,
        onRequestPaywall: @escaping () -> Void = {}
    ) {
        self.existingTask = existingTask
        self.defaultDate = defaultDate
        self.goal = goal
        self.onSave = onSave
        self.onDelete = onDelete
        self.onDeleteSeries = onDeleteSeries
        self.onDuplicate = onDuplicate
        self.onRequestPaywall = onRequestPaywall
        _title = State(initialValue: existingTask?.title ?? "")
        _selectedDay = State(initialValue: existingTask?.resolvedDate ?? defaultDate)
        _startTime = State(initialValue: existingTask?.startTime ?? Self.nextRoundHour(from: defaultDate))
        _durationMinutes = State(initialValue: Int(existingTask?.durationMinutes ?? 60))
        _priority = State(initialValue: existingTask?.priorityValue ?? .medium)
        _selectedGoal = State(initialValue: existingTask?.goal ?? goal)
        _notes = State(initialValue: existingTask?.notes ?? "")
    }

    private static func nextRoundHour(from date: Date) -> Date {
        let cal = Calendar.current
        let rounded = cal.date(bySetting: .minute, value: 0, of: date) ?? date
        return cal.date(byAdding: .hour, value: 1, to: rounded) ?? date
    }

    /// The wheel-style hour/minute picker returns a full `Date`, and its calendar day can
    /// silently roll over (e.g. dragging the minute wheel past midnight) independently of
    /// the day this task is actually filed under. Only the hour/minute are meaningful from
    /// `timeOfDay` — the day always comes from `day` — same pattern as
    /// `CommitmentEntity.instance(on:)` and `SleepSettings.range(startingOn:)`.
    private static func combining(day: Date, timeOfDay: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: timeOfDay)
        let dayStart = cal.startOfDay(for: day)
        return cal.date(byAdding: comps, to: dayStart) ?? day
    }

    /// New tasks default to the earliest open slot on the day instead of an arbitrary
    /// next-round-hour guess — duration caps at 60 min, or less if that's all the gap has
    /// room for. Only applies to brand-new tasks; editing an existing one always keeps its
    /// own time untouched.
    private func applySmartDefaultsIfNeeded() {
        guard existingTask == nil, !didApplySmartDefaults else { return }
        didApplySmartDefaults = true
        let notBefore = Calendar.current.isDateInToday(selectedDay) ? Date.now : .distantPast
        guard let slot = ScheduleEngine.earliestOpenSlot(on: selectedDay, notBefore: notBefore, context: context) else { return }

        // Round the raw gap start up to a clean mark (e.g. 12:15 instead of 12:14) — rounding
        // up only ever shrinks the gap, never creates a new collision, so the duration cap
        // below accounts for exactly how many minutes rounding ate into it.
        let roundedStart = Self.roundUpToNearestFiveMinutes(slot.start)
        let roundingDelta = Int(roundedStart.timeIntervalSince(slot.start) / 60)
        let remainingMinutes = slot.availableMinutes - roundingDelta
        guard remainingMinutes > 0 else { return } // rounding ate the whole gap — keep the generic default

        startTime = roundedStart
        durationMinutes = min(60, remainingMinutes)
    }

    private static func roundUpToNearestFiveMinutes(_ date: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let minute = comps.minute else { return date }
        let remainder = minute % 5
        comps.minute = remainder == 0 ? minute : minute - remainder + 5
        comps.second = 0
        return cal.date(from: comps) ?? date
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TextField("Task name", text: $title)
                        .wpTypography(.cardTitle)
                        .padding(14)
                        .background(ColorTokens.surface1)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if existingTask != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Date")
                                .wpTypography(.micro)
                                .foregroundStyle(ColorTokens.textSecondary)
                            DatePicker("", selection: $selectedDay, displayedComponents: .date)
                                .labelsHidden()
                                .padding(.horizontal, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                .background(ColorTokens.surface1)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Time")
                                .wpTypography(.micro)
                                .foregroundStyle(ColorTokens.textSecondary)
                            Button {
                                showingTimeSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "clock")
                                    Text(startTime.formatted(.dateTime.hour().minute()))
                                    Spacer()
                                }
                                .wpTypography(.body)
                                .foregroundStyle(ColorTokens.textPrimary)
                                .padding(14)
                                .background(ColorTokens.surface1)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Duration")
                                .wpTypography(.micro)
                                .foregroundStyle(ColorTokens.textSecondary)
                            Button {
                                showingDurationSheet = true
                            } label: {
                                HStack {
                                    Text("\(durationMinutes) min")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11))
                                }
                                .wpTypography(.body)
                                .foregroundStyle(ColorTokens.textPrimary)
                                .padding(14)
                                .background(ColorTokens.surface1)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Priority")
                            .wpTypography(.micro)
                            .foregroundStyle(ColorTokens.textSecondary)
                        HStack(spacing: 8) {
                            ForEach(Priority.allCases) { p in
                                Button {
                                    priority = p
                                } label: {
                                    Text(p.label)
                                        .wpTypography(.body)
                                        .foregroundStyle(priority == p ? p.tintColor : ColorTokens.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(priority == p ? p.tintColor : ColorTokens.border, lineWidth: priority == p ? 1.6 : 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sensoryFeedback(.selection, trigger: priority)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Goal")
                            .wpTypography(.micro)
                            .foregroundStyle(ColorTokens.textSecondary)
                        Button {
                            showingGoalPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "target")
                                Text(selectedGoal?.name ?? "No goal")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                            }
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textPrimary)
                            .padding(14)
                            .background(ColorTokens.surface1)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if existingTask == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Repeat")
                                .wpTypography(.micro)
                                .foregroundStyle(ColorTokens.textSecondary)
                            HStack {
                                ForEach(CommitmentEntity.weekdaySymbols, id: \.self) { day in
                                    let selected = repeatDays.contains(day)
                                    Text(String(day.prefix(1)))
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(width: 32, height: 32)
                                        .background(selected ? ColorTokens.textPrimary : ColorTokens.surface1)
                                        .foregroundStyle(selected ? ColorTokens.surface0 : ColorTokens.textSecondary)
                                        .clipShape(Circle())
                                        .onTapGesture {
                                            if selected { repeatDays.remove(day) } else { repeatDays.insert(day) }
                                        }
                                }
                            }
                            if !repeatDays.isEmpty {
                                Stepper("For \(repeatWeeks) week\(repeatWeeks == 1 ? "" : "s")", value: $repeatWeeks, in: 1...52)
                                    .wpTypography(.body)
                                    .foregroundStyle(ColorTokens.textPrimary)
                            }
                        }
                    }

                    Button {
                        guard theme.isPro else { return }
                        showingNotesEditor = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            Text(notes.isEmpty ? "Add notes" : "Edit notes")
                            Spacer()
                            if !theme.isPro { ProBadge() }
                        }
                        .wpTypography(.cardTitle)
                        .foregroundStyle(ColorTokens.textInProgress)
                        .padding(14)
                        .background(ColorTokens.inProgressTint)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .opacity(theme.isPro ? 1 : 0.6)
                    }
                    .buttonStyle(.plain)

                    if let existingTask {
                        VStack(spacing: 10) {
                            if let onDuplicate {
                                Button {
                                    // Not dismissing here on purpose: duplicating might need
                                    // to hand off to a bump sheet if tomorrow collides, and
                                    // the parent owns that decision — see the Save button.
                                    onDuplicate(TaskReplicator.draftForTomorrow(existingTask))
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.square.on.square")
                                        Text("Duplicate to tomorrow")
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.wpSecondary)
                            }
                            Button {
                                showingRepeatSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "repeat")
                                    Text("Repeat on other days")
                                    Spacer()
                                }
                            }
                            .buttonStyle(.wpSecondary)
                        }
                        .padding(.top, 4)

                        if onDelete != nil {
                            Button(role: .destructive) {
                                showingDeleteConfirm = true
                            } label: {
                                Text("Delete task")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .padding(.top, 6)
                        }
                    }
                }
                .padding(20)
            }
            .background(ColorTokens.surface0.ignoresSafeArea())
            .onAppear { applySmartDefaultsIfNeeded() }
            .onChange(of: repeatDays) { old, new in
                // The moment repeat is first turned on, default its length to reach the
                // task's goal (if any) instead of leaving whatever the stepper happened to
                // be at — this is what would have caught "8 weeks" vs. the 10 actually
                // needed to reach a goal 68 days out. Only fires once, and only if a goal is
                // already selected at that moment; picking a goal afterward doesn't
                // retroactively change a length the user may have already adjusted.
                guard old.isEmpty, !new.isEmpty, !didApplySmartRepeatWeeks, let selectedGoal else { return }
                didApplySmartRepeatWeeks = true
                repeatWeeks = TaskReplicator.weeksUntil(selectedGoal.resolvedTargetDate, from: selectedDay)
            }
            .navigationTitle(existingTask == nil ? "New task" : "Task detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let draft = TaskDraft(
                            title: title.isEmpty ? "Untitled task" : title,
                            date: selectedDay,
                            startTime: Self.combining(day: selectedDay, timeOfDay: startTime),
                            durationMinutes: durationMinutes,
                            priority: priority,
                            notes: notes.isEmpty ? nil : notes,
                            goal: selectedGoal,
                            repeatWeekdays: repeatDays,
                            repeatWeeks: repeatWeeks
                        )
                        // No dismiss() here — onSave may need to hand off to a follow-up
                        // sheet (ad-hoc bump / cascade confirm) instead of just closing, and
                        // only the parent knows which. It's responsible for dismissing.
                        onSave(draft, existingTask)
                    }
                    .tint(theme.accentSwatch.color)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingNotesEditor) {
                NotesEditorSheet(notes: $notes)
            }
            .sheet(isPresented: $showingGoalCreate) {
                GoalCreateView(
                    onCreated: { newGoal in selectedGoal = newGoal },
                    onRequestPaywall: onRequestPaywall
                )
            }
            .sheet(isPresented: $showingTimeSheet) {
                TimePickerSheet(time: $startTime)
            }
            .sheet(isPresented: $showingDurationSheet) {
                DurationPickerSheet(durationMinutes: $durationMinutes)
            }
            .sheet(isPresented: $showingGoalPicker, onDismiss: {
                guard pendingGoalCreateRequest else { return }
                pendingGoalCreateRequest = false
                showingGoalCreate = true
            }) {
                GoalPickerSheet(
                    goals: allGoals,
                    selectedGoal: $selectedGoal,
                    onCreateNew: { pendingGoalCreateRequest = true }
                )
            }
            .sheet(isPresented: $showingDeleteConfirm, onDismiss: {
                guard let pendingDeleteAction else { return }
                self.pendingDeleteAction = nil
                pendingDeleteAction()
            }) {
                DeleteConfirmSheet(
                    taskTitle: existingTask?.title ?? "this task",
                    isSeries: existingTask?.seriesID != nil && onDeleteSeries != nil,
                    onConfirmOne: { pendingDeleteAction = { onDelete?(); dismiss() } },
                    onConfirmSeries: onDeleteSeries.map { seriesAction in
                        { pendingDeleteAction = { seriesAction(); dismiss() } }
                    }
                )
            }
            .sheet(isPresented: $showingRepeatSheet, onDismiss: {
                // Wait until the Repeat sheet has actually finished dismissing before
                // showing the alert — presenting it in the same instant as the dismiss
                // (e.g. from RepeatSheet's own button action) can leave it stuck, the same
                // way chaining two sheets directly does.
                guard let pendingRepeatResult else { return }
                self.pendingRepeatResult = nil
                repeatSummary = TaskReplicator.summaryText(
                    created: pendingRepeatResult.created,
                    skipped: pendingRepeatResult.skipped,
                    lastDate: pendingRepeatResult.lastDate
                )
            }) {
                if let existingTask {
                    RepeatSheet(task: existingTask) { created, skipped, lastDate in
                        pendingRepeatResult = (created, skipped, lastDate)
                    }
                }
            }
            .alert("Repeat", isPresented: Binding(get: { repeatSummary != nil }, set: { if !$0 { repeatSummary = nil } })) {
                Button("OK") { repeatSummary = nil }
            } message: {
                Text(repeatSummary ?? "")
            }
        }
    }

}

private struct TimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager
    @Binding var time: Date
    @State private var draftTime: Date

    init(time: Binding<Date>) {
        _time = time
        _draftTime = State(initialValue: time.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("", selection: $draftTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding(.top, 8)
                Spacer()
            }
            .padding(20)
            .background(ColorTokens.surface0.ignoresSafeArea())
            .navigationTitle("Set time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        time = draftTime
                        dismiss()
                    }
                    .tint(theme.accentSwatch.color)
                }
            }
        }
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.hidden)
    }
}

private struct DurationPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager
    @Binding var durationMinutes: Int

    private static let presets = [15, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Duration")
                .wpTypography(.screenTitle)
                .foregroundStyle(ColorTokens.textPrimary)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Self.presets.prefix(3), id: \.self) { minutes in
                        pill(minutes)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(Self.presets.suffix(3), id: \.self) { minutes in
                        pill(minutes)
                    }
                }
            }
        }
        .padding(22)
        .background(ColorTokens.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(16)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        .presentationBackground(ColorTokens.surface0)
    }

    private func pill(_ minutes: Int) -> some View {
        let selected = durationMinutes == minutes
        return Button {
            durationMinutes = minutes
            dismiss()
        } label: {
            Text("\(minutes) min")
                .wpTypography(.body)
                .foregroundStyle(selected ? theme.accentSwatch.color : ColorTokens.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(selected ? theme.accentSwatch.color : ColorTokens.border, lineWidth: selected ? 1.6 : 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct GoalPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let goals: FetchedResults<GoalEntity>
    @Binding var selectedGoal: GoalEntity?
    var onCreateNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Goal")
                .wpTypography(.screenTitle)
                .foregroundStyle(ColorTokens.textPrimary)

            VStack(spacing: 8) {
                goalRow(nil, title: "No goal", icon: "circle.slash")
                ForEach(goals) { goal in
                    goalRow(goal, title: goal.name ?? "Untitled goal", icon: "target")
                }
            }

            Button {
                onCreateNew()
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Create new goal")
                    Spacer()
                }
            }
            .buttonStyle(.wpSecondary)
        }
        .padding(22)
        .background(ColorTokens.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(16)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(ColorTokens.surface0)
    }

    private func goalRow(_ goal: GoalEntity?, title: String, icon: String) -> some View {
        let isSelected = selectedGoal?.objectID == goal?.objectID
        return Button {
            selectedGoal = goal
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(isSelected ? ColorTokens.textPrimary : ColorTokens.textSecondary)
                Text(title)
                    .wpTypography(.cardTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(ColorTokens.textPrimary)
                }
            }
            .padding(14)
            .background(isSelected ? ColorTokens.surface0 : ColorTokens.surface1)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? ColorTokens.textPrimary : ColorTokens.border, lineWidth: isSelected ? 1.6 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct DeleteConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss

    let taskTitle: String
    let isSeries: Bool
    var onConfirmOne: () -> Void
    var onConfirmSeries: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(ColorTokens.warningTint)
                    .frame(width: 52, height: 52)
                Image(systemName: "trash")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ColorTokens.textWarning)
            }

            VStack(spacing: 6) {
                Text("Delete this task?")
                    .wpTypography(.cardTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                Text("\u{201C}\(taskTitle)\u{201D} will be removed. This can\u{2019}t be undone.")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 10) {
                if isSeries, let onConfirmSeries {
                    Button {
                        onConfirmOne()
                        dismiss()
                    } label: {
                        Text("Delete just this one")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: ColorTokens.warning, foreground: .white))

                    Button {
                        onConfirmSeries()
                        dismiss()
                    } label: {
                        Text("Delete this and all future occurrences")
                    }
                    .buttonStyle(.wpSecondary)
                } else {
                    Button {
                        onConfirmOne()
                        dismiss()
                    } label: {
                        Text("Delete task")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: ColorTokens.warning, foreground: .white))
                }

                Button("Cancel") { dismiss() }
                    .buttonStyle(.wpSecondary)
            }
        }
        .padding(22)
        .background(ColorTokens.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(16)
        .presentationDetents([isSeries ? .height(400) : .height(320)])
        .presentationDragIndicator(.visible)
        .presentationBackground(ColorTokens.surface0)
    }
}

private struct RepeatSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager

    let task: TaskEntity
    var onDone: (_ created: Int, _ skipped: Int, _ lastDate: Date?) -> Void

    @State private var selectedDays: Set<String>
    @State private var weeks: Int

    init(task: TaskEntity, onDone: @escaping (Int, Int, Date?) -> Void) {
        self.task = task
        self.onDone = onDone
        let weekdayIndex = (Calendar.current.component(.weekday, from: task.resolvedDate) + 5) % 7
        _selectedDays = State(initialValue: [CommitmentEntity.weekdaySymbols[weekdayIndex]])
        // Same goal-linked default as creation time — if this task belongs to a goal, default
        // to running the repeat through the goal's target date instead of a generic 4 weeks.
        if let goal = task.goal {
            _weeks = State(initialValue: TaskReplicator.weeksUntil(goal.resolvedTargetDate, from: task.resolvedDate))
        } else {
            _weeks = State(initialValue: 4)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repeat \"\(task.title ?? "task")\"")
                        .wpTypography(.cardTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                    Text("Skips any day it would collide with something.")
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textSecondary)
                }

                HStack {
                    ForEach(CommitmentEntity.weekdaySymbols, id: \.self) { day in
                        let selected = selectedDays.contains(day)
                        Text(String(day.prefix(1)))
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(selected ? ColorTokens.textPrimary : ColorTokens.surface1)
                            .foregroundStyle(selected ? ColorTokens.surface0 : ColorTokens.textSecondary)
                            .clipShape(Circle())
                            .onTapGesture {
                                if selected { selectedDays.remove(day) } else { selectedDays.insert(day) }
                            }
                    }
                }

                Stepper("For \(weeks) week\(weeks == 1 ? "" : "s")", value: $weeks, in: 1...52)
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textPrimary)

                Spacer()

                Button("Repeat") {
                    let result = TaskReplicator.repeatWeekly(task, onWeekdays: selectedDays, forWeeks: weeks, context: context)
                    dismiss()
                    onDone(result.created, result.skipped, result.lastDate)
                }
                .buttonStyle(PrimaryButtonStyle(tint: theme.accentSwatch.color, foreground: .white))
                .disabled(selectedDays.isEmpty)
            }
            .padding(20)
            .background(ColorTokens.surface0.ignoresSafeArea())
            .navigationTitle("Repeat task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct NotesEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager
    @Binding var notes: String

    var body: some View {
        NavigationStack {
            TextEditor(text: $notes)
                .padding(12)
                .background(ColorTokens.surface0.ignoresSafeArea())
                .navigationTitle("Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .tint(theme.accentSwatch.color)
                    }
                }
        }
    }
}

#Preview {
    NewTaskView(onSave: { _, _ in })
        .environmentObject(ThemeManager.shared)
}
