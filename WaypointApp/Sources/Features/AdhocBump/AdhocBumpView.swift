import SwiftUI

/// Generic "your day is full" resolver: shown both when a brand-new task collides with the
/// day, and when growing/moving an existing task would run into something immovable.
struct AdhocBumpView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager

    var headline: String = "Needs a slot"
    var message: String
    let collidingTasks: [TaskEntity]
    var onBumpExisting: (TaskEntity) -> Void
    var secondaryLabel: String = "Bump it to tomorrow instead"
    var onSecondaryAction: () -> Void
    /// When non-nil, there's also room after everything else today — offer tacking the new
    /// task on at the end instead of bumping anything.
    var appendStart: Date? = nil
    var onAppendToEnd: (() -> Void)? = nil
    var onRequestPaywall: () -> Void = {}

    @State private var selected: TaskEntity?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(ColorTokens.warningTint)
                        .frame(width: 48, height: 48)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ColorTokens.textWarning)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(headline)
                        .wpTypography(.screenTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                    Text(message)
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textSecondary)
                }
            }

            if collidingTasks.isEmpty {
                Text("Nothing else can move to make room — try a shorter duration or a different time.")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ColorTokens.surface0)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PICK ONE TO MOVE TO TOMORROW")
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textMuted)
                        .tracking(0.6)

                    VStack(spacing: 8) {
                        ForEach(Array(collidingTasks.enumerated()), id: \.element.id) { _, task in
                            Button {
                                selected = task
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selected == task ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 21))
                                        .foregroundStyle(selected == task ? ColorTokens.textPrimary : ColorTokens.textMuted)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.title ?? "")
                                            .wpTypography(.cardTitle)
                                            .foregroundStyle(ColorTokens.textPrimary)
                                        Text("\(task.priorityValue.label) priority · \(task.timeRangeLabel)")
                                            .wpTypography(.body)
                                            .foregroundStyle(ColorTokens.textSecondary)
                                    }
                                    Spacer()
                                }
                                .padding(14)
                                .background(selected == task ? ColorTokens.surface0 : ColorTokens.surface1)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(selected == task ? ColorTokens.textPrimary : ColorTokens.border, lineWidth: selected == task ? 1.6 : 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    guard theme.isPro else { return }
                    selected = collidingTasks.min { $0.priorityValue.sortWeight > $1.priorityValue.sortWeight }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Suggest best swap")
                        if !theme.isPro { ProBadge() }
                    }
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textInProgress)
                    .opacity(theme.isPro ? 1 : 0.6)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 10) {
                if let appendStart {
                    Button {
                        onAppendToEnd?()
                        dismiss()
                    } label: {
                        Text("Add to next open slot — starts \(appendStart.formatted(.dateTime.hour().minute()))")
                    }
                    .buttonStyle(.wpPrimary)

                    Button {
                        if let selected {
                            onBumpExisting(selected)
                            dismiss()
                        }
                    } label: {
                        Text(selected.map { "Move \u{201C}\($0.title ?? "task")\u{201D} to tomorrow" } ?? "Move selected task to tomorrow")
                    }
                    .buttonStyle(.wpSecondary)
                    .disabled(selected == nil)
                } else {
                    Button {
                        if let selected {
                            onBumpExisting(selected)
                            dismiss()
                        }
                    } label: {
                        Text(selected.map { "Move \u{201C}\($0.title ?? "task")\u{201D} to tomorrow" } ?? "Move selected task to tomorrow")
                    }
                    .buttonStyle(.wpPrimary)
                    .disabled(selected == nil)
                }

                Button {
                    onSecondaryAction()
                    dismiss()
                } label: {
                    Text(secondaryLabel)
                }
                .buttonStyle(.wpSecondary)
            }
        }
        .padding(22)
        .background(ColorTokens.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(16)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(ColorTokens.surface0)
    }
}
