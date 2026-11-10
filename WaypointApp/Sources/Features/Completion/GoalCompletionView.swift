import SwiftUI

/// The one moment the app makes a fuss.
///
/// Deliberately the same object as `CompletionView`, which celebrates finishing a day: the
/// same spring on the mark, the same delayed rise on the text, the same single `Done`. A
/// second celebration invented from scratch would read as a different app arriving, and
/// finishing a goal is the bigger version of finishing a day, not a different kind of event.
///
/// What's different is the mark. A day gets a filled circle and a tick; a goal gets its own
/// ring, closed — the same ring that's been sitting at some fraction on the goal page for
/// weeks, arriving at the whole. That's the ring's one chance to be the thing on screen
/// rather than a statistic in the corner of a card.
///
/// **One moment, not several.** The haptic belongs to this screen rather than to the tap
/// that opened it — `TaskRowView` suppresses its own success while this is pending, so
/// ticking a goal's last task is a single event and not a success buzz followed by another.
struct GoalCompletionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeManager

    let celebration: GoalCelebration

    @State private var ringProgress: Double = 0
    @State private var markScale: CGFloat = 0.4
    @State private var markOpacity: Double = 0
    @State private var textOffset: CGFloat = 10
    @State private var textOpacity: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                ProgressRing(
                    progress: ringProgress,
                    lineWidth: 10,
                    color: theme.accentSwatch.markColor,
                    showsLabel: false
                )
                .frame(width: 132, height: 132)

                Image(systemName: "checkmark")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(theme.accentSwatch.markColor)
                    .scaleEffect(markScale)
                    .opacity(markOpacity)
            }

            VStack(spacing: 8) {
                Text("Goal complete")
                    .wpTypography(.screenTitle)
                    .foregroundStyle(ColorTokens.textPrimary)

                Text(celebration.name)
                    .wpTypography(.cardTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // The two numbers that say what it took. Not a streak and not a percentage —
                // one of those is about recent form and the other is now definitionally 100.
                Text("\(celebration.tasksDone) \(celebration.tasksDone == 1 ? "task" : "tasks") over \(celebration.days) \(celebration.days == 1 ? "day" : "days")")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
            }
            .padding(.horizontal, 32)
            .offset(y: textOffset)
            .opacity(textOpacity)

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.wpPrimary)
                .padding(.horizontal, 40)
                .opacity(textOpacity)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorTokens.surface0.ignoresSafeArea())
        .onAppear {
            // The ring closes first and the tick lands into it, rather than both arriving at
            // once — the point of the ring is the travel, and a mark that appears on top of a
            // ring still drawing itself hides the only part worth watching.
            withAnimation(.spring(response: 0.85, dampingFraction: 0.8)) {
                ringProgress = 1
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.45)) {
                markScale = 1
                markOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.6)) {
                textOffset = 0
                textOpacity = 1
            }
        }
        .sensoryFeedback(.success, trigger: markOpacity) { old, new in new > old }
    }
}

#Preview {
    GoalCompletionView(
        celebration: GoalCelebration(id: "preview", name: "Learn Spanish", days: 45, tasksDone: 38)
    )
    .environmentObject(ThemeManager.shared)
}
