import SwiftUI

/// Puts a locked screen behind glass instead of behind a closed door.
///
/// The first version of this hid things: a lock badge on the tab icon, and tapping it refused to
/// open the tab at all. That teaches people the app is small. A screen they can walk into and
/// see — blurred, with its real shape and its real density visible underneath — says the
/// opposite, because the thing being sold is right there being described by itself. No copy
/// argues for a feature as well as the feature's own silhouette.
///
/// The blur is **not** a security measure and nothing here pretends otherwise. It is a sales
/// surface drawn over the user's own device, holding the user's own data. What it must not do is
/// hold back something they'd be right to feel robbed of, which is why `TodayView` uses it on
/// days ahead and never on days gone: planning forward is a feature, and finished work is a
/// record.
private struct PaywallLock: ViewModifier {
    let isLocked: Bool
    let title: String
    let message: String

    @EnvironmentObject private var theme: ThemeManager
    @State private var showingPaywall = false

    func body(content: Content) -> some View {
        if isLocked {
            ZStack {
                content
                    // `allowsHitTesting(false)` rather than `.disabled` — disabled dims as well,
                    // and dimming already means something specific on these screens (a past
                    // day, a completed row). Two meanings for one treatment is how a reader
                    // learns to trust neither.
                    .blur(radius: 9)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                card
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        } else {
            content
        }
    }

    private var card: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.accentSwatch.markColor)
            Text(title)
                .wpTypography(.cardTitle)
                .foregroundStyle(ColorTokens.textPrimary)
            Text(message)
                .wpTypography(.body)
                .foregroundStyle(ColorTokens.textSecondary)
                .multilineTextAlignment(.center)
            Button { showingPaywall = true } label: {
                Text("See plans")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.surface0)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(ColorTokens.textPrimary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(24)
        .wpCard()
        .padding(.horizontal, 28)
    }
}

extension View {
    /// Blurs this view and offers the paywall over it when `isLocked`.
    ///
    /// Takes its own wording at each site rather than owning one generic sentence. A lock that
    /// says the same thing everywhere is a lock that says nothing: what's behind the Week tab
    /// and what's behind tomorrow are different purchases to make, and the card is the only
    /// place that difference gets explained.
    func lockedBehindPaywall(_ isLocked: Bool, title: String, message: String) -> some View {
        modifier(PaywallLock(isLocked: isLocked, title: title, message: message))
    }
}
