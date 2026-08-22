import SwiftUI

/// Shown when extending a task pushes into the tasks after it, but there's still room
/// before anything immovable — one confirmation shifts the whole downstream chain at once.
struct CascadeConfirmView: View {
    @Environment(\.dismiss) private var dismiss

    let shifts: [CascadeShift]
    var onConfirm: () -> Void
    var onCancel: () -> Void

    private var shiftMinutes: Int {
        guard let first = shifts.first else { return 0 }
        return Int(first.newStart.timeIntervalSince(first.task.resolvedStartTime) / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.right.to.line")
                    .foregroundStyle(ColorTokens.textInProgress)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Push the rest of your day back?")
                        .wpTypography(.cardTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                    Text("\(shifts.count == 1 ? "1 task" : "\(shifts.count) tasks") will move about \(shiftMinutes) min later.")
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textSecondary)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(shifts.enumerated()), id: \.element.id) { index, shift in
                    HStack {
                        Text(shift.task.title ?? "")
                            .wpTypography(.cardTitle)
                            .foregroundStyle(ColorTokens.textPrimary)
                        Spacer()
                        Text(shift.task.resolvedStartTime.formatted(.dateTime.hour().minute()))
                            .foregroundStyle(ColorTokens.textMuted)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11))
                            .foregroundStyle(ColorTokens.textMuted)
                        Text(shift.newStart.formatted(.dateTime.hour().minute()))
                            .foregroundStyle(ColorTokens.textInProgress)
                    }
                    .wpTypography(.body)
                    .padding(12)
                    if index < shifts.count - 1 {
                        Divider().overlay(ColorTokens.border)
                    }
                }
            }
            .background(ColorTokens.surface0)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(spacing: 10) {
                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text("Push these back")
                }
                .buttonStyle(.wpPrimary)

                Button {
                    onCancel()
                    dismiss()
                } label: {
                    Text("Cancel")
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(ColorTokens.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(16)
        .presentationDetents([.medium])
        .presentationBackground(ColorTokens.surface0)
    }
}
