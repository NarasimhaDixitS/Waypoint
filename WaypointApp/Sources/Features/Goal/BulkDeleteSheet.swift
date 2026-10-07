import SwiftUI

/// Offered when a bulk delete would touch a repeat: just these, or the repeat going forward.
///
/// The counts are the point. Both options say exactly how many tasks they remove, so the
/// decision is made on a number rather than on a word like "series" — which is easy to read
/// past, and which hides the fact that it reaches work the user never ticked.
struct BulkDeleteSheet: View {
    @Environment(\.dismiss) private var dismiss

    let plan: BulkDeletePlan
    var onDeleteTasks: () -> Void
    var onDeleteSeries: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Delete")
                    .wpTypography(.screenTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                Text(plan.seriesCount == 1
                     ? "One of these repeats."
                     : "\(plan.seriesCount) of these repeat.")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
            }

            VStack(spacing: 10) {
                option(
                    title: plan.selected.count == 1 ? "Just this task" : "Just these \(plan.selected.count) tasks",
                    detail: "Leaves the rest of the repeat alone.",
                    icon: "checkmark.circle",
                    emphasis: false
                ) {
                    onDeleteTasks()
                    dismiss()
                }

                option(
                    title: "The whole repeat — \(plan.seriesTasks.count) tasks",
                    // Named plainly, because this is the number the user didn't choose by hand.
                    detail: plan.additionalCount == 1
                        ? "Also removes 1 later task you haven't selected."
                        : "Also removes \(plan.additionalCount) later tasks you haven't selected.",
                    icon: "repeat",
                    emphasis: true
                ) {
                    onDeleteSeries()
                    dismiss()
                }
            }

            // Said once, here, rather than on both rows: everything past is safe either way.
            Text("Occurrences before the earliest one you selected are never touched.")
                .wpTypography(.micro)
                .foregroundStyle(ColorTokens.textMuted)

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTokens.surface1)
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
        .presentationBackground(ColorTokens.surface1)
    }

    private func option(
        title: String,
        detail: String,
        icon: String,
        emphasis: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(emphasis ? ColorTokens.textWarning : ColorTokens.textSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .wpTypography(.cardTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(detail)
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(ColorTokens.surface0)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(emphasis ? ColorTokens.textWarning.opacity(0.4) : ColorTokens.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The second screen on the series path.
///
/// **Why a confirmation as well as undo.** Undo is four seconds, and four seconds is a short
/// time to notice that forty tasks you never looked at have gone — most of them scheduled for
/// weeks you aren't currently reading. The confirmation is what makes the decision conscious;
/// the undo toast still appears afterwards and still works, so a change of heart in the moment
/// is recoverable too. Two nets, because this is the one action here that reaches work the
/// user didn't pick by hand.
struct SeriesDeleteConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss

    let plan: BulkDeletePlan
    var onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Delete the whole repeat?")
                .wpTypography(.screenTitle)
                .foregroundStyle(ColorTokens.textPrimary)

            Text(message)
                .wpTypography(.body)
                .foregroundStyle(ColorTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text("Delete \(plan.seriesTasks.count) tasks")
                }
                .buttonStyle(PrimaryButtonStyle(tint: ColorTokens.warning, foreground: .white))

                Button { dismiss() } label: {
                    Text("Keep them")
                }
                .buttonStyle(.wpSecondary)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTokens.surface1)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationBackground(ColorTokens.surface1)
    }

    private var message: String {
        let series = plan.seriesCount == 1 ? "this repeat" : "these \(plan.seriesCount) repeats"
        return "This removes \(plan.seriesTasks.count) tasks — every remaining occurrence of \(series) from the earliest one you selected onwards. Anything scheduled before that stays."
    }
}
