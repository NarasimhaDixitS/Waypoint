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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(headline)
                            .wpTypography(.appTitle)
                            .foregroundStyle(ColorTokens.textPrimary)
                        Text("Your tasks, goals and history stay on this device and stay readable. A subscription is what lets you add new work.")
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
                        subscription.purchase(selected)
                        dismiss()
                    } label: {
                        Text("Subscribe — \(selected.mockPrice) \(selected.cadence)")
                            .wpTypography(.cardTitle)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(theme.accentSwatch.color)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button("Restore purchases") {
                        subscription.restore()
                        dismiss()
                    }
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
                    .frame(maxWidth: .infinity)

                    // Apple requires the terms of an auto-renewing subscription to be visible at
                    // the point of purchase — length, price, and that it renews until cancelled.
                    // Omitting it is a common review rejection.
                    Text("Billed through your Apple ID. Renews automatically until cancelled; you can cancel any time in Settings. Prices shown are placeholders while payment is being built.")
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
        case .expired: "Your trial has ended"
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
                    Text("\(plan.mockPrice) \(plan.cadence)")
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textSecondary)
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
