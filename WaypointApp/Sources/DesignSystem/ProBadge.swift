import SwiftUI

/// Marks a feature that's gated but not actually purchasable yet — muted on purpose, so it
/// reads as "not yet" rather than an active upsell. Callers should only show this when
/// `!theme.isPro` and should not route the tap to a paywall (see NewTaskView's "Add notes",
/// GoalCreateView's "AI-planned", AdhocBumpView's "Suggest best swap", and
/// ProgressAnalyticsView's lock overlay for the pattern).
struct ProBadge: View {
    var body: some View {
        Text("Soon")
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ColorTokens.border)
            .foregroundStyle(ColorTokens.textSecondary)
            .clipShape(Capsule())
    }
}
