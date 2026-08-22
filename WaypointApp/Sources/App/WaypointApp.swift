import SwiftUI

@main
struct WaypointApp: App {
    @StateObject private var theme = ThemeManager.shared
    @StateObject private var auth = AuthManager.shared
    let persistence = PersistenceController.shared

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
        }
    }
}
