import SwiftUI

struct MainTabView: View {
    @StateObject private var dateStore = DateNavigationStore()
    @State private var selectedTab = 0
    /// The first-of-month anchor for whichever month is currently browsed in the Week tab —
    /// persists across tab switches (browsing to next month, checking Today, coming back to
    /// Week keeps you on next month), separate from `weekRefreshTrigger` below.
    @State private var selectedMonth = WeekView.firstOfMonth(containing: .now)
    /// Bumped every time Week becomes the active tab, forcing it to fully rebuild (a fresh
    /// `init()`, a fresh task fetch) rather than just re-render. `WeekView`'s task fetch is a
    /// plain one-shot `@FetchRequest` set up once in `init` — it doesn't reliably pick up
    /// tasks created elsewhere (e.g. a multi-week repeat) while the tab isn't active, and
    /// merely re-rendering an already-alive instance isn't enough to catch it up.
    @State private var weekRefreshTrigger = 0

    /// Combines both reasons `WeekView` might need a fresh fetch — a different month, or just
    /// revisiting the tab — into one identity so `.id()` rebuilds on either.
    private struct WeekIdentity: Hashable {
        let month: Date
        let refreshTrigger: Int
    }

    /// A plain `$selectedTab` binding only updates on an actual value change, so tapping the
    /// Today tab while already on it fires nothing. This custom binding's setter runs on
    /// every tap regardless — including re-taps — so the Today tab can always reset the date,
    /// and Week can always force a fresh fetch.
    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == 0, !Calendar.current.isDateInToday(dateStore.selectedDate) {
                    // `.now` is a new Date value on every call (down to the second), so
                    // without this guard, re-tapping Today while already there would still
                    // count as a "change" and needlessly replay the jump animation.
                    withAnimation(.easeInOut(duration: 0.3)) {
                        dateStore.selectedDate = .now
                    }
                } else if newValue == 1 {
                    let currentMonth = WeekView.firstOfMonth(containing: .now)
                    if !Calendar.current.isDate(selectedMonth, equalTo: currentMonth, toGranularity: .month) {
                        // Same reasoning as the Today guard above — only animate the reset
                        // when it's an actual change, not on every re-tap.
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedMonth = currentMonth
                        }
                    }
                    weekRefreshTrigger += 1
                }
                selectedTab = newValue
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            NavigationStack { TodayView() }
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(0)

            NavigationStack {
                WeekView(
                    browsedMonth: selectedMonth,
                    onSelectDay: { day in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            dateStore.selectedDate = day
                            selectedTab = 0
                        }
                    },
                    onNavigateMonth: { newMonth in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedMonth = newMonth
                        }
                    }
                )
                .id(WeekIdentity(month: selectedMonth, refreshTrigger: weekRefreshTrigger))
            }
            .tabItem { Label("Week", systemImage: "calendar") }
            .tag(1)

            NavigationStack { ProgressAnalyticsView() }
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                .tag(2)

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
        }
        .tint(ColorTokens.textPrimary)
        .environmentObject(dateStore)
    }
}
