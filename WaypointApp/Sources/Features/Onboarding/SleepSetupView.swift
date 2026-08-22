import SwiftUI

/// Sleep is a mandatory protected block, not an optional commitment — shown with a
/// sensible default already filled in so most people can just tap Continue, with the
/// option to adjust if it doesn't match their schedule.
struct SleepSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sleep = SleepSettings.shared
    var buttonLabel: String = "Continue"
    var onFinished: () -> Void = {}

    @State private var durationHours: Double

    init(buttonLabel: String = "Continue", onFinished: @escaping () -> Void = {}) {
        self.buttonLabel = buttonLabel
        self.onFinished = onFinished
        _durationHours = State(initialValue: Double(SleepSettings.shared.durationMinutes) / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Protect your sleep")
                    .wpTypography(.screenTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                Text("Waypoint never schedules tasks during this window. Does this look right?")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
            }
            .padding(.top, 24)

            VStack(spacing: 10) {
                HStack {
                    Text("Bedtime")
                        .wpTypography(.cardTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                    Spacer()
                    DatePicker("", selection: $sleep.startTimeOfDay, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .wpCard()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Hours of sleep")
                            .wpTypography(.cardTitle)
                            .foregroundStyle(ColorTokens.textPrimary)
                        Spacer()
                        Text(formattedDuration)
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textSecondary)
                    }
                    Slider(value: $durationHours, in: 4...10, step: 0.5)
                        .tint(ColorTokens.success)
                }
                .wpCard()

                Text("Wake up around \(wakeLabel)")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
                    .padding(.horizontal, 4)
            }

            Spacer()

            Button(buttonLabel) {
                sleep.durationMinutes = Int(durationHours * 60)
                sleep.isConfirmed = true
                onFinished()
                dismiss()
            }
            .buttonStyle(.wpPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
        .background(ColorTokens.surface0.ignoresSafeArea())
    }

    private var formattedDuration: String {
        let hours = Int(durationHours)
        let minutes = Int((durationHours - Double(hours)) * 60)
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    private var wakeLabel: String {
        sleep.startTimeOfDay
            .addingTimeInterval(durationHours * 3600)
            .formatted(.dateTime.hour().minute())
    }
}

#Preview {
    SleepSetupView(onFinished: {})
}
