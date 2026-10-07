import SwiftUI
import CoreData

/// Every goal in one place, plus the work that belongs to none of them.
///
/// **Why this exists.** Goals were only ever reachable by swiping the banner on Today. That is
/// fine as a glance and wrong as the only door: with four goals, three of them are invisible,
/// and there was nowhere at all to see a goal's tasks as a set rather than one day at a time.
///
/// **Why "No goal" is a card and not a filter.** Unattached tasks are most of what a new user
/// has, and they are exactly the pile that needs tidying in bulk — forty tasks typed in a hurry
/// with the wrong duration. Hiding them behind a toggle would mean the one group most in need
/// of this screen was the one group not on it.
/// Where the goal centre can navigate to.
///
/// Value-based routes rather than `NavigationLink { destination }`, because only these update
/// the stack's `path` binding — and that binding is what lets re-tapping the Goals tab pop
/// back out. Goals are carried as `NSManagedObjectID` so the route stays `Hashable` and can't
/// outlive the object it names.
enum GoalRoute: Hashable {
    case goal(NSManagedObjectID)
    case ungrouped
}

struct GoalCenterView: View {
    @Binding var path: NavigationPath
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var subscription: SubscriptionManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \GoalEntity.createdAt, ascending: false)],
        animation: .default
    )
    private var goals: FetchedResults<GoalEntity>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TaskEntity.date, ascending: true)],
        predicate: NSPredicate(format: "goal == nil"),
        animation: .default
    )
    private var ungrouped: FetchedResults<TaskEntity>

    // `-wpGoal` / `-wpNoGoal` push straight to one of these screens on launch. Debug only,
    // same family as `-wpTab` and `-wpNewTask`, and for the same reason: they're two taps deep,
    // the simulator is driven by hand, and the alternative is shipping changes to them unseen.

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                ForEach(goals) { goal in
                    NavigationLink(value: GoalRoute.goal(goal.objectID)) {
                        GoalCard(goal: goal)
                    }
                    .buttonStyle(.plain)
                }

                // Always present, even at zero. A card reading "nothing loose" is a useful
                // answer; a card that vanishes leaves you wondering where the loose tasks went.
                NavigationLink(value: GoalRoute.ungrouped) {
                    ungroupedCard
                }
                .buttonStyle(.plain)

                if goals.isEmpty {
                    emptyNote
                }
            }
            .padding(20)
            .padding(.bottom, ColorTokens.tabBarClearance)
        }
        .background(ColorTokens.surface0.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationDestination(for: GoalRoute.self) { route in
            switch route {
            case .goal(let id):
                if let goal = try? context.existingObject(with: id) as? GoalEntity {
                    GoalDetailView(goal: goal)
                }
            case .ungrouped:
                UngroupedTasksView()
            }
        }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            guard path.isEmpty else { return }
            if args.contains("-wpGoal"), let first = goals.first {
                path.append(GoalRoute.goal(first.objectID))
            } else if args.contains("-wpNoGoal") {
                path.append(GoalRoute.ungrouped)
            }
            #endif
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Goals")
                .wpTypography(.appTitle)
                .foregroundStyle(ColorTokens.textPrimary)
            Text(goals.isEmpty ? "Nothing set yet" : "\(goals.count) in progress")
                .wpTypography(.body)
                .foregroundStyle(ColorTokens.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var ungroupedCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 20))
                .foregroundStyle(ColorTokens.textSecondary)
                .frame(width: 44, height: 44)
                .background(ColorTokens.surface0)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("No goal")
                    .wpTypography(.cardTitle)
                    .foregroundStyle(ColorTokens.textPrimary)
                Text(ungrouped.isEmpty
                     ? "Everything is attached to a goal"
                     : "\(ungrouped.count) task\(ungrouped.count == 1 ? "" : "s") on their own")
                    .wpTypography(.body)
                    .foregroundStyle(ColorTokens.textSecondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ColorTokens.textMuted)
        }
        .wpCard()
    }

    private var emptyNote: some View {
        Text("A goal gives your tasks somewhere to add up to. Create one from Today's banner.")
            .wpTypography(.body)
            .foregroundStyle(ColorTokens.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}

/// One goal, summarised.
///
/// Carries the same seven-day strip the Today banner uses rather than inventing a second
/// vocabulary for "how's it going" — a card here and the banner there should agree at a glance.
private struct GoalCard: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject var goal: GoalEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.name ?? "Untitled goal")
                        .wpTypography(.cardTitle)
                        .foregroundStyle(ColorTokens.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(subtitle)
                        .wpTypography(.body)
                        .foregroundStyle(ColorTokens.textSecondary)
                }

                Spacer(minLength: 8)

                ProgressRing(
                    progress: goal.completionFraction,
                    lineWidth: 5,
                    color: theme.accentSwatch.markColor,
                    labelFont: .system(size: 12, weight: .semibold)
                )
                .frame(width: 48, height: 48)
            }

            Divider().overlay(ColorTokens.border)

            GoalWeekStrip(
                days: goal.recentCompletion(),
                activeSince: goal.createdAt,
                // Ink, not white: this card is `surface1`, not the accent-filled banner.
                tint: ColorTokens.textPrimary
            )
                .frame(maxWidth: .infinity)
        }
        .wpCard()
    }

    private var subtitle: String {
        let done = goal.doneTaskCount
        let total = goal.sortedTasks.count
        let remaining = goal.daysRemaining
        let timing = remaining > 0
            ? "\(remaining) day\(remaining == 1 ? "" : "s") to go"
            // Past its date and not finished. Said plainly rather than hidden: a goal whose
            // deadline has gone is the one you most need to be told about.
            : (goal.completionFraction >= 1 ? "Finished" : "Past its date")
        return "\(done) of \(total) done · \(timing)"
    }
}

