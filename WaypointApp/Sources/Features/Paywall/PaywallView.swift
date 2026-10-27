import SwiftUI

/// Shown when a lapsed user tries to create something.
///
/// Deliberately not a feature list. By the time someone sees this they've used the app for a
/// fortnight and know exactly what it does — a checklist would be telling them about their own
/// last two weeks. What it says instead is what they lose and what they keep.
///
/// **It got much shorter when Waypoint stopped selling subscriptions.** Two plan rows, a
/// comparison between them, a note explaining what switching from one to the other would do to
/// your billing, a renewal disclosure, a cancelled state, a declined-card state, and a
/// "Manage subscription" link — all of it existed to explain a recurring charge. One payment
/// needs none of it. What's left is the name, the price, and a button.
struct PaywallView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?

    /// The App Store's own localised price, or nothing.
    ///
    /// **Deliberately no invented fallback.** This used to be a `mockPrice` returning "$1.99"
    /// to everyone on earth, which is wrong in every country that doesn't use dollars and wrong
    /// here the day the price changes in App Store Connect — the one number on this screen
    /// somebody is deciding on, hardcoded in Swift. An em dash while the store is still
    /// answering is honest; a made-up figure is not.
    private var price: String { subscription.price ?? "—" }

    private var isPurchased: Bool { subscription.status.isPurchased }

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

                    productCard

                    if isPurchased {
                        // No button rather than a dead one. There is genuinely nothing to buy
                        // here, and a greyed-out button invites tapping to find out why.
                        Text("You own this.")
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
                                switch await subscription.purchase() {
                                case .bought: dismiss()
                                case .cancelled: break
                                case .failed(let message): errorMessage = message
                                }
                            }
                        } label: {
                            Text("Unlock \(WaypointPro.name)")
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

                    // Kept prominent, and it earns it now. A one-time unlock is the sort of
                    // thing someone buys once and expects on every phone they ever own, and
                    // there is no account here to look them up by — the Apple Account is the
                    // only thread joining a new device to a purchase made years ago.
                    Button("Restore purchase") {
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

                    legalBlock
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(ColorTokens.surface0.ignoresSafeArea())
            // Ask again if we arrived without a price.
            //
            // It's fetched once at launch, and that one request can lose: a slow network, a
            // cold start, airplane mode on the train. The fallback is an em dash, which is
            // honest but useless — and a paywall showing no price at all is both the worst
            // possible conversion and something an App Store reviewer can reasonably reject,
            // since the price has to be visible at the point of purchase. Opening this screen
            // is the one moment it is certainly worth another try. Costs nothing in the normal
            // case, where the SDK answers from its own cache.
            .task { if subscription.price == nil { await subscription.syncWithStore() } }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                        .foregroundStyle(ColorTokens.textSecondary)
                }
            }
        }
    }

    /// Name, price, and the fact that it doesn't recur — the three things somebody needs before
    /// they decide, in one block.
    ///
    /// The product's name is here rather than assumed, because build 5 was rejected for not
    /// naming it: the screen showed "Monthly" and "Annual", which are durations. Apple requires
    /// the product's own title at the point of purchase.
    private var productCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(WaypointPro.name)
                .wpTypography(.cardTitle)
                .foregroundStyle(ColorTokens.textPrimary)
            HStack(spacing: 8) {
                Text(price)
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textPrimary)
                Text("one-time purchase")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ColorTokens.border, lineWidth: 1)
        )
    }

    /// One block, because it is one thing.
    ///
    /// **Much shorter than it was.** Guideline 3.1.2's disclosure — "renews automatically until
    /// cancelled" and the rest — governs auto-renewable subscriptions, and there is no renewal
    /// to disclose any more. Both links stay anyway: the privacy policy is the one claim this
    /// app makes about itself that somebody might reasonably want to read before paying, and
    /// removing something a reviewer has already been shown invites the question of why.
    private var legalBlock: some View {
        VStack(spacing: 6) {
            Text("One payment. \(WaypointPro.name) is yours for good, on every iPhone signed in to your Apple Account.")
                .wpTypography(.micro)
                .foregroundStyle(ColorTokens.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

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
        .padding(.top, 2)
    }

    private var headline: String {
        switch subscription.status {
        case .trial(let daysLeft):
            return daysLeft == 1 ? "Last day of your trial" : "\(daysLeft) days left in your trial"
        case .purchased:
            return "You have \(WaypointPro.name)"
        case .free:
            return "Your trial has ended"
        }
    }

    private var blurb: String {
        switch subscription.status {
        case .trial, .free:
            return "Today and your history stay free, always. \(WaypointPro.name) opens the rest — the week ahead, your progress, and as many goals as you want."
        case .purchased:
            return "Everything's unlocked, permanently. Thanks for paying for it."
        }
    }
}
