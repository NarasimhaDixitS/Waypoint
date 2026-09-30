import SwiftUI

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var account: AccountManager

    /// Three gates, in order: signed in, set up, then the app.
    ///
    /// Sign-in comes first and nothing is reachable behind it. Worth being clear-eyed about
    /// what that costs, since it's a deliberate choice rather than a default: every task lives
    /// on this device, so the gate isn't protecting anything — it's establishing whose work it
    /// is. The bill for that arrives the day the stub becomes a real Apple request, because
    /// anyone who declines it, or opens the app somewhere with no signal, is then locked out
    /// of a to-do list sitting intact on their own phone. That's the trade being made.
    var body: some View {
        Group {
            if !account.isSignedIn {
                WelcomeView(onSignIn: { account.signIn() })
            } else if hasCompletedOnboarding {
                MainTabView()
            } else {
                SetupFlowView(onFinished: {
                    hasCompletedOnboarding = true
                    if theme.notificationsEnabled {
                        NotificationManager.requestAuthorizationIfNeeded()
                        NotificationManager.scheduleDailySummary()
                    }
                })
            }
        }
        .animation(.easeInOut(duration: 0.28), value: account.isSignedIn)
        .background(ColorTokens.surface0.ignoresSafeArea())
    }
}

/// What's left of onboarding once the welcome screen became the sign-in gate.
private struct SetupFlowView: View {
    enum Stage { case schedule, sleep }
    @State private var stage: Stage = .schedule
    var onFinished: () -> Void

    var body: some View {
        switch stage {
        case .schedule:
            ScheduleSetupView(onFinished: { stage = .sleep })
        case .sleep:
            SleepSetupView(onFinished: onFinished)
        }
    }
}
