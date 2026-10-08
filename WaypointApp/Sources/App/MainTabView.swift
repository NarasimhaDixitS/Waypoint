import SwiftUI
import CoreData
import UIKit

struct MainTabView: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var dateStore = DateNavigationStore()
    @EnvironmentObject private var subscription: SubscriptionManager
    @State private var showingPaywall = false
    @State private var selectedTab = MainTabView.launchTab
    /// The goals tab is the only one that pushes anything, so it's the only one that needs a
    /// path. Re-tapping a tab you're already on should return you to its root — standard
    /// everywhere in iOS, and without it a pushed goal page had no way back at all once the
    /// navigation bar was hidden.
    @State private var goalPath = NavigationPath()

    /// Lets a build be launched straight onto a given tab: `-wpTab 1`.
    ///
    /// Debug only, and purely a development affordance — every screen but Today is otherwise
    /// three taps from a cold launch, which makes looking at one from the outside slower than
    /// it should be, and "I couldn't see it" has been the cause of more than one bad call here.
    /// Release builds always open on Today.
    private static var launchTab: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-wpTab"), flag + 1 < args.count,
              let tab = Int(args[flag + 1]), (0...4).contains(tab) else { return 0 }
        return tab
        #else
        return 0
        #endif
    }
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
    @State private var searchActive = MainTabView.launchSearch != nil

    /// `-wpSearch spanish` opens the search overlay with that query already typed. Debug only,
    /// same family as `-wpTab` and `-wpNewTask`, and for the same reason: the overlay is behind
    /// a tap, the simulator is driven by hand, and the alternative is shipping a screen nobody
    /// has seen drawn — which is exactly how search shipped sorted oldest-first.
    static var launchSearch: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-wpSearch"), flag + 1 < args.count else { return nil }
        return args[flag + 1]
        #else
        return nil
        #endif
    }
    /// Bumped by the "+" button docked beside the tab bar to tell TodayView to present the
    /// new-task sheet — see `TodayView.addTaskTrigger`. Docking the button in the tab bar's own
    /// fixed chrome (rather than floating it over each tab's scrollable content, as before)
    /// means it can never end up rendered on top of a list row's own controls, whatever that
    /// row's size or position happens to be.
    @State private var addTaskTrigger = 0
    /// Bumped whenever the Today tab is selected; see `TodayView.returnToTodayTrigger`.
    @State private var returnToTodayTrigger = 0

    /// Whether the Progress tab has a chart the user hasn't been shown yet.
    ///
    /// Recomputed on `scenePhase` rather than watched continuously: the charts that are ready
    /// change on the scale of days, and a `@FetchRequest` over every task and event here to
    /// catch it sooner would cost a fetch on this view for something that moves once a week.
    @State private var progressHasNews = false

    /// One fetch, on launch and on return to the foreground.
    ///
    /// Not a `@FetchRequest`: that would re-run on every task edit anywhere in the app, to
    /// answer a question whose answer changes roughly once a week. A chart becoming readable
    /// is not news that needs to arrive within the second.
    private func markProgressSeen() {
        ProgressNews.markSeen(currentlyReadyCharts())
        progressHasNews = false
    }

    private func refreshProgressNews() {
        progressHasNews = !ProgressNews.unseen(in: currentlyReadyCharts()).isEmpty
    }

    private func currentlyReadyCharts() -> Set<ProgressChart> {
        let context = PersistenceController.shared.container.viewContext
        let tasks = (try? context.fetch(TaskEntity.fetchRequest())) ?? []
        let events = (try? context.fetch(TaskEventEntity.fetchRequest(kind: nil))) ?? []
        let sessions = (try? context.fetch(NSFetchRequest<FocusSessionEntity>(entityName: "FocusSessionEntity"))) ?? []
        let goals = (try? context.fetch(NSFetchRequest<GoalEntity>(entityName: "GoalEntity"))) ?? []

        return ProgressReadiness.ready(
            tasks: tasks,
            events: events,
            sessions: sessions,
            goal: goals.first { !$0.sortedTasks.isEmpty },
            effortWeeks: 6
        )
    }

    /// What the Progress lock says, which depends on how much the person has actually built up.
    private var progressLockMessage: String {
        let days = TrialRecord.daysSinceStart()
        guard days >= 3 else {
            return "Waypoint keeps recording what you finish and what you put off. Subscribing is what lets you read it back."
        }
        return "You've built up \(days) days of patterns in here. Subscribing is what keeps reading them back."
    }

    /// Combines both reasons `WeekView` might need a fresh fetch — a different month, or just
    /// revisiting the tab — into one identity so `.id()` rebuilds on either.
    private struct WeekIdentity: Hashable {
        let month: Date
        let refreshTrigger: Int
    }

    private var isViewingPastDay: Bool {
        let cal = Calendar.current
        return cal.startOfDay(for: dateStore.selectedDate) < cal.startOfDay(for: .now)
    }

    private func selectTab(_ newValue: Int) {
        // Arriving at Today should show today, including in the carousel. It keeps its own page
        // otherwise, so leaving on goal three and coming back lands you on goal three — the
        // Today tab not showing today, which is the one thing it exists to do.
        if newValue == 0 { returnToTodayTrigger += 1 }
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
        } else if newValue == 3 {
            // **Here, not in `ProgressAnalyticsView.onAppear`.** Every tab lives in the same
            // `ZStack` and is hidden with `.opacity`, so that view appears at launch whether or
            // not anyone opens it — which marked every chart seen before the badge had a chance
            // to show, silently defeating the entire feature. Selecting the tab is the only
            // event that actually means "looked at".
            markProgressSeen()
        } else if newValue == 2, selectedTab == 2, !goalPath.isEmpty {
            // Already on Goals and already pushed in: the tap means "take me back out", the
            // same as every other iOS tab bar. Only when it's already the current tab — a tap
            // that switches *to* Goals should land wherever you left off.
            withAnimation(.easeInOut(duration: 0.25)) {
                goalPath.removeLast(goalPath.count)
            }
        }
        selectedTab = newValue
    }

    /// Unlike `selectTab`, this never forces the "jump to today" side effect when already on
    /// Today — someone browsing a future day who taps "+" almost certainly wants a task on
    /// *that* day, not to be bounced back to today first.
    private func requestAddTask() {
        // The gate. On the free tier today is still fully yours — make, edit and finish as much
        // as you like. What's bought is everything *around* today: planning forward, the week,
        // the patterns. So this blocks adding work to a day that isn't today, and nothing else.
        //
        // Note which way round that is. Nothing already written is ever taken away; the limit
        // falls on new work on other days, which a free user has no way to reach anyway.
        guard subscription.status.canEditDay(dateStore.selectedDate) else {
            showingPaywall = true
            return
        }
        if selectedTab != 0 {
            selectedTab = 0
        }
        addTaskTrigger += 1
    }

    var body: some View {
        ZStack {
            ZStack {
                NavigationStack {
                    TodayView(
                        addTaskTrigger: addTaskTrigger,
                        returnToTodayTrigger: returnToTodayTrigger
                    )
                }
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
                    // Deliberately NOT keyed on the month. It used to be, which tore the whole
                    // view down and rebuilt it on every month step — taking its `@State` and,
                    // fatally, any in-flight transition with it. That is why stepping months
                    // snapped while switching modes (plain internal state) slid correctly.
                    // WeekView now retargets its own fetch when the month changes.
                    .id(weekRefreshTrigger)
                }
                .lockedBehindPaywall(
                    !subscription.status.canUseWeekTab,
                    title: "Your week",
                    message: "Seeing the week as a whole, and moving work around inside it, is part of the subscription."
                )
                .opacity(selectedTab == 1 ? 1 : 0)
                .allowsHitTesting(selectedTab == 1)

                NavigationStack(path: $goalPath) { GoalCenterView(path: $goalPath) }
                    .opacity(selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 2)

                NavigationStack { ProgressAnalyticsView() }
                    .lockedBehindPaywall(
                        !subscription.status.canUseProgress,
                        title: "Your patterns",
                        // Names what they already own rather than listing features. A concrete
                        // thing you've built up and stand to stop reading is a stronger reason
                        // than a list of charts you've never seen.
                        message: progressLockMessage
                    )
                    .opacity(selectedTab == 3 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 3)

                NavigationStack { SettingsView() }
                    .opacity(selectedTab == 4 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 4)
            }
            // A crossfade, not a slide: the tabs aren't laid out in a row, so sliding would
            // imply an order that doesn't exist — and it would fight Today's own left/right
            // day swipe, which does mean something directional.
            .animation(.easeInOut(duration: 0.2), value: selectedTab)

            if searchActive {
                GlobalSearchOverlay(
                    onSelectTask: { task in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            dateStore.selectedDate = task.resolvedDate
                            selectedTab = 0
                            searchActive = false
                        }
                    },
                    onSelectGoal: { goal in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            goalPath = NavigationPath()
                            goalPath.append(GoalRoute.goal(goal.objectID))
                            selectedTab = 2
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
        // undo toast — clear it automatically, the same as the native TabView's bar used to do
        // before this replaced it. A fixed-offset guess would silently break the moment the
        // bar's own height changed. The "+" button lives in this same reserved chrome, right
        // beside the pill, rather than floating over each tab's own scrollable content — see
        // `addTaskTrigger`'s doc comment for why that used to be a real problem.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 14) {
                CustomTabBar(
                    selectedTab: Binding(get: { selectedTab }, set: selectTab),
                    searchActive: $searchActive,
                    progressHasNews: progressHasNews
                )
                .frame(maxWidth: .infinity)
                // A past day is a record, not a workspace: completion is locked to a task's
                // own scheduled day, so anything filed into yesterday could never be ticked
                // off — it could only accumulate as permanent overdue debt. Keyed on
                // `dateStore` rather than the tab because `requestAddTask` routes every tab's
                // "+" through Today, which files the task on `selectedDate`.
                if !isViewingPastDay {
                    addTaskButton
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isViewingPastDay)
            .padding(.horizontal, 20)
        }
        .animation(.easeInOut(duration: 0.22), value: searchActive)
        .onAppear { refreshProgressNews() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshProgressNews() }
        }
        // Leaving Progress is when the dot should go, and `markSeen` has just run there.
        .onChange(of: selectedTab) { _, _ in refreshProgressNews() }
        .wpTopFade()
        .environmentObject(dateStore)
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        // waypoint://today, ://week, ://goals, ://progress, ://settings — one route per tab.
        //
        // The widget only ever asks for `today`, which it does so the app opens on today rather
        // than wherever the user last was. The rest exist because a tab is a reasonable thing
        // for a Shortcut or a future widget to link to, and because a screen nothing can open
        // directly is a screen nobody can look at without tapping their way there.
        .onOpenURL { url in
            guard url.scheme == "waypoint" else { return }
            let tab: Int? = switch url.host {
            case "today": 0
            case "week": 1
            case "goals": 2
            case "progress": 3
            case "settings": 4
            default: nil
            }
            guard let tab else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                if tab == 0 { dateStore.selectedDate = .now }
                selectTab(tab)
            }
        }
        // A trial ends by the clock moving, and nothing fires an event when it does. Without
        // this, an app left open across the boundary would keep letting someone create work
        // until they happened to relaunch it.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            subscription.refresh()
        }
    }

    /// Docked in the tab bar's own reserved chrome instead of floating over Today's content —
    /// see `addTaskTrigger`'s doc comment.
    private var addTaskButton: some View {
        // 68pt to match CustomTabBar.barHeight below — same visual height as the pill it's
        // docked beside, not an arbitrary FAB size left over from when it floated separately.
        Button(action: requestAddTask) {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(theme.accentSwatch.color)
                .clipShape(Circle())
                .shadow(color: ColorTokens.ShadowTier.raised.color, radius: ColorTokens.ShadowTier.raised.radius, x: 0, y: ColorTokens.ShadowTier.raised.y)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New task")
        // CustomTabBar's own frame is barHeight + badgeLift tall (extra room reserved above the
        // pill for the selected badge to pop up into), which shifts the *pill's* visual center
        // down by badgeLift/2 within that frame. This button has no such reservation, so
        // without this offset it centers 7pt too high relative to the pill beside it.
        .offset(y: 7)
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
    /// Progress has a chart it hasn't shown this person yet.
    var progressHasNews: Bool = false

    // Day, week, goals, patterns, settings — widening scope left to right, with search last
    // because it isn't a place, it's a way of getting to one.
    private let icons = ["checklist", "calendar", "target", "chart.line.uptrend.xyaxis", "gearshape", "magnifyingglass"]
    // Only `gearshape` has a filled twin among these. The others fall through to their
    // outline, which the badge can carry: a filled chip in the reversed colour is already a
    // much louder selection marker than a filled glyph would be.
    private let filledIcons: [String?] = [nil, nil, nil, nil, "gearshape.fill", nil]

    private let barHeight: CGFloat = 68
    /// Badge and notch are scaled by ~0.82 against the five-slot version (66 / 86 / 52), which
    /// is exactly the ratio that keeps them the same fraction of a slot now there are six:
    /// the badge was 1.23 slots wide and still is, the notch was 1.6 and still is. `barHeight`
    /// and `badgeLift` are deliberately untouched, so the bar sits where it always sat — only
    /// what rides on it got smaller.
    private let badgeDiameter: CGFloat = 54
    /// How far the badge's top sticks up above the bar's own top edge.
    private let badgeLift: CGFloat = 14
    private let notchWidth: CGFloat = 70
    /// Deep enough that the pocket's low point still sits right at the badge's own bottom edge
    /// (badgeDiameter - badgeLift) even after lowering the badge, so the badge keeps reading as
    /// sunk in all the way rather than merely nicking the bar's top line.
    private let notchDepth: CGFloat = 40

    private var activeIndex: Int { searchActive ? 5 : selectedTab }
    // These sit *on the accent-filled bar*, so they have to contrast with the accent, not with
    // the page. Two wrong answers got here before the right one: literal black/white, which
    // paper has no business showing, and then `textPrimary`, which is near-black in paper — on
    // a bar whose fill is also near-black, so every icon vanished.
    private var iconColor: Color { theme.accentSwatch.onFillColor }
    private var badgeFill: Color { theme.accentSwatch.onAccentColor }
    private var badgeIconColor: Color { theme.accentSwatch.onAccentReversedColor }

    private func select(_ index: Int) {
        if index == 5 {
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
                    .shadow(color: ColorTokens.ShadowTier.raised.color, radius: ColorTokens.ShadowTier.raised.radius, x: 0, y: ColorTokens.ShadowTier.raised.y)
                    .offset(y: badgeLift)

                HStack(spacing: 0) {
                    ForEach(icons.indices, id: \.self) { index in
                        Button { select(index) } label: {
                            Group {
                                if index == activeIndex {
                                    Color.clear
                                } else {
                                    // No lock badge here, deliberately. A locked tab icon
                                    // refuses to open and teaches people the app is small; the
                                    // tab opens and shows what's inside it, blurred, which
                                    // argues for itself far better than a padlock does.
                                    Image(systemName: icons[index])
                                        .font(.system(size: 19))
                                        // 0.85, not 0.7: on the teal fill that's 4.49:1
                                        // against 3.58:1, and the badge is a filled chip in
                                        // the reversed colour, so selection doesn't need the
                                        // unselected glyphs held that far back to read.
                                        .foregroundStyle(iconColor.opacity(0.85))
                                        // A chart has started speaking since this tab was last
                                        // opened. Only ever on Progress, and only when it isn't
                                        // the tab you're already looking at — a dot on the page
                                        // you're reading is a dot about nothing.
                                        .overlay(alignment: .topTrailing) {
                                            if index == 3, progressHasNews, activeIndex != 3 {
                                                Circle()
                                                    .fill(iconColor)
                                                    .frame(width: 6, height: 6)
                                                    .offset(x: 5, y: -3)
                                            }
                                        }
                                }
                            }
                            .frame(width: slotWidth, height: barHeight)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .offset(y: badgeLift)

                // `UnfadedButtonStyle`, not `.plain` — see the style's own note. The badge is
                // the lid on the notch, and a lid that goes translucent under a thumb is how
                // the pocket underneath became visible as a hard dip.
                Button { select(activeIndex) } label: {
                    ZStack {
                        Circle()
                            .fill(badgeFill)
                            .shadow(color: ColorTokens.ShadowTier.raised.color, radius: ColorTokens.ShadowTier.raised.radius, x: 0, y: ColorTokens.ShadowTier.raised.y)
                        Image(systemName: filledIcons[activeIndex] ?? icons[activeIndex])
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(badgeIconColor)
                    }
                    .frame(width: badgeDiameter, height: badgeDiameter)
                }
                .buttonStyle(UnfadedButtonStyle())
                .frame(width: slotWidth, alignment: .center)
                .offset(x: slotWidth * CGFloat(activeIndex))
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.7), value: activeIndex)
        }
        .frame(height: barHeight + badgeLift)
    }
}

/// Renders its label exactly as given, with no pressed appearance at all.
///
/// `.buttonStyle(.plain)` fades its label while a finger is down. That is right for almost
/// everything and wrong for the tab bar's selected badge: the badge circle is the only thing
/// covering `NotchedBarShape`'s pocket, so fading it doesn't dim a button — it opens a window
/// onto the notch carved into the bar beneath, which reads as the bar suddenly developing a
/// sharp dip that lasts as long as the press. A tester reported it as two separate bugs
/// ("goes transparent" and "there's a dip"); they are one.
///
/// Deliberately no substitute feedback — no scale, no opacity. The badge already answers the
/// press by sliding to the tapped tab, and anything else competes with that animation.
///
/// The unselected icons keep `.plain`. Nothing hides behind them, and the fade is useful there.
private struct UnfadedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
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
/// Goals first, then the tasks that match their own text. See `SearchResults`.
private struct GlobalSearchOverlay: View {
    @EnvironmentObject private var theme: ThemeManager
    var onSelectTask: (TaskEntity) -> Void
    var onSelectGoal: (GoalEntity) -> Void
    var onCancel: () -> Void

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \TaskEntity.startTime, ascending: true)])
    private var allTasks: FetchedResults<TaskEntity>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \GoalEntity.createdAt, ascending: false)])
    private var allGoals: FetchedResults<GoalEntity>

    @State private var query = MainTabView.launchSearch ?? ""
    @FocusState private var fieldFocused: Bool
    /// Measured, because a `ScrollView` takes every point it is offered. Capping it at 320 made
    /// the panel 320 tall whether it held one row or twenty, so a single result floated at the
    /// top of a mostly-empty card.
    @State private var contentHeight: CGFloat = 0

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var taskResults: [TaskEntity] {
        SearchResults.tasks(matching: trimmedQuery, in: Array(allTasks))
    }

    private var goalResults: [GoalEntity] {
        SearchResults.goals(matching: trimmedQuery, in: Array(allGoals))
    }

    private var isEmpty: Bool { taskResults.isEmpty && goalResults.isEmpty }

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
            hint("Search goals and tasks. Notes count too.")
        } else if isEmpty {
            hint("Nothing matches \u{201C}\(trimmedQuery)\u{201D}.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !goalResults.isEmpty {
                        sectionLabel("Goals")
                        ForEach(goalResults, id: \.objectID) { goal in
                            goalRow(goal)
                        }
                    }
                    if !taskResults.isEmpty {
                        sectionLabel("Tasks")
                            .padding(.top, goalResults.isEmpty ? 0 : 6)
                        ForEach(taskResults, id: \.objectID) { task in
                            resultRow(task)
                        }
                    }
                }
                .padding(14)
                .background(
                    GeometryReader { proxy in
                        // Written from `onAppear`/`onChange` rather than through a
                        // `PreferenceKey`: the key reported 0.0 forever when this pattern was
                        // first used for the clash sheet's detent, and this is the same shape.
                        Color.clear
                            .onAppear { contentHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, h in contentHeight = h }
                    }
                )
            }
            .frame(height: min(max(contentHeight, 60), 320))
            .background(ColorTokens.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: ColorTokens.ShadowTier.floating.color, radius: ColorTokens.ShadowTier.floating.radius, x: 0, y: ColorTokens.ShadowTier.floating.y)
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
            .shadow(color: ColorTokens.ShadowTier.floating.color, radius: ColorTokens.ShadowTier.floating.radius, x: 0, y: ColorTokens.ShadowTier.floating.y)
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
            .shadow(color: ColorTokens.ShadowTier.raised.color, radius: ColorTokens.ShadowTier.raised.radius, x: 0, y: ColorTokens.ShadowTier.raised.y)

            Button("Cancel", action: onCancel)
                .foregroundStyle(theme.accentSwatch.color)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .wpTypography(.micro)
            .fontWeight(.semibold)
            .tracking(0.6)
            .foregroundStyle(ColorTokens.textSecondary)
            .padding(.horizontal, 2)
    }

    /// A goal, with the one line that says whether it's going well — so the result answers
    /// "how's that going" without a tap, and the tap takes you to the rest.
    private func goalRow(_ goal: GoalEntity) -> some View {
        Button {
            onSelectGoal(goal)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "target")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accentSwatch.markColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.name ?? "Untitled goal")
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textPrimary)
                        .lineLimit(1)
                    Text("\(goal.doneTaskCount) of \(goal.sortedTasks.count) done\(goal.daysRemaining > 0 ? " · \(goal.daysRemaining) days to go" : "")")
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textSecondary)
                        .lineLimit(1)
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
        .buttonStyle(.wpRow)
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
                    // The goal name is here because it no longer gets you here: a task is a
                    // match on its own words now, so this is the only thing saying what it
                    // belongs to.
                    Text("\(task.resolvedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(task.timeRangeLabel)\(task.goal?.name.map { " · \($0)" } ?? "")")
                        .wpTypography(.micro)
                        .foregroundStyle(ColorTokens.textSecondary)
                        .lineLimit(1)
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
        .buttonStyle(.wpRow)
    }

    private func taskDotColor(_ task: TaskEntity) -> Color {
        switch task.state {
        // Mirrors `TaskRowView`'s emphasis ladder at dot scale: done is the accent, overdue
        // is the only warning hue, and upcoming just sits back from pending.
        case .done: theme.accentSwatch.markColor
        case .overdue: ColorTokens.warning
        case .future: ColorTokens.textMuted.opacity(0.45)
        case .inProgress: theme.accentSwatch.inProgressColor
        case .pending: ColorTokens.textMuted
        }
    }
}
