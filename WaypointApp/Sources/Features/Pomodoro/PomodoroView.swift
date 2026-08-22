import SwiftUI

struct PomodoroView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager

    var focusTitle: String?
    var onSessionComplete: (() -> Void)?

    /// Remembered across sessions so returning users don't have to reselect a duration.
    @AppStorage("pomodoroMinutes") private var selectedMinutes = 25

    @State private var remainingSeconds: Int
    /// Wall-clock end time while running — the source of truth for the countdown, so it
    /// stays correct even if the app is suspended and the UI timer stops ticking.
    @State private var endDate: Date?
    @State private var isRunning = false
    @State private var showingCustomPicker = false
    @State private var customMinutes = 25

    private let presets = [25, 30, 45]
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(focusTitle: String? = nil, onSessionComplete: (() -> Void)? = nil) {
        self.focusTitle = focusTitle
        self.onSessionComplete = onSessionComplete
        let minutes = UserDefaults.standard.object(forKey: "pomodoroMinutes") as? Int ?? 25
        _remainingSeconds = State(initialValue: minutes * 60)
    }

    private var totalSeconds: Int { selectedMinutes * 60 }
    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1 - Double(remainingSeconds) / Double(totalSeconds)
    }
    private var isCustomSelected: Bool { !presets.contains(selectedMinutes) }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 4) {
                Text("Focusing on")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
                Text(focusTitle ?? "Free session")
                    .wpTypography(.cardTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
            }

            ZStack {
                ProgressRing(
                    progress: progress,
                    lineWidth: 8,
                    color: ColorTokens.inProgress,
                    trackColor: ColorTokens.border,
                    showsLabel: false
                )
                Text(timeLabel)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(ColorTokens.textPrimary)
                    .monospacedDigit()
            }
            .frame(width: 220, height: 220)

            HStack(spacing: 10) {
                ForEach(presets, id: \.self) { minutes in
                    intervalChip(label: "\(minutes) min", isSelected: selectedMinutes == minutes) {
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
                    .foregroundStyle(.white)
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
        .background(ColorTokens.surface0.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: remainingSeconds) { old, new in old > 0 && new == 0 }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear {
            remainingSeconds = selectedMinutes * 60
        }
        .onReceive(timer) { _ in tick() }
        .onChange(of: isRunning) { toggleRunning($1) }
        .sheet(isPresented: $showingCustomPicker) {
            CustomDurationSheet(minutes: $customMinutes) {
                select(minutes: customMinutes)
            }
        }
    }

    private func intervalChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .wpTypography(.body)
                .foregroundStyle(isSelected ? Color.white : ColorTokens.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? ColorTokens.inProgress : ColorTokens.surface1)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func select(minutes: Int) {
        selectedMinutes = minutes
        remainingSeconds = minutes * 60
        endDate = nil
        isRunning = false
        NotificationManager.cancelPomodoroComplete()
    }

    private func toggleRunning(_ running: Bool) {
        if running {
            endDate = Date.now.addingTimeInterval(TimeInterval(remainingSeconds))
            if theme.notificationsEnabled {
                NotificationManager.schedulePomodoroComplete(in: TimeInterval(remainingSeconds), taskTitle: focusTitle)
            }
        } else {
            if let endDate {
                remainingSeconds = max(0, Int(endDate.timeIntervalSinceNow.rounded()))
            }
            endDate = nil
            NotificationManager.cancelPomodoroComplete()
        }
    }

    private func tick() {
        guard isRunning, let endDate else { return }
        let remaining = max(0, Int(endDate.timeIntervalSinceNow.rounded()))
        remainingSeconds = remaining
        if remaining <= 0 {
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
