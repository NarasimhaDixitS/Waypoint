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

    private var currentPlan: SubscriptionPlan? {
        if case .subscribed(let plan, _, _) = subscription.status { return plan }
        return nil
    }

    private var renewal: Renewal? {
        if case .subscribed(_, _, let renewal) = subscription.status { return renewal }
        return nil
    }

    private var periodEnd: Date? {
        if case .subscribed(_, let until, _) = subscription.status { return until }
        return nil
    }

    /// What tapping the main button would actually do.
    ///
    /// **The paywall used to offer "Subscribe" to people who were already subscribed**, with no
    /// hint of what a second purchase meant. Tapping Monthly while holding Annual is a real
    /// thing Apple supports, and it does something quite specific — but the app said nothing,
    /// so the only way to find out was to buy.
    private enum Action { case subscribe, resubscribe, switchPlan, fixPayment, nothing }

    private var action: Action {
        guard let currentPlan else { return .subscribe }
        if selected != currentPlan { return .switchPlan }
        switch renewal {
        case .cancelled: return .resubscribe
        // Buying again does not fix a declined card, and the screen that does is Apple's.
        // Sending them there is the whole point of telling them, so it gets the main button
        // rather than a grey link under a line reading "this is your current plan".
        case .billingProblem: return .fixPayment
        default: return .nothing
        }
    }

    private var buyLabel: String {
        let price = subscription.prices[selected].map { " — \($0) \(selected.cadence)" } ?? ""
        switch action {
        case .subscribe: return "Subscribe\(price)"
        case .resubscribe: return "Resubscribe\(price)"
        case .switchPlan: return "Switch to \(selected.title)\(price)"
        case .fixPayment, .nothing: return ""
        }
    }

    /// When a plan change takes effect, said before the tap rather than discovered after it.
    ///
    /// The two directions behave completely differently and Apple decides which is which:
    /// moving to a longer period is an upgrade and happens at once with a pro-rata credit,
    /// while moving to a shorter one is a downgrade and waits for the paid period to run out.
    private var switchNote: String? {
        guard case .switchPlan = action, let currentPlan else { return nil }
        if currentPlan == .annual && selected == .monthly {
            let date = periodEnd?.formatted(.dateTime.day().month(.abbreviated).year()) ?? "your renewal date"
            return "Starts \(date), when your current year ends. Nothing changes before then, and you won't be charged today."
        }
        return "Switches over straight away. Apple credits you for the part of this period you haven't used, so you don't pay twice."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(headline)
                            .wpTypography(.appTitle)
                            .foregroundStyle(ColorTokens.textPrimary)
                        Text(blurb)
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

                    if let switchNote {
                        Text(switchNote)
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }

                    if case .fixPayment = action, let manage = AppLinks.manageSubscription {
                        Link(destination: manage) {
                            Text("Update payment method")
                                .wpTypography(.cardTitle)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(theme.accentSwatch.color)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    } else if case .nothing = action {
                        // No button rather than a dead one. There is genuinely nothing to buy
                        // here, and a greyed-out "Subscribe" invites tapping to find out why.
                        Text("This is your current plan.")
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    } else {
                        Button {
                            errorMessage = nil
                            Task {
                                // Only dismiss on success. Cancelling used to close the sheet
                                // too, which reads as "bought" — the one misreading a paywall
                                // must not allow.
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
                    }

                    // **This used to be set and never drawn.** Both the purchase and the
                    // restore paths wrote a message into state that no view read, so a failed
                    // purchase — and, worse, "no previous purchase found" after tapping
                    // Restore — looked exactly like a button that did nothing at all.
                    if let errorMessage {
                        Text(errorMessage)
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textWarning)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button("Restore purchases") {
                        errorMessage = nil
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

                    if currentPlan != nil, renewal != .billingProblem,
                       let manage = AppLinks.manageSubscription {
                        Link("Manage subscription", destination: manage)
                            .wpTypography(.body)
                            .foregroundStyle(ColorTokens.textSecondary)
                            .frame(maxWidth: .infinity)
                    }

                    // Apple requires the terms of an auto-renewing subscription to be visible at
                    // the point of purchase — length, price, and that it renews until cancelled.
                    // Omitting it is a common review rejection.
                    Text("Billed through your Apple ID. Renews automatically until cancelled; you can cancel any time in Settings.")
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    // The other half of 3.1.2, and the half that was missing: both links have
                    // to be functional and in the binary, not only in the App Store listing.
                    HStack(spacing: 8) {
                        if let terms = AppLinks.terms {
                            Link("Terms of Use", destination: terms)
                        }
                        if AppLinks.terms != nil && AppLinks.privacy != nil {
                            Text("·").foregroundStyle(ColorTokens.textMuted)
                        }
                        if let privacy = AppLinks.privacy {
                            Link("Privacy Policy", destination: privacy)
                        }
                    }
                    .wpTypography(.micro)
                    .tint(ColorTokens.textSecondary)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(ColorTokens.surface0.ignoresSafeArea())
            // Open on the plan they are actually on, not on the one we'd like to sell. A
            // subscriber landing on a preselected "Switch to Annual" reads as the app having
            // forgotten what they bought.
            .onAppear { if let currentPlan { selected = currentPlan } }
            .animation(.easeInOut(duration: 0.2), value: switchNote)
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
            return daysLeft == 1 ? "Last day of your trial" : "\(daysLeft) days left in your trial"
        case .subscribed(let plan, let until, let renewal):
            let date = until.formatted(.dateTime.day().month(.abbreviated).year())
            switch renewal {
            case .renewing: return "You're on \(plan.title)"
            case .cancelled: return "Your subscription ends \(date)"
            case .billingProblem: return "There's a problem with your payment"
            }
        case .free:
            return "Your trial has ended"
        }
    }

    private var blurb: String {
        switch subscription.status {
        case .trial, .free:
            return "Today stays yours, free, forever — and so does everything you've already done. A subscription is what opens the week ahead, your progress, and more than one goal."
        case .subscribed(_, _, let renewal):
            switch renewal {
            case .renewing:
                return "You have everything. You can change plan below, or manage the subscription itself in your Apple account."
            case .cancelled:
                // Nothing is being taken away early, and saying so plainly is the whole job of
                // this line. The alternative reads as a countdown designed to panic somebody.
                return "Nothing changes before then — you keep everything you have until the date. Resubscribe whenever you like and nothing is lost."
            case .billingProblem:
                return "You still have full access while Apple retries the payment. Updating your payment method in your Apple account will sort it out."
            }
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
                // "Current" outranks "Best value": which plan you are already paying for is a
                // fact about you, and the sales badge is not.
                if plan == currentPlan {
                    Text("Current")
                        .wpTypography(.micro)
                        .fontWeight(.semibold)
                        .foregroundStyle(ColorTokens.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .overlay { Capsule().stroke(ColorTokens.border, lineWidth: 1) }
                } else if let note = plan.savingNote {
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
