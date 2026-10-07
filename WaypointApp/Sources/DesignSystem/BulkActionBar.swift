import SwiftUI

/// The bar that appears along the bottom of Today while tasks are selected.
///
/// **Why a bar and not swipe actions.** Row swipe was built and cut: it fought the day-change
/// swipe, committing at 78pt against the day's 55pt, so it could never fire on its own. An
/// explicit mode with an explicit bar has no gesture to lose.
///
/// **Why Delete sits apart.** The two edits are reversible — a priority or a goal set wrongly
/// is set again. Delete is the only thing here that destroys work, so it keeps its distance and
/// its colour, the same rule the task editor's own action section follows.
///
/// Nothing here acts on past days. See `TodayView.canEnterEditMode`.
struct BulkActionBar: View {
    @EnvironmentObject private var theme: ThemeManager

    let count: Int
    var onPriority: () -> Void
    var onGoal: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // The count is the subject of every button beside it, so it reads as a sentence
            // rather than a status: "2 selected — delete".
            Text("\(count) selected")
                .wpTypography(.body)
                .fontWeight(.semibold)
                .foregroundStyle(ColorTokens.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 8)

            action("Priority", icon: "flag", role: .normal, perform: onPriority)
            action("Goal", icon: "target", role: .normal, perform: onGoal)
            action("Delete", icon: "trash", role: .destructive, perform: onDelete)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            // `surface1` with a border, never `surface1` alone: the bar floats over a
            // `surface0` page and those two are 4% apart in light mode. See `ColorTokens`.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ColorTokens.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(ColorTokens.border, lineWidth: 1)
                )
                .shadow(
                    color: Palette.current.usesDepth ? ColorTokens.ShadowTier.raised.color : .clear,
                    radius: ColorTokens.ShadowTier.raised.radius,
                    x: 0,
                    y: ColorTokens.ShadowTier.raised.y
                )
        )
        .padding(.horizontal, 20)
    }

    private enum ActionRole { case normal, destructive }

    private func action(
        _ label: String,
        icon: String,
        role: ActionRole,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .wpTypography(.micro)
            }
            .foregroundStyle(role == .destructive ? ColorTokens.textWarning : ColorTokens.textSecondary)
            // 44pt minimum in both directions, the same rule the completion circle follows.
            .frame(minWidth: 52, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Puts a selection circle in front of a row while selection mode is on.
///
/// A modifier rather than a parameter on `TaskRowView` on purpose. Selection is a property of
/// the *list*, not of a task — the same row appears in Week and on a goal's page, neither of
/// which has a selection mode — so teaching the row about it would spread a Today concept into
/// three screens that don't share it.
struct SelectableRow: ViewModifier {
    @EnvironmentObject private var theme: ThemeManager

    let isSelecting: Bool
    let isSelected: Bool

    func body(content: Content) -> some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    // Unselected is deliberately muted rather than `textSecondary`: a column of
                    // empty circles down the left of every row competes with the titles, and
                    // what matters is which ones are filled.
                    .foregroundStyle(isSelected ? theme.accentSwatch.color : ColorTokens.textMuted)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
            content
        }
        .animation(.easeInOut(duration: 0.2), value: isSelecting)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

extension View {
    func selectable(isSelecting: Bool, isSelected: Bool) -> some View {
        modifier(SelectableRow(isSelecting: isSelecting, isSelected: isSelected))
    }
}

/// Three choices, applied to everything selected.
///
/// Its own small sheet rather than a `.confirmationDialog`: this project moved off those once
/// already, because they render as a small disconnected callout that doesn't belong to the
/// screen that opened them. The task editor's pickers are all in-house for the same reason.
struct BulkPrioritySheet: View {
    @Environment(\.dismiss) private var dismiss

    let count: Int
    var onPick: (Priority) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Priority")
                    .wpTypography(.screenTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                // Says what it will do before it does it. "Priority" alone leaves the user to
                // remember how many rows they ticked two taps ago.
                Text(count == 1 ? "For 1 task" : "For \(count) tasks")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
            }

            VStack(spacing: 8) {
                ForEach(Priority.allCases, id: \.self) { priority in
                    row(priority)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorTokens.surface1)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationBackground(ColorTokens.surface1)
    }

    private func row(_ priority: Priority) -> some View {
        Button {
            onPick(priority)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flag.fill")
                    .foregroundStyle(priority.tintColor)
                Text(priority.label)
                    .wpTypography(.cardTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                Spacer()
            }
            .padding(14)
            // `surface0` well inside the raised page, the same inversion the task editor uses
            // for its fields — not `surface1`, which would be the page itself.
            .background(ColorTokens.surface0)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
