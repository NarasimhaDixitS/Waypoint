import SwiftUI

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingFlowView(onFinished: {
                    hasCompletedOnboarding = true
                    if theme.notificationsEnabled {
                        NotificationManager.requestAuthorizationIfNeeded()
                        NotificationManager.scheduleDailySummary()
                    }
                })
            }
        }
        .background(ColorTokens.surface0.ignoresSafeArea())
    }
}

private struct OnboardingFlowView: View {
    enum Stage { case welcome, schedule, sleep }
    @State private var stage: Stage = .welcome
    var onFinished: () -> Void

    var body: some View {
        switch stage {
        case .welcome:
            WelcomeView(onContinue: { stage = .schedule })
        case .schedule:
            ScheduleSetupView(onFinished: { stage = .sleep })
        case .sleep:
            SleepSetupView(onFinished: onFinished)
        }
    }
}
