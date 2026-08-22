import SwiftUI

@main
struct WaypointApp: App {
    @StateObject private var theme = ThemeManager.shared
    let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .environmentObject(theme)
                .tint(theme.accentSwatch.color)
                .preferredColorScheme(theme.appearanceMode.colorScheme)
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
        }
    }
}
