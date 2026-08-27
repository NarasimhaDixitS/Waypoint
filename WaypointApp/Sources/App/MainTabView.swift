import SwiftUI
import CoreData

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
    /// Global search, reachable from every tab via the nav bar — not itself a tab (selecting
    /// it doesn't change `selectedTab`), just an overlay above whichever tab is showing.
    @State private var searchActive = false

    /// Combines both reasons `WeekView` might need a fresh fetch — a different month, or just
    /// revisiting the tab — into one identity so `.id()` rebuilds on either.
    private struct WeekIdentity: Hashable {
        let month: Date
        let refreshTrigger: Int
    }

    private func selectTab(_ newValue: Int) {
        if newValue == 0, !Calendar.current.isDateInToday(dateStore.selectedDate) {
            // `.now` is a new Date value on every call (down to the second), so without this
            // guard, re-tapping Today while already there would still count as a "change" and
            // needlessly replay the jump animation.
            withAnimation(.easeInOut(duration: 0.3)) {
                dateStore.selectedDate = .now
            }
        } else if newValue == 1 {
            let currentMonth = WeekView.firstOfMonth(containing: .now)
            if !Calendar.current.isDate(selectedMonth, equalTo: currentMonth, toGranularity: .month) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    selectedMonth = currentMonth
                }
            }
            weekRefreshTrigger += 1
        }
        selectedTab = newValue
    }

    var body: some View {
        ZStack {
            ZStack {
                NavigationStack { TodayView() }
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 0)

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
                .opacity(selectedTab == 1 ? 1 : 0)
                .allowsHitTesting(selectedTab == 1)

                NavigationStack { ProgressAnalyticsView() }
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 2)

                NavigationStack { SettingsView() }
                    .opacity(selectedTab == 3 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 3)
            }

            if searchActive {
                GlobalSearchOverlay(
                    onSelectTask: { task in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            dateStore.selectedDate = task.resolvedDate
                            selectedTab = 0
                            searchActive = false
                        }
                    },
                    onCancel: { searchActive = false }
                )
                .transition(.opacity)
            }
        }
        // Reserving the tab bar's space via safeAreaInset (rather than layering it as a plain
        // ZStack sibling) is what lets every screen's own safe-area-relative positioning — the
        // FAB, the undo toast — clear it automatically, the same as the native TabView's bar
        // used to do before this replaced it. A fixed-offset guess would silently break the
        // moment the bar's own height changed.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CustomTabBar(
                selectedTab: Binding(get: { selectedTab }, set: selectTab),
                searchActive: $searchActive
            )
        }
        .animation(.easeInOut(duration: 0.22), value: searchActive)
        .environmentObject(dateStore)
    }
}

/// Replaces the native `TabView` chrome entirely — a fully custom bar so the selected item can
/// read in the user's accent color instead of a fixed neutral tint, matching every other
/// accent-dependent element in the app. Search lives here as a fifth item rather than in
/// Today's own header, so it works the same regardless of which tab is showing; tapping it
/// toggles `searchActive` instead of changing `selectedTab`, since it isn't a screen you land
/// on and stay on.
private struct CustomTabBar: View {
    @EnvironmentObject private var theme: ThemeManager
    @Binding var selectedTab: Int
    @Binding var searchActive: Bool

    private struct Item {
        let icon: String
        let filledIcon: String?
        let label: String
    }

    private let items: [Item] = [
        Item(icon: "sun.max", filledIcon: "sun.max.fill", label: "Today"),
        Item(icon: "calendar", filledIcon: nil, label: "Week"),
        Item(icon: "chart.bar", filledIcon: "chart.bar.fill", label: "Progress"),
        Item(icon: "gearshape", filledIcon: "gearshape.fill", label: "Settings")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                let isSelected = !searchActive && selectedTab == index
                Button {
                    if searchActive { searchActive = false }
                    selectedTab = index
                } label: {
                    tabLabel(
                        icon: isSelected ? (items[index].filledIcon ?? items[index].icon) : items[index].icon,
                        label: items[index].label,
                        isSelected: isSelected
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                searchActive.toggle()
            } label: {
                tabLabel(icon: "magnifyingglass", label: "Search", isSelected: searchActive)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(ColorTokens.surface1)
        .overlay(alignment: .top) {
            Rectangle().fill(ColorTokens.border).frame(height: 1)
        }
        .shadow(color: ColorTokens.shadowRaised, radius: 14, x: 0, y: -2)
    }

    private func tabLabel(icon: String, label: String, isSelected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
            Text(label)
                .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
        }
        .foregroundStyle(isSelected ? theme.accentSwatch.color : ColorTokens.textMuted)
        .frame(maxWidth: .infinity)
    }
}

/// Full-text search across every task, reachable from any tab — an overlay rather than a
/// sheet, so the field sits right above the nav bar instead of taking over the whole screen.
/// Matches on title or goal name; selecting a result jumps Today to that task's day.
private struct GlobalSearchOverlay: View {
    @EnvironmentObject private var theme: ThemeManager
    var onSelectTask: (TaskEntity) -> Void
    var onCancel: () -> Void

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \TaskEntity.startTime, ascending: true)])
    private var allTasks: FetchedResults<TaskEntity>

    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [TaskEntity] {
        guard !trimmedQuery.isEmpty else { return [] }
        return allTasks.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(trimmedQuery)
                || ($0.goal?.name ?? "").localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 10) {
                resultsPanel
                searchFieldRow
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .onAppear { fieldFocused = true }
    }

    @ViewBuilder
    private var resultsPanel: some View {
        if trimmedQuery.isEmpty {
            hint("Search your tasks by title or goal.")
        } else if results.isEmpty {
            hint("No tasks match \u{201C}\(trimmedQuery)\u{201D}.")
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(results, id: \.objectID) { task in
                        resultRow(task)
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 320)
            .background(ColorTokens.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: ColorTokens.shadowFloating, radius: 24, x: 0, y: 12)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .wpTypography(.body)
            .foregroundStyle(ColorTokens.textSecondary)
            .multilineTextAlignment(.center)
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(ColorTokens.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: ColorTokens.shadowFloating, radius: 24, x: 0, y: 12)
    }

    private var searchFieldRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ColorTokens.textMuted)
                TextField("Search tasks", text: $query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($fieldFocused)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(ColorTokens.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(ColorTokens.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: ColorTokens.shadowRaised, radius: 14, x: 0, y: 6)

            Button("Cancel", action: onCancel)
                .foregroundStyle(theme.accentSwatch.color)
        }
    }

    private func resultRow(_ task: TaskEntity) -> some View {
        Button {
            onSelectTask(task)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(taskDotColor(task))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title ?? "")
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textPrimary)
                        .strikethrough(task.isDone)
                        .lineLimit(1)
                    Text("\(task.resolvedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(task.timeRangeLabel)")
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ColorTokens.textMuted)
            }
            .padding(10)
            .background(ColorTokens.surface0)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func taskDotColor(_ task: TaskEntity) -> Color {
        switch task.state {
        case .done: ColorTokens.success
        case .overdue: ColorTokens.warning
        case .future: ColorTokens.scheduled
        case .inProgress: ColorTokens.inProgress
        case .pending: ColorTokens.textMuted
        }
    }
}
