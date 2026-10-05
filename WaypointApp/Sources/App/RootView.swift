import SwiftUI

struct RootView: View {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @EnvironmentObject private var theme: ThemeManager

    /// Two steps on a first run — a welcome, then setup — and the app after that.
    ///
    /// There used to be a sign-in gate in front of both, and nothing was reachable behind it.
    /// It protected nothing: every task is in a database on this device, so the gate only ever
    /// established whose work it was, and it did that by hardcoding one name for everybody.
    /// Purchases don't need it either — the App Store ties those to the buyer's Apple ID.
    ///
    /// Shipping accounts would also have committed the app to offering account deletion in
    /// perpetuity, which is a real obligation to take on for a database that never leaves the
    /// phone. If sync ever arrives, sign-in arrives with it.
    var body: some View {
        Group {
            if !hasSeenWelcome {
                WelcomeView(onContinue: { hasSeenWelcome = true })
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
        .animation(.easeInOut(duration: 0.28), value: hasSeenWelcome)
        .background(ColorTokens.surface0.ignoresSafeArea())
    }
}

struct SetupFlowView: View {
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
