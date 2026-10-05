import SwiftUI
import WidgetKit

@main
struct WaypointApp: App {
    @StateObject private var theme = ThemeManager.shared
    @StateObject private var subscription = SubscriptionManager.shared
    let persistence = PersistenceController.shared
    @State private var showingRecoveryNotice = false
    @Environment(\.scenePhase) private var scenePhase

    /// Reloads the demo fixture on launch: `-wpReseed`.
    ///
    /// Debug only, and a development affordance in the same family as `-wpTab`. The fixture is
    /// otherwise reachable only through a button in Settings, so every change to it had to be
    /// checked by asking whoever has the simulator to go and tap that — which is exactly the gap
    /// that led to shipping cards nobody had seen drawn.
    ///
    /// In `init`, deliberately, rather than on the first `.active` scene phase. A screen's
    /// `@FetchRequest` predicates are set from its `.onAppear`, which lands *before* that phase
    /// change: the Progress tab narrowed itself to four weeks and then had the whole store
    /// replaced underneath it, so it drew all-time figures under a "4 weeks" label. A flag whose
    /// whole purpose is looking at the numbers has to not change the numbers.
    private func reseedIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-wpReseed") else { return }
        SampleData.loadDemo(into: persistence.container.viewContext)
        #endif
    }

    init() {
        reseedIfRequested()
    }

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
                // Drawn immediately, never gated on the network.
                //
                // This used to wait for `auth.isReady` — a round trip to Supabase for an
                // anonymous session — before drawing anything, so the app sat on a blank screen
                // until that answered. With no connection it didn't skip, it waited for the
                // *failure*, which takes longer: worst exactly when someone is most impatient.
                //
                // Nothing needed the answer. Every task and goal is already on the device, and
                // the session's user id is read by nothing. A local app has no business asking
                // permission from a server before showing a user their own data.
                RootView()
                    .environment(\.managedObjectContext, persistence.container.viewContext)
                    .environmentObject(theme)
                    .environmentObject(subscription)
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
            .tint(theme.accentSwatch.color)
            // Rebuilds the whole tree when the palette changes. `ColorTokens` is read as a
            // static from twenty-nine files, and a view that reads a token without observing
            // `ThemeManager` has nothing to tell it the answer just changed — it would keep its
            // old colours until something unrelated made it redraw. Auditing all twenty-nine
            // for that is a worse bet than one forced rebuild on a setting nobody flips twice
            // a minute.
            //
            // **Before `preferredColorScheme`, not after.** `.id` re-creates the identity of
            // everything above it, and a colour scheme preference declared inside that gets
            // re-created along with it rather than reaching the window — so the app ignored
            // light/dark entirely and sat in whatever the system said. Ordering, not logic.
            .id(theme.palette)
            // Paper pins the scheme. It draws one way whatever light/dark says, and the status
            // bar and keyboard are the two surfaces the palette can't paint itself — left to
            // the system they'd come back dark over an off-white page.
            .preferredColorScheme(theme.palette.forcedColorScheme ?? theme.appearanceMode.colorScheme)
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
            // Redrawn when the app leaves the foreground, which is the moment the widget is
            // about to be the only thing the user sees. Cheaper and more reliable than trying
            // to catch every individual edit — WidgetKit coalesces these anyway.
            .onChange(of: scenePhase) { _, phase in
                let context = persistence.container.viewContext
                if phase == .active {
                    AppSessionLog.begin(in: context)
                    // Catches anything that became true while the app wasn't running — a goal
                    // finished by a deletion, a milestone that turned over at midnight. Both
                    // happen with nobody present, so neither can hang off a tap.
                    HistoryReconciler.run(in: context)
                    // Reminders were rebuilt only from Today's and a goal's `onAppear`, and
                    // nothing wakes the app in the background to do it — so a day nobody opened
                    // one of those two screens was a day with no reminders at all. Hanging it on
                    // the scene phase makes every launch and every return from background
                    // rebuild the window, whichever screen you land on.
                    NotificationManager.refreshTaskReminders(in: context, enabled: theme.notificationsEnabled)
                } else {
                    AppSessionLog.end(in: context)
                    WidgetCenter.shared.reloadAllTimelines()
                }
                try? context.save()
            }
        }
    }
}
