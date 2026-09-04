import SwiftUI

struct TaskRowView: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var task: TaskEntity
    var onToggle: () -> Void
    var onStartFocus: () -> Void
    /// Opens the editor on an overdue task so a new date can be chosen. It used to move the
    /// task to tomorrow outright, in one tap — which is how a task gets pushed fourteen times
    /// without anyone noticing, and it filled the deferral log with reflexive taps rather than
    /// decisions. The affordance stays (an overdue row's checkbox is disabled, so without it
    /// the row has no visible way out); only the thoughtless default is gone.
    var onReschedule: () -> Void = {}
    /// True for any task not dated today — completion can only happen on the day itself,
    /// not early and not late after the fact. Move it to reschedule instead.
    var isCompletionLocked: Bool = false
    /// The next thing due today. Set only while nothing is in progress — when something is
    /// running, the pinned card at the top already answers "what now?" and a second marker
    /// would just be two answers to one question. See `DayTimelineView.nextTaskID`.
    var isNext: Bool = false

    @State private var bump = false
    @State private var celebrateTrigger = 0

    private var state: TaskState { task.state }

    /// State is depicted by *emphasis*, not by hue. A list is an attention ranking — in
    /// progress is loudest, pending is normal, upcoming and done recede — and only `overdue`
    /// spends a color, so that when red does appear it reads as an alarm instead of as one
    /// more entry in a four-hue rainbow. Done in particular used to carry the loudest
    /// treatment in the app (green tint + green ink + solid green disc) despite being the
    /// most common row by evening; now it dissolves into the page background and keeps a
    /// single accent-colored check as its reward. Everything distinguishing the states is a
    /// non-hue channel — size, weight, opacity, strikethrough, filled vs. dashed vs. open
    /// stroke — so the list stays legible without relying on color vision.
    ///
    /// The in-progress task is the one thing happening right now — it gets a real size jump
    /// (title, meta, icons, padding all scale up together), not just a tint change, so it reads
    /// as the focal point of the list at a glance rather than just a differently-colored row.
    private var isInProgress: Bool { state == .inProgress }

    var body: some View {
        HStack(spacing: isInProgress ? 16 : 12) {
            VStack(alignment: .leading, spacing: isInProgress ? 5 : 3) {
                Text(task.title ?? "")
                    .wpTypography(isInProgress ? .bigStat : .cardTitle)
                    .foregroundStyle(titleColor)
                    .strikethrough(state == .done)

                HStack(spacing: 7) {
                    Text(task.timeRangeLabel)
                        .wpTypography(.body)
                        .foregroundStyle(metaColor)
                    stateBadge
                }
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if state == .inProgress {
                Button(action: onStartFocus) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.accentSwatch.inProgressColor)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start focus session")
            }

            if state == .overdue {
                Button(action: onReschedule) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ColorTokens.warning)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reschedule this task")
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
                    CompletionBurst(trigger: celebrateTrigger, color: theme.accentSwatch.color)
                }
            }
            .buttonStyle(.plain)
            .disabled(isCompletionLocked)
            .accessibilityLabel(isCompletionLocked ? "Only completable on its scheduled day" : (state == .done ? "Mark as not done" : "Mark as done"))
        }
        .padding(isInProgress ? 20 : 14)
        .background {
            if state == .inProgress {
                TaskProgressWave(
                    start: task.resolvedStartTime,
                    end: task.endTime,
                    tint: theme.accentSwatch.inProgressTintColor,
                    line: theme.accentSwatch.inProgressColor
                )
            } else if let elevation {
                ColorTokens.elevatedFill(backgroundColor, tier: elevation.tier, isDark: colorScheme == .dark)
            } else {
                // Done: no lift, so no `elevatedFill` either — brightening it would undo the
                // dissolve into the page that says the task is finished.
                backgroundColor
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isInProgress ? 22 : 18, style: .continuous))
        .shadow(color: shadowColor, radius: elevation?.radius ?? 0, x: 0, y: elevation?.y ?? 0)
        .animation(.easeInOut(duration: 0.25), value: state == .done)
        .sensoryFeedback(.success, trigger: task.isDone) { old, new in new }
        .sensoryFeedback(.impact(weight: .light), trigger: task.isDone) { old, new in !new }
    }

    /// Only states that tell you something you can't already see get a word. Done has the
    /// strikethrough, the filled check and a dissolved card; in progress is twice the size
    /// with a moving waterline — labelling either just says the same thing a fourth time (and
    /// "in progress" was wide enough to wrap the meta line onto two lines). Overdue is the
    /// one state whose word is the point: red plus a time in the past doesn't tell you what's
    /// expected of you, so it gets a real flag. Upcoming keeps a quiet word only while the
    /// dashed marker is still an unlearned convention.
    @ViewBuilder
    private var stateBadge: some View {
        switch state {
        case .overdue:
            Text("OVERDUE")
                .wpTypography(.micro)
                .fontWeight(.semibold)
                .tracking(0.6)
                // White on `warning` measures 4.51:1 — clears AA for normal text, so the flag
                // stays readable rather than relying on the row tint it sits on.
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(ColorTokens.warning)
                .clipShape(Capsule())
        case .future:
            // Separated by the app's usual mid-dot ("Day 1 of 62 · 62 days left", "9:00 AM–5:00 PM
            // · Work"), kept at the time range's own size and ink so it reads as punctuation
            // between two facts rather than as part of the label. The overdue capsule needs no
            // such separator — a filled pill is already its own object.
            HStack(spacing: 5) {
                Text("·")
                    .wpTypography(.body)
                    .foregroundStyle(metaColor)
                Text("UPCOMING")
                    .wpTypography(.micro)
                    .fontWeight(.semibold)
                    .tracking(0.6)
                    // Not `textMuted`: 11pt semibold is small text, so it answers to 4.5:1, and
                    // muted measures 3.61 on a light card. `textSecondary` clears it at 6.49.
                    .foregroundStyle(ColorTokens.textSecondary)
            }
        case .pending where isNext:
            Text("NEXT")
                .wpTypography(.micro)
                .fontWeight(.semibold)
                .tracking(0.6)
                .foregroundStyle(ColorTokens.textSecondary)
        case .done, .inProgress, .pending:
            EmptyView()
        }
    }

    /// Elevation is the ladder's fourth channel, after size, ink and fill: what's live floats,
    /// what's finished lies flat. Uses the shared shadow tokens but a far tighter throw than
    /// `CardBackground`'s card-scale geometry (14pt blur dropped 10pt) — rows sit 8pt apart, so
    /// card values would spill each row's shadow across the one below it.
    private var elevation: (tier: ColorTokens.ShadowTier, radius: CGFloat, y: CGFloat)? {
        switch state {
        case .done: nil
        case .inProgress: (.raised, 10, 4)
        case .pending, .future, .overdue: (.resting, 6, 2)
        }
    }

    private var shadowColor: Color {
        switch elevation?.tier {
        case .raised: ColorTokens.shadowRaised
        case .resting: ColorTokens.shadowResting
        default: .clear
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .done:
            ZStack {
                Circle().fill(theme.accentSwatch.color)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
        case .inProgress:
            Circle()
                .stroke(theme.accentSwatch.inProgressColor, lineWidth: 2.5)
                .frame(width: 32, height: 32)
        case .overdue:
            Circle()
                .stroke(ColorTokens.warning, lineWidth: 1.6)
                .frame(width: 24, height: 24)
        case .future:
            // Dashed rather than purple: "not yet actionable" is carried by the broken
            // stroke, which reads at a glance without spending a hue on it.
            Circle()
                .stroke(ColorTokens.textMuted, style: StrokeStyle(lineWidth: 1.6, dash: [3, 3]))
                .frame(width: 24, height: 24)
        case .pending:
            Circle()
                .stroke(ColorTokens.border, lineWidth: 1.6)
                .frame(width: 24, height: 24)
        }
    }

    private var titleColor: Color {
        switch state {
        case .done: ColorTokens.textSecondary
        case .overdue: ColorTokens.textWarning
        case .future: ColorTokens.textSecondary
        case .inProgress: theme.accentSwatch.inProgressTextColor
        case .pending: ColorTokens.textPrimary
        }
    }

    private var metaColor: Color {
        switch state {
        case .done: ColorTokens.textMuted
        case .overdue: ColorTokens.textWarning.opacity(0.85)
        case .future: ColorTokens.textMuted
        case .inProgress: theme.accentSwatch.inProgressTextColor.opacity(0.85)
        case .pending: ColorTokens.textSecondary
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .done: ColorTokens.surface0
        case .overdue: ColorTokens.warningTint
        case .future: ColorTokens.surface1
        case .inProgress: theme.accentSwatch.inProgressTintColor
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
