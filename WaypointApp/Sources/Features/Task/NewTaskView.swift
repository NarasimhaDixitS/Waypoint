import SwiftUI

/// The four repeat presets shown as pills in the notepad-style creation layout, replacing
/// the old always-visible per-weekday circle picker with one tap for the common cases and
/// `.custom` as the escape hatch back to picking individual days.
private enum RepeatPreset: CaseIterable, Identifiable {
    case entireWeek, weekdays, weekends, custom

    var id: Self { self }

    var label: String {
        switch self {
        case .entireWeek: "Entire week"
        case .weekdays: "Weekdays"
        case .weekends: "Weekends"
        case .custom: "Custom"
        }
    }

    /// `nil` for `.custom` — its days come from direct user taps on the weekday circles,
    /// not a fixed set.
    var fixedDays: Set<String>? {
        switch self {
        case .entireWeek: Set(CommitmentEntity.weekdaySymbols)
        case .weekdays: Set(CommitmentEntity.weekdaySymbols.prefix(5))
        case .weekends: Set(CommitmentEntity.weekdaySymbols.suffix(2))
        case .custom: nil
        }
    }
}

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
    @State private var showingGoalCreate = false
    @State private var showingGoalPicker = false
    /// Edit mode only — the notepad layout shows the date as a plain tappable text piece
    /// alongside time/duration rather than a boxed `DatePicker`.
    @State private var showingDateSheet = false
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
    /// Which repeat preset pill is selected, if any — `nil` means "just this once". Kept
    /// separate from `repeatDays` (the actual source of truth passed to the saved draft)
    /// because `.custom` needs `repeatDays` to stay freely editable via the weekday circles
    /// while still tracking which pill is highlighted.
    @State private var repeatPreset: RepeatPreset?
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

    /// Display order for the priority segmented control — deliberately low → medium → high,
    /// distinct from `Priority`'s own declaration order (high, medium, low), which is sorted
    /// by urgency rather than by reading order left-to-right.
    private static let priorityOrder: [Priority] = [.low, .medium, .high]

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

    /// The day this task will actually be filed on: the selected day normally, or the first
    /// day matching the chosen repeat pattern when that pattern doesn't include the selected
    /// day's own weekday. See `saveTask`.
    /// Today's start, except for a task that already sits in the past — a picker whose range
    /// excludes its own bound value leaves SwiftUI's `DatePicker` unable to render the
    /// selection, so an existing task can always at least keep the date it has. Editing it
    /// forward is allowed; editing any task further back than today is not.
    private var earliestSelectableDay: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let existing = existingTask.map({ cal.startOfDay(for: $0.resolvedDate) }) else { return today }
        return min(today, existing)
    }

    private var seedDay: Date {
        TaskReplicator.firstDay(onOrAfter: selectedDay, matching: repeatDays)
    }

    /// A goal-linked repeat can't run past the goal's own end date — keeps a task's schedule
    /// from quietly outliving the goal it belongs to. Ungoaled tasks keep the generic ceiling.
    private var maxRepeatWeeks: Int {
        guard let selectedGoal else { return 52 }
        return TaskReplicator.weeksUntil(selectedGoal.resolvedTargetDate, from: selectedDay)
    }

    /// Every field on the page shares this same flat, borderless "inset well" treatment —
    /// `surface0` (the page-background gray) fills the field itself, sitting inside the
    /// card's own `surface1` (white) background, exactly inverted from how those two tokens
    /// are normally used elsewhere. That inversion is what makes a field read as a recessed
    /// input rather than a raised card.
    @ViewBuilder
    private func filledField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(ColorTokens.surface0)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .wpTypography(.micro)
                .foregroundStyle(ColorTokens.textSecondary)
            filledField {
                TextField("Task name", text: $title)
                    .wpTypography(.cardTitle)
            }
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description")
                .wpTypography(.micro)
                .foregroundStyle(ColorTokens.textSecondary)
            filledField {
                TextField("Add a description", text: $notes, axis: .vertical)
                    .wpTypography(.body)
                    .lineLimit(1...4)
            }
        }
    }

    private var goalField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Goal")
                .wpTypography(.micro)
                .foregroundStyle(ColorTokens.textSecondary)
            Button { showingGoalPicker = true } label: {
                filledField {
                    HStack {
                        Text(selectedGoal?.name ?? "No goal")
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ColorTokens.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Edit mode only — creation always defaults to today/the day passed in, so there's
    /// nothing to change here until the task actually exists.
    private var dateField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date")
                .wpTypography(.micro)
                .foregroundStyle(ColorTokens.textSecondary)
            Button { showingDateSheet = true } label: {
                filledField {
                    HStack {
                        Text(selectedDay.formatted(.dateTime.month(.abbreviated).day().year()))
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textPrimary)
                        Spacer()
                        Image(systemName: "calendar")
                            .foregroundStyle(ColorTokens.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var timeDurationRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Time")
                    .wpTypography(.micro)
                    .foregroundStyle(ColorTokens.textSecondary)
                Button { showingTimeSheet = true } label: {
                    filledField {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(ColorTokens.textSecondary)
                            Text(startTime.formatted(.dateTime.hour().minute()))
                                .wpTypography(.body)
                                .foregroundStyle(ColorTokens.textPrimary)
                            Spacer()
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Duration")
                    .wpTypography(.micro)
                    .foregroundStyle(ColorTokens.textSecondary)
                Button { showingDurationSheet = true } label: {
                    filledField {
                        HStack {
                            Image(systemName: "hourglass")
                                .foregroundStyle(ColorTokens.textSecondary)
                            Text("\(durationMinutes) min")
                                .wpTypography(.body)
                                .foregroundStyle(ColorTokens.textPrimary)
                            Spacer()
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Segmented capsule, all three options always visible — tapping one selects it
    /// directly, replacing the earlier tap-to-cycle interaction now that the layout has
    /// room to just show every option at once.
    private var priorityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Priority")
                .wpTypography(.micro)
                .foregroundStyle(ColorTokens.textSecondary)
            HStack(spacing: 4) {
                ForEach(Self.priorityOrder) { p in
                    let selected = priority == p
                    Text(p.label)
                        .wpTypography(.body)
                        .foregroundStyle(selected ? p.tintColor : ColorTokens.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? ColorTokens.surface1 : Color.clear)
                                .shadow(color: selected ? ColorTokens.shadowResting : .clear, radius: 4, x: 0, y: 2)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) { priority = p }
                        }
                }
            }
            .padding(4)
            .background(ColorTokens.surface0)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .sensoryFeedback(.selection, trigger: priority)
    }

    /// Split out of `body` — folding this back inline pushes the surrounding `ScrollView`'s
    /// single expression past what the type-checker can solve in reasonable time.
    @ViewBuilder
    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repeat")
                .wpTypography(.micro)
                .foregroundStyle(ColorTokens.textSecondary)
            HStack(spacing: 8) {
                ForEach(RepeatPreset.allCases) { preset in
                    let selected = repeatPreset == preset
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { select(preset) }
                    } label: {
                        Text(preset.label)
                            .wpTypography(.micro)
                            .foregroundStyle(ColorTokens.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selected ? ColorTokens.surface1 : ColorTokens.surface0)
                            .overlay(
                                Capsule().stroke(selected ? ColorTokens.textPrimary : Color.clear, lineWidth: 1.4)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if repeatPreset == .custom {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(CommitmentEntity.weekdaySymbols, id: \.self) { day in
                        let selected = repeatDays.contains(day)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(selected ? theme.accentSwatch.color : ColorTokens.textMuted)
                                .frame(width: 6, height: 6)
                            Text(day)
                                .wpTypography(.micro)
                                .foregroundStyle(ColorTokens.textPrimary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selected ? ColorTokens.surface1 : ColorTokens.surface0)
                        .overlay(
                            Capsule().stroke(selected ? ColorTokens.textPrimary : Color.clear, lineWidth: 1.2)
                        )
                        .clipShape(Capsule())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if selected { repeatDays.remove(day) } else { repeatDays.insert(day) }
                            }
                        }
                    }
                }
            }

            if !repeatDays.isEmpty {
                Stepper("For \(repeatWeeks) week\(repeatWeeks == 1 ? "" : "s")", value: $repeatWeeks, in: 1...maxRepeatWeeks)
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textPrimary)
                // Only worth saying when the pattern actually moves the task off the day the
                // user is looking at — otherwise it's stating the obvious.
                if existingTask == nil, !Calendar.current.isDate(seedDay, inSameDayAs: selectedDay) {
                    let startLabel = seedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                    Text("Starts \(startLabel), the first matching day.")
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textSecondary)
                }
                if let selectedGoal {
                    let endLabel = selectedGoal.resolvedTargetDate.formatted(.dateTime.month(.abbreviated).day())
                    Text("Capped to \(selectedGoal.name ?? "this goal")'s end date, \(endLabel).")
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textSecondary)
                }
            }
        }
    }

    /// Tapping an already-selected preset turns repeat back off entirely, rather than
    /// requiring a separate "None" pill — the same toggle-to-clear behavior as the old
    /// per-day circle picker had.
    private func select(_ preset: RepeatPreset) {
        if repeatPreset == preset {
            repeatPreset = nil
            repeatDays = []
            return
        }
        repeatPreset = preset
        if let days = preset.fixedDays {
            repeatDays = days
        } else if repeatDays.isEmpty {
            // Entering Custom with nothing chosen yet — start from today's weekday so the
            // stepper below has something non-empty to attach to immediately.
            let weekdayIndex = (Calendar.current.component(.weekday, from: selectedDay) + 5) % 7
            repeatDays = [CommitmentEntity.weekdaySymbols[weekdayIndex]]
        }
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

    /// Centered title with a plain "•••" overflow glyph (edit mode only, mirrors `header`'s
    /// close glyph on the other side) and a plain "X" to dismiss — replaces the system nav
    /// bar entirely, since this view is no longer a `NavigationStack`.
    private var header: some View {
        ZStack {
            Text(existingTask == nil ? "New Task" : "Edit Task")
                .wpTypography(.cardTitle)
                .foregroundStyle(ColorTokens.textPrimary)
            HStack {
                if existingTask != nil {
                    Menu {
                        if let onDuplicate, let existingTask {
                            Button {
                                // Not dismissing here on purpose: duplicating might need to
                                // hand off to a bump sheet if tomorrow collides, and the
                                // parent owns that decision — see `saveTask`.
                                onDuplicate(TaskReplicator.draftForTomorrow(existingTask))
                            } label: {
                                Label("Duplicate to tomorrow", systemImage: "plus.square.on.square")
                            }
                        }
                        Button {
                            showingRepeatSheet = true
                        } label: {
                            Label("Repeat on other days", systemImage: "repeat")
                        }
                        if onDelete != nil {
                            Button(role: .destructive) {
                                showingDeleteConfirm = true
                            } label: {
                                Label("Delete task", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ColorTokens.textSecondary)
                            .frame(width: 32, height: 32)
                    }
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ColorTokens.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    /// Two pill buttons replacing the old top-corner Cancel/Save — matches the reference's
    /// "Clear" / "Add" footer instead of a system toolbar.
    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .wpTypography(.cardTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(ColorTokens.surface0)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                saveTask()
            } label: {
                Text("Save")
                    .wpTypography(.cardTitle)
                    // Not `.white`: this sits on a `textPrimary` fill, which is a warm
                    // off-white in dark mode — white-on-white made the label vanish entirely.
                    // Ink on a `textPrimary` surface has to invert with it, same pairing the
                    // weekday chips and schedule setup already use.
                    .foregroundStyle(ColorTokens.surface0)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(ColorTokens.textPrimary)
                    .clipShape(Capsule())
                    .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    private func saveTask() {
        // A new task carrying a repeat pattern has to start *on* that pattern. Only the
        // repeats after it are placed by weekday, so filing this one on whichever day is
        // currently selected would put the very first occurrence on a weekday the user never
        // picked — asking for Mon/Thu on a Friday really did create a stray Friday task.
        // Editing an existing task leaves its date alone: that date is the user's own choice,
        // shown and editable right there on the page.
        let day = existingTask == nil ? seedDay : selectedDay
        let draft = TaskDraft(
            title: title.isEmpty ? "Untitled task" : title,
            date: day,
            startTime: Self.combining(day: day, timeOfDay: startTime),
            durationMinutes: durationMinutes,
            priority: priority,
            notes: notes.isEmpty ? nil : notes,
            goal: selectedGoal,
            repeatWeekdays: repeatDays,
            repeatWeeks: repeatWeeks
        )
        // No dismiss() here — onSave may need to hand off to a follow-up sheet (ad-hoc bump
        // / cascade confirm) instead of just closing, and only the parent knows which. It's
        // responsible for dismissing.
        onSave(draft, existingTask)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleField
                    descriptionField
                    goalField

                    if existingTask != nil {
                        dateField
                    }

                    timeDurationRow
                    priorityRow

                    if existingTask == nil {
                        repeatSection
                    }
                }
                .padding(20)
            }

            Divider()

            footer
        }
        .background(ColorTokens.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(16)
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
        .onChange(of: selectedGoal) { _, _ in
            // Picking a goal that ends sooner than the currently-chosen length must pull
            // the stepper back down with it — otherwise `repeatWeeks` sits outside its own
            // new `1...maxRepeatWeeks` range.
            repeatWeeks = min(repeatWeeks, maxRepeatWeeks)
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(ColorTokens.surface0)
        .sheet(isPresented: $showingDateSheet) {
                DatePickerSheet(date: $selectedDay, notBefore: earliestSelectableDay)
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

    /// Same reasoning as `NewTaskView.maxRepeatWeeks` — a goal-linked task can't repeat past
    /// its own goal's end date. `task.goal` can't change within this sheet, so this is fixed
    /// for its lifetime, unlike the creation-time version.
    private var maxWeeks: Int {
        guard let goal = task.goal else { return 52 }
        return TaskReplicator.weeksUntil(goal.resolvedTargetDate, from: task.resolvedDate)
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

                Stepper("For \(weeks) week\(weeks == 1 ? "" : "s")", value: $weeks, in: 1...maxWeeks)
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textPrimary)
                if let goal = task.goal {
                    let endLabel = goal.resolvedTargetDate.formatted(.dateTime.month(.abbreviated).day())
                    Text("Capped to \(goal.name ?? "this goal")'s end date, \(endLabel).")
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textSecondary)
                }

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

#Preview {
    NewTaskView(onSave: { _, _ in })
        .environmentObject(ThemeManager.shared)
}
