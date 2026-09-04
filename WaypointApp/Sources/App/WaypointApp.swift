import SwiftUI

@main
struct WaypointApp: App {
    @StateObject private var theme = ThemeManager.shared
    @StateObject private var auth = AuthManager.shared
    let persistence = PersistenceController.shared
    @State private var showingRecoveryNotice = false

    private var recoveryMessage: String {
        switch persistence.recovery {
        case .setAside:
            // Deliberately not "your data is gone" — it isn't. Saying so would push people into
            // deleting the app, which is the one action that would actually destroy it.
            return "Your tasks and goals are safe on this device, but this version of Waypoint couldn't open them, so it started with an empty list. Don't delete the app — an update will restore them."
        case .unavailable:
            return "Waypoint couldn't set up storage on this device. Anything you add now won't be saved. Restarting the app may fix it."
        case nil:
            return ""
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isReady {
                    RootView()
                        .environment(\.managedObjectContext, persistence.container.viewContext)
                        .environmentObject(theme)
                        .environmentObject(auth)
                        .onAppear {
                            // Only prime the real system permission prompt for users who already
                            // completed onboarding in a previous launch — a first-time user hasn't
                            // engaged with the app yet, so this fires again right after they finish
                            // onboarding instead (see RootView).
                            guard UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") else { return }
                            if theme.notificationsEnabled {
                                NotificationManager.requestAuthorizationIfNeeded()
                                NotificationManager.scheduleDailySummary()
                            }
                        }
                } else {
                    ColorTokens.surface0.ignoresSafeArea()
                }
            }
            .tint(theme.accentSwatch.color)
            .preferredColorScheme(theme.appearanceMode.colorScheme)
            // The store failing to load used to kill the app on its launch screen. It now opens
            // regardless, so the one thing left to get right is telling the user the truth: their
            // data still exists, this build just couldn't read it.
            .alert("Couldn't open your data", isPresented: $showingRecoveryNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(recoveryMessage)
            }
            .onAppear {
                showingRecoveryNotice = persistence.recovery != nil
            }
        }
    }
}
