import SwiftUI

struct TaskRowView: View {
    @ObservedObject var task: TaskEntity
    var onToggle: () -> Void
    var onStartFocus: () -> Void
    /// Moves this task to the same time tomorrow — offered only while overdue, as a
    /// deliberately per-task action (see the doc comment on `TodayView.rescheduleToTomorrow`
    /// for why this isn't a bulk "move everything" button).
    var onReschedule: () -> Void = {}
    /// True for any task not dated today — completion can only happen on the day itself,
    /// not early and not late after the fact. Move it to reschedule instead.
    var isCompletionLocked: Bool = false

    @State private var bump = false
    @State private var celebrateTrigger = 0

    private var state: TaskState { task.state }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title ?? "")
                    .wpTypography(.cardTitle)
                    .foregroundStyle(titleColor)
                    .strikethrough(state == .done)

                HStack(spacing: 5) {
                    Text(task.timeRangeLabel)
                    switch state {
                    case .done: Text("· done")
                    case .overdue: Text("· overdue")
                    case .future: Text("· upcoming")
                    case .inProgress: Text("· in progress")
                    case .pending: EmptyView()
                    }
                }
                .wpTypography(.body)
                .foregroundStyle(metaColor)
            }

            Spacer(minLength: 8)

            if state == .inProgress {
                Button(action: onStartFocus) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ColorTokens.inProgress)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start focus session")
            }

            if state == .overdue {
                Button(action: onReschedule) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ColorTokens.warning)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Move to tomorrow")
            }

            if let notes = task.notes, !notes.isEmpty {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundStyle(metaColor)
            }

            Button {
                let willComplete = !task.isDone
                bump = true
                onToggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { bump = false }
                if willComplete {
                    celebrateTrigger += 1
                }
            } label: {
                // CompletionBurst sits alongside statusIcon in this ZStack, not chained onto
                // it via `.overlay` — statusIcon's `switch state` changes which view *type*
                // renders on pending→done, and an overlay attached to that switch gets torn
                // down and rebuilt along with it, losing the burst's own animation state
                // mid-flight. A stable sibling slot survives that transition.
                ZStack {
                    statusIcon
                        .scaleEffect(bump ? 1.18 : 1)
                        .opacity(isCompletionLocked ? 0.4 : 1)
                        .animation(.spring(response: 0.32, dampingFraction: 0.45), value: bump)
                    CompletionBurst(trigger: celebrateTrigger, color: ColorTokens.success)
                }
            }
            .buttonStyle(.plain)
            .disabled(isCompletionLocked)
            .accessibilityLabel(isCompletionLocked ? "Only completable on its scheduled day" : (state == .done ? "Mark as not done" : "Mark as done"))
        }
        .padding(14)
        .background {
            if state == .inProgress {
                TaskProgressWave(
                    start: task.resolvedStartTime,
                    end: task.endTime,
                    tint: ColorTokens.inProgressTint,
                    line: ColorTokens.inProgress
                )
            } else {
                backgroundColor
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: state == .done)
        .sensoryFeedback(.success, trigger: task.isDone) { old, new in new }
        .sensoryFeedback(.impact(weight: .light), trigger: task.isDone) { old, new in !new }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .done:
            ZStack {
                Circle().fill(ColorTokens.success)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
        case .inProgress:
            Circle()
                .stroke(ColorTokens.inProgress, lineWidth: 2)
                .frame(width: 24, height: 24)
        case .overdue:
            Circle()
                .stroke(ColorTokens.warning, lineWidth: 1.6)
                .frame(width: 24, height: 24)
        case .future:
            Circle()
                .stroke(ColorTokens.scheduled, lineWidth: 1.6)
                .frame(width: 24, height: 24)
        case .pending:
            Circle()
                .stroke(ColorTokens.border, lineWidth: 1.6)
                .frame(width: 24, height: 24)
        }
    }

    private var titleColor: Color {
        switch state {
        case .done: ColorTokens.textSuccess
        case .overdue: ColorTokens.textWarning
        case .future: ColorTokens.textScheduled
        case .inProgress: ColorTokens.textInProgress
        case .pending: ColorTokens.textPrimary
        }
    }

    private var metaColor: Color {
        switch state {
        case .done: ColorTokens.textSuccess.opacity(0.85)
        case .overdue: ColorTokens.textWarning.opacity(0.85)
        case .future: ColorTokens.textScheduled.opacity(0.85)
        case .inProgress: ColorTokens.textInProgress.opacity(0.85)
        case .pending: ColorTokens.textSecondary
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .done: ColorTokens.successTint
        case .overdue: ColorTokens.warningTint
        case .future: ColorTokens.scheduledTint
        case .inProgress: ColorTokens.inProgressTint
        case .pending: ColorTokens.surface1
        }
    }
}

struct ScheduleBlockRow: View {
    var commitment: CommitmentEntity
    var start: Date
    var end: Date

    @State private var collapsed = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { collapsed.toggle() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: commitment.iconSystemName)
                    .font(.system(size: 12))
                Text("\(start.formatted(.dateTime.hour().minute()))–\(end.formatted(.dateTime.hour().minute()))")
                Text("· \(commitment.name ?? "") (fixed)")
                    .lineLimit(1)
                Spacer()
            }
            .wpTypography(.body)
            .foregroundStyle(ColorTokens.textSecondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .padding(.horizontal, 4)
        .accessibilityLabel("\(commitment.name ?? "Commitment"), fixed, \(start.formatted(.dateTime.hour().minute())) to \(end.formatted(.dateTime.hour().minute()))")
        .accessibilityHint(collapsed ? "Double tap to expand" : "Double tap to collapse")
    }
}
