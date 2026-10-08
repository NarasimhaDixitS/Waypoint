import SwiftUI
import CoreData

struct PomodoroView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var theme: ThemeManager

    var focusTitle: String?
    /// Raw id, matching how the event log refers to tasks: the record has to outlive the task.
    var focusTaskID: UUID?
    /// How long the task was planned for, and when. Both are `nil` for a free session.
    ///
    /// **The timer used to ignore these entirely.** It opened at whatever duration was last
    /// used — so starting a focus run on a ninety-minute task gave you twenty-five minutes, and
    /// a twenty-minute task could open a forty-five-minute timer because of something you did
    /// on Tuesday. The task already says how long it's meant to take; asking again was asking a
    /// question the app had already been answered.
    var taskMinutes: Int?
    var taskStart: Date?
    var onSessionComplete: (() -> Void)?

    /// Remembered across sessions, and used only when there's no task to take the length from.
    @AppStorage("pomodoroMinutes") private var selectedMinutes = 25

    @State private var remainingSeconds: Int
    /// Wall-clock end time while running — the source of truth for the countdown, so it
    /// stays correct even if the app is suspended and the UI timer stops ticking.
    @State private var endDate: Date?
    @State private var isRunning = false
    @State private var showingCustomPicker = false
    @State private var customMinutes = 25

    // MARK: - Session accounting
    //
    // Focused time is accumulated across run stretches rather than read off the countdown,
    // because the two are not the same number. A timer paused over lunch and resumed still
    // shows the same remaining seconds, and treating the gap as focus would make every estimate
    // look wildly optimistic. Only stretches where it was actually running count.

    /// When the current run stretch began; `nil` while paused.
    @State private var runStartedAt: Date?
    /// Focused seconds banked from earlier stretches of this session.
    @State private var bankedSeconds: Int = 0
    /// When the user first pressed play — the session's own start, kept across pauses.
    @State private var sessionStartedAt: Date?
    /// Guards against recording twice when the timer finishes and the sheet is then dismissed.
    @State private var didRecord = false

    /// The task's own length leads, then the usual stretches — minus any that duplicate it.
    ///
    /// A fixed 25/30/45 beside a fifty-minute task offers three ways to stop early and no way
    /// to do the thing as planned.
    private var presets: [Int] {
        guard let taskMinutes else { return [25, 30, 45] }
        // What's left of the window earns a place when it's a real alternative — far enough
        // from the full length to mean something, and long enough to be worth starting. Without
        // it, "stay on plan" is a trip through Custom.
        let remaining = windowMinutesLeft
        let offerRemaining = remaining.map { $0 >= 5 && $0 < taskMinutes - 4 } ?? false
        let base = [taskMinutes] + (offerRemaining ? [remaining!] : [])
        return base + [25, 45].filter { !base.contains($0) }
    }
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(
        focusTitle: String? = nil,
        focusTaskID: UUID? = nil,
        taskMinutes: Int? = nil,
        taskStart: Date? = nil,
        onSessionComplete: (() -> Void)? = nil
    ) {
        self.focusTitle = focusTitle
        self.focusTaskID = focusTaskID
        self.taskMinutes = taskMinutes
        self.taskStart = taskStart
        self.onSessionComplete = onSessionComplete
        // The task's own length wins over the remembered one. The memory is for free sessions,
        // where there's nothing better to go on.
        let minutes = taskMinutes ?? (UserDefaults.standard.object(forKey: "pomodoroMinutes") as? Int ?? 25)
        _remainingSeconds = State(initialValue: minutes * 60)
    }

    private var totalSeconds: Int { selectedMinutes * 60 }
    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1 - Double(remainingSeconds) / Double(totalSeconds)
    }
    private var isCustomSelected: Bool { !presets.contains(selectedMinutes) }

    /// The length this run is actually using — the task's, unless the user has picked another.
    private var activeMinutes: Int { selectedMinutes }

    private var plannedEnd: Date? {
        guard let taskStart, let taskMinutes else { return nil }
        return taskStart.addingTimeInterval(TimeInterval(taskMinutes * 60))
    }

    /// Minutes left of the planned window, or `nil` once it's gone.
    private var windowMinutesLeft: Int? {
        guard let plannedEnd else { return nil }
        let left = Int(plannedEnd.timeIntervalSinceNow / 60)
        return left > 0 ? left : nil
    }

    /// Where you actually are relative to the plan.
    ///
    /// **This screen used to say nothing about it.** The timer never looked at the clock —
    /// `taskStart` was only ever formatted into a label — so opening a 6:00–6:40 task at 6:38
    /// offered a full forty minutes running to 7:18, and a window that closed three hours ago
    /// still read as a neutral "Planned 6:00–6:40 AM".
    ///
    /// The length deliberately doesn't change. The duration estimates how long the *work*
    /// takes, and starting late doesn't make it shorter — shrinking the timer to the leftover
    /// window would quietly claim a forty-minute job is now a two-minute one. It just stops
    /// pretending you're on time when you aren't.
    private var planLine: String? {
        guard let taskStart, let taskMinutes, let plannedEnd else { return nil }
        let window = "\(taskStart.formatted(date: .omitted, time: .shortened))–\(plannedEnd.formatted(date: .omitted, time: .shortened))"

        if Date.now < taskStart {
            return "Planned \(window) · \(taskMinutes) min"
        }
        if let left = windowMinutesLeft {
            return "Planned \(window) · window ends in \(left) min"
        }
        return "Was planned for \(window)"
    }

    /// Focused minutes so far, counting only stretches where it was actually running.
    private var focusedMinutes: Int {
        let live = runStartedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        return (bankedSeconds + live) / 60
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 5) {
                Text(focusTitle ?? "Free session")
                    .wpTypography(.screenTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                // The plan, not just the title. Without it the screen is a stopwatch that
                // happens to be open; with it the countdown is visibly the task's own hour.
                if let planLine {
                    Text(planLine)
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 8)

            // No ring. The page is the vessel now, and a ring would say the same thing twice.
            VStack(spacing: 4) {
                Text(timeLabel)
                    .font(.system(size: 68, weight: .semibold, design: .rounded))
                    .foregroundStyle(ColorTokens.textPrimary)
                    .monospacedDigit()
                // Counts only stretches that were actually running, so a timer left paused
                // over lunch doesn't claim the lunch. See the session accounting above.
                if focusedMinutes > 0 {
                    Text("\(focusedMinutes) min focused")
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textSecondary)
                }
            }
            .padding(.vertical, 18)

            HStack(spacing: 10) {
                ForEach(presets, id: \.self) { minutes in
                    // The task's own length is marked, so picking another is visibly a choice
                    // to depart from the plan rather than just another number.
                    intervalChip(
                        label: "\(minutes) min",
                        isSelected: selectedMinutes == minutes,
                        // A dot rather than the word: "40 min · planned" wrapped onto two lines
                        // and made one chip taller than the rest of the row.
                        isPlanned: minutes == taskMinutes
                    ) {
                        select(minutes: minutes)
                    }
                }
                intervalChip(label: isCustomSelected ? "\(selectedMinutes) min" : "Custom", isSelected: isCustomSelected) {
                    customMinutes = isCustomSelected ? selectedMinutes : selectedMinutes
                    showingCustomPicker = true
                }
            }

            Button {
                isRunning.toggle()
            } label: {
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    // Same reason as the Save button in `NewTaskView`: `textPrimary` is a warm
                    // off-white in dark mode, so a white glyph on it is invisible.
                    .foregroundStyle(ColorTokens.surface0)
                    .frame(width: 64, height: 64)
                    .background(ColorTokens.textPrimary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .medium), trigger: isRunning)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                ColorTokens.surface0
                WaveFill(
                    progress: progress,
                    tint: theme.accentSwatch.markColor,
                    line: theme.accentSwatch.markColor
                )
            }
            .ignoresSafeArea()
        }
        .sensoryFeedback(.success, trigger: remainingSeconds) { old, new in old > 0 && new == 0 }
        .overlay(alignment: .topTrailing) {
            // The app hides the navigation bar everywhere, so a system toolbar button here was
            // the one piece of borrowed chrome on an otherwise full-bleed screen.
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ColorTokens.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
            .accessibilityLabel("Close")
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if let taskMinutes { selectedMinutes = taskMinutes }
            remainingSeconds = selectedMinutes * 60
            #if DEBUG
            // `-wpFocusFill 0.6` opens the timer already six-tenths through, running. The fill
            // is the whole point of this screen and it starts empty, so without this the only
            // way to look at it is to sit and wait out a work block.
            let args = ProcessInfo.processInfo.arguments
            if let flag = args.firstIndex(of: "-wpFocusFill"), flag + 1 < args.count,
               let fraction = Double(args[flag + 1]) {
                remainingSeconds = Int(Double(selectedMinutes * 60) * (1 - min(max(fraction, 0), 1)))
                bankedSeconds = selectedMinutes * 60 - remainingSeconds
                isRunning = true
            }
            #endif
        }
        .onReceive(timer) { _ in tick() }
        .onChange(of: isRunning) { toggleRunning($1) }
        .onDisappear { recordSession(ranToCompletion: false) }
        .sheet(isPresented: $showingCustomPicker) {
            CustomDurationSheet(minutes: $customMinutes) {
                select(minutes: customMinutes)
            }
        }
    }

    private func intervalChip(
        label: String,
        isSelected: Bool,
        isPlanned: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isPlanned {
                    Circle()
                        .fill(isSelected ? ColorTokens.surface0 : theme.accentSwatch.markColor)
                        .frame(width: 5, height: 5)
                }
                Text(label)
                    .wpTypography(.body)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? ColorTokens.surface0 : ColorTokens.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? ColorTokens.textPrimary : ColorTokens.surface1)
            .clipShape(Capsule())
        }
        .buttonStyle(.wpRow)
        .accessibilityLabel(isPlanned ? "\(label), the planned length" : label)
    }

    private func select(minutes: Int) {
        // Picking a different length ends whatever was running and banks it — the time spent so
        // far was still spent, and silently folding it into a session with a different planned
        // length would corrupt exactly the comparison this data exists for.
        recordSession(ranToCompletion: false)
        selectedMinutes = minutes
        remainingSeconds = minutes * 60
        endDate = nil
        isRunning = false
        resetSessionAccounting()
        NotificationManager.cancelPomodoroComplete()
    }

    private func resetSessionAccounting() {
        runStartedAt = nil
        bankedSeconds = 0
        sessionStartedAt = nil
        didRecord = false
    }

    private func toggleRunning(_ running: Bool) {
        if running {
            endDate = Date.now.addingTimeInterval(TimeInterval(remainingSeconds))
            runStartedAt = .now
            if sessionStartedAt == nil { sessionStartedAt = .now }
            if theme.notificationsEnabled {
                NotificationManager.schedulePomodoroComplete(in: TimeInterval(remainingSeconds), taskTitle: focusTitle)
            }
        } else {
            if let endDate {
                remainingSeconds = max(0, Int(endDate.timeIntervalSinceNow.rounded()))
            }
            bankRunStretch()
            endDate = nil
            NotificationManager.cancelPomodoroComplete()
        }
    }

    /// Moves the stretch just ended into `bankedSeconds`.
    private func bankRunStretch() {
        guard let runStartedAt else { return }
        bankedSeconds += max(0, Int(Date.now.timeIntervalSince(runStartedAt).rounded()))
        self.runStartedAt = nil
    }

    /// Writes the session down. Called both when the countdown reaches zero and when the sheet
    /// closes, since a session abandoned halfway is as much a fact about how long work takes as
    /// one that ran its course — `ranToCompletion` is what tells them apart.
    private func recordSession(ranToCompletion: Bool) {
        guard !didRecord, let startedAt = sessionStartedAt else { return }
        bankRunStretch()
        didRecord = true
        FocusSessionLog.record(
            taskID: focusTaskID,
            taskTitle: focusTitle,
            startedAt: startedAt,
            endedAt: .now,
            plannedSeconds: totalSeconds,
            actualSeconds: bankedSeconds,
            ranToCompletion: ranToCompletion,
            in: context
        )
        try? context.save()
    }

    private func tick() {
        guard isRunning, let endDate else { return }
        let remaining = max(0, Int(endDate.timeIntervalSinceNow.rounded()))
        remainingSeconds = remaining
        if remaining <= 0 {
            recordSession(ranToCompletion: true)
            isRunning = false
            self.endDate = nil
            onSessionComplete?()
        }
    }

    private var timeLabel: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }
}

private struct CustomDurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var minutes: Int
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Minutes", selection: $minutes) {
                    ForEach(Array(stride(from: 5, through: 180, by: 5)), id: \.self) { value in
                        Text("\(value) min").tag(value)
                    }
                }
                .pickerStyle(.wheel)

                Button("Use \(minutes) min") {
                    onDone()
                    dismiss()
                }
                .buttonStyle(.wpPrimary)
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding(.top, 20)
            .background(ColorTokens.surface0.ignoresSafeArea())
            .navigationTitle("Custom duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .presentationDetents([.height(320)])
        }
    }
}

#Preview {
    NavigationStack { PomodoroView(focusTitle: "Deep work: thesis ch. 3") }
        .environmentObject(ThemeManager.shared)
}
