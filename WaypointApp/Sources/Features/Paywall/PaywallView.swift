import SwiftUI

/// Shown when a lapsed user tries to create something.
///
/// Deliberately not a feature list. Every feature is in both plans, so a checklist would be
/// padding — and by the time someone sees this they've used the app for a week and know what it
/// does. What it says instead is what they lose and what they keep.
struct PaywallView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var subscription: SubscriptionManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var selected: SubscriptionPlan = .annual

    @State private var errorMessage: String?

    /// The App Store's own localised price, or nothing.
    ///
    /// Deliberately no invented fallback. `mockPrice` returned "$1.99" to everyone on earth,
    /// which is wrong in every country that doesn't use dollars and wrong here the day a price
    /// changes in App Store Connect — the one number on this screen somebody is deciding on,
    /// hardcoded in Swift. An em dash while the store is still answering is honest; a made-up
    /// figure is not.
    private func price(for plan: SubscriptionPlan) -> String {
        subscription.prices[plan] ?? "—"
    }

    private var buyLabel: String {
        guard let price = subscription.prices[selected] else { return "Subscribe" }
        return "Subscribe — \(price) \(selected.cadence)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(headline)
                            .wpTypography(.appTitle)
                            .foregroundStyle(ColorTokens.textPrimary)
                        Text("Today stays yours, free, forever — and so does everything you've already done. A subscription is what opens the week ahead, your progress, and more than one goal.")
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 10) {
                        ForEach(SubscriptionPlan.allCases) { plan in
                            planRow(plan)
                        }
                    }

                    Button {
                        Task {
                            // Only dismiss on success. Cancelling used to close the sheet too,
                            // which reads as "bought" — the one misreading a paywall must not
                            // allow.
                            switch await subscription.purchase(selected) {
                            case .bought: dismiss()
                            case .cancelled: break
                            case .failed(let message): errorMessage = message
                            }
                        }
                    } label: {
                        Text(buyLabel)
                            .wpTypography(.cardTitle)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(theme.accentSwatch.color)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button("Restore purchases") {
                        Task {
                            switch await subscription.restore() {
                            case .bought: dismiss()
                            case .cancelled: break
                            case .failed(let message): errorMessage = message
                            }
                        }
                    }
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
                    .frame(maxWidth: .infinity)

                    // Apple requires the terms of an auto-renewing subscription to be visible at
                    // the point of purchase — length, price, and that it renews until cancelled.
                    // Omitting it is a common review rejection.
                    Text("Billed through your Apple ID. Renews automatically until cancelled; you can cancel any time in Settings.")
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(ColorTokens.surface0.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                        .foregroundStyle(ColorTokens.textSecondary)
                }
            }
        }
    }

    private var headline: String {
        switch subscription.status {
        case .trial(let daysLeft):
            daysLeft == 1 ? "Last day of your trial" : "\(daysLeft) days left in your trial"
        case .subscribed: "You're subscribed"
        case .free: "Your trial has ended"
        }
    }

    private func planRow(_ plan: SubscriptionPlan) -> some View {
        let isSelected = selected == plan
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selected = plan }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? theme.accentSwatch.markColor : ColorTokens.textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title)
                        .wpTypography(.cardTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                    // One price, no "then". There is no introductory offer: the launch price
                    // is the price, which means there is nothing a reader has to be warned
                    // about further down. A second line here would only be there to disclose a
                    // rise that isn't coming.
                    Text("\(price(for: plan)) \(plan.cadence)")
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textPrimary)
                }
                Spacer()
                if let note = plan.savingNote {
                    Text(note)
                        .wpTypography(.micro)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(theme.accentSwatch.color)
                        .clipShape(Capsule())
                }
            }
            .padding(15)
            .background(ColorTokens.elevatedFill(ColorTokens.surface1, tier: .resting, isDark: colorScheme == .dark))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? theme.accentSwatch.markColor : ColorTokens.border, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
