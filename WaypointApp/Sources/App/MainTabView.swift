import SwiftUI
import CoreData
import UIKit

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

/// Replaces the native `TabView` chrome entirely — a floating, inset pill in solid accent
/// color, with the current tab shown as a raised circular badge that pops up out of the bar's
/// top edge (not just a same-plane highlight) — high-contrast neutral fill (black in light
/// mode, white in dark), the icon on it inverted to match, independent of which accent is
/// active. Search lives here as a fifth item rather than in Today's own header, so it works
/// the same regardless of which tab is showing; tapping it toggles `searchActive` instead of
/// changing `selectedTab`, since it isn't a screen you land on and stay on.
private struct CustomTabBar: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTab: Int
    @Binding var searchActive: Bool

    private let icons = ["sun.max", "calendar", "chart.bar", "gearshape", "magnifyingglass"]
    private let filledIcons: [String?] = ["sun.max.fill", nil, "chart.bar.fill", "gearshape.fill", nil]

    private let barHeight: CGFloat = 68
    private let badgeDiameter: CGFloat = 66
    /// How far the badge's top sticks up above the bar's own top edge.
    private let badgeLift: CGFloat = 14
    private let notchWidth: CGFloat = 86
    /// Deep enough that the pocket's low point still sits right at the badge's own bottom edge
    /// (badgeDiameter - badgeLift) even after lowering the badge, so the badge keeps reading as
    /// sunk in all the way rather than merely nicking the bar's top line.
    private let notchDepth: CGFloat = 52

    private var activeIndex: Int { searchActive ? 4 : selectedTab }
    private var iconColor: Color { colorScheme == .dark ? .white : .black }
    private var badgeFill: Color { colorScheme == .dark ? .white : .black }
    private var badgeIconColor: Color { colorScheme == .dark ? .black : .white }

    private func select(_ index: Int) {
        if index == 4 {
            searchActive.toggle()
        } else {
            if searchActive { searchActive = false }
            selectedTab = index
        }
    }

    var body: some View {
        GeometryReader { geo in
            let slotWidth = geo.size.width / CGFloat(icons.count)
            let notchCenterX = slotWidth * CGFloat(activeIndex) + slotWidth / 2

            ZStack(alignment: .topLeading) {
                NotchedBarShape(notchCenterX: notchCenterX, notchWidth: notchWidth, notchDepth: notchDepth)
                    .fill(theme.accentSwatch.color)
                    .frame(height: barHeight)
                    .shadow(color: ColorTokens.shadowRaised, radius: 22, x: 0, y: 18)
                    .offset(y: badgeLift)

                HStack(spacing: 0) {
                    ForEach(icons.indices, id: \.self) { index in
                        Button { select(index) } label: {
                            Group {
                                if index == activeIndex {
                                    Color.clear
                                } else {
                                    Image(systemName: icons[index])
                                        .font(.system(size: 22))
                                        .foregroundStyle(iconColor.opacity(0.7))
                                }
                            }
                            .frame(width: slotWidth, height: barHeight)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .offset(y: badgeLift)

                Button { select(activeIndex) } label: {
                    ZStack {
                        Circle()
                            .fill(badgeFill)
                            .shadow(color: ColorTokens.shadowRaised, radius: 14, x: 0, y: 8)
                        Image(systemName: filledIcons[activeIndex] ?? icons[activeIndex])
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(badgeIconColor)
                    }
                    .frame(width: badgeDiameter, height: badgeDiameter)
                }
                .buttonStyle(.plain)
                .frame(width: slotWidth, alignment: .center)
                .offset(x: slotWidth * CGFloat(activeIndex))
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.7), value: activeIndex)
        }
        .frame(height: barHeight + badgeLift)
        .padding(.horizontal, 20)
    }
}

/// A pill whose top edge cuts into a deep, smooth pocket around `notchCenterX` — instead of a
/// flat edge with the badge simply floating above it — so the badge reads as sunk in right down
/// to its own bottom edge, matching the reference the user pointed to. Both sides of the pocket
/// are a single cubic curve down to a shared, full-depth low point (not a flat floor bridged by
/// a straight line) — a flat floor at differing depths per side needs a connecting line, and
/// that line is what read as a sharp diagonal wedge when the badge sat near the pill's rounded
/// end and one side had far less room than the other. A shared apex stays one smooth curve
/// however lopsided the two sides get. `notchCenterX` is animatable so the pocket slides in sync
/// with the badge as the selected tab changes.
private struct NotchedBarShape: Shape {
    var notchCenterX: CGFloat
    let notchWidth: CGFloat
    let notchDepth: CGFloat

    var animatableData: CGFloat {
        get { notchCenterX }
        set { notchCenterX = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.height / 2
        let halfNotch = notchWidth / 2
        let leftShoulder = max(notchCenterX - halfNotch, r)
        let rightShoulder = min(notchCenterX + halfNotch, rect.width - r)
        // Control-point offsets scale with the ACTUAL clamped span on each side, not the
        // nominal half-notch width — a near-edge badge clamps one shoulder in close, and using
        // the unclamped width there overshoots the tiny remaining segment into a self-crossing
        // loop instead of a smooth dip.
        let leftSpan = max(notchCenterX - leftShoulder, 0)
        let rightSpan = max(rightShoulder - notchCenterX, 0)

        var path = Path()
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: leftShoulder, y: 0))
        path.addCurve(
            to: CGPoint(x: notchCenterX, y: notchDepth),
            control1: CGPoint(x: leftShoulder + leftSpan * 0.55, y: 0),
            control2: CGPoint(x: notchCenterX - leftSpan * 0.55, y: notchDepth)
        )
        path.addCurve(
            to: CGPoint(x: rightShoulder, y: 0),
            control1: CGPoint(x: notchCenterX + rightSpan * 0.55, y: notchDepth),
            control2: CGPoint(x: rightShoulder - rightSpan * 0.55, y: 0)
        )
        path.addLine(to: CGPoint(x: rect.width - r, y: 0))
        path.addArc(center: CGPoint(x: rect.width - r, y: r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: r, y: rect.height))
        path.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
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
            // A real frosted blur of whatever's behind (the current tab's content), not a flat
            // dark scrim — reads as "the page is still there, just blurred," not a popup
            // dropped on top of it.
            Rectangle()
                .fill(.ultraThinMaterial)
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
            .shadow(color: ColorTokens.shadowFloating, radius: 30, x: 0, y: 28)
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
            .shadow(color: ColorTokens.shadowFloating, radius: 30, x: 0, y: 28)
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
            .shadow(color: ColorTokens.shadowRaised, radius: 22, x: 0, y: 18)

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
        case .inProgress: theme.accentSwatch.inProgressColor
        case .pending: ColorTokens.textMuted
        }
    }
}