/// The tasks that belong to no goal.
///
/// Deliberately not a `GoalDetailView` with an optional goal: nearly everything on that screen
/// — the ring, the burndown, the heatmap, the streak — is a statement about a goal's shape over
/// time, and a pile of unrelated tasks has no shape. What they share is the list and its
/// selection, which is `SelectableTaskList`.
struct UngroupedTasksView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var subscription: SubscriptionManager

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TaskEntity.date, ascending: true)],
        predicate: NSPredicate(format: "goal == nil"),
        animation: .default
    )
    private var tasks: FetchedResults<TaskEntity>

    @State private var editingTask: TaskEntity?

    var body: some View {
        SelectableTaskList(
            title: "No goal",
            subtitle: tasks.isEmpty ? "Nothing here" : "\(tasks.count) task\(tasks.count == 1 ? "" : "s")",
            tasks: Array(tasks),
            emptyMessage: "Tasks you create without picking a goal land here.",
            onEditTask: { editingTask = $0 }
        )
        .sheet(item: $editingTask) { task in
            NewTaskView(
                existingTask: task,
                defaultDate: task.resolvedDate,
                onSave: { draft, existing in
                    // **Known limit, stated rather than hidden.** Changing a task's time from
                    // here does not run the clash-and-cascade flow, because these tasks share
                    // nothing but the absence of a goal — there is no single day in view to
                    // resolve collisions against, and shuffling tasks on a day this screen
                    // can't show would be a change nobody could see happen.
                    //
                    // Today owns collisions. Everything this screen does in bulk — priority,
                    // goal, delete — leaves time alone, which is why bulk needs no equivalent.
                    if let existing { existing.apply(draft, in: context) }
                    try? context.save()
                    editingTask = nil
                },
                onDelete: {
                    if let id = task.id { NotificationManager.cancelReminder(taskID: id) }
                    TaskEventLog.recordAbandonmentIfNeeded(task: task, in: context)
                    context.delete(task)
                    try? context.save()
                    editingTask = nil
                }
            )
        }
    }
}
