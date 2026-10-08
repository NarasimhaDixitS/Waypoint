import Foundation

/// The charts on the Progress page, and whether each one has anything to say yet.
///
/// **Why this exists rather than each card deciding for itself.** Every card already knows
/// when it's empty — it used that to draw an apology where a chart would go. A new user met
/// four or five of those at once: a title, a paragraph explaining a chart, and a line saying
/// it isn't there. Nothing on the screen was about them.
///
/// Lifting the question out lets the page do three better things with the same answer: skip
/// the card entirely, count what's still to come, and — the one that matters — notice the
/// moment a chart *starts* speaking, so the tab can say so.
///
/// It deliberately calls the same `ProgressAnalytics` functions the cards do. A second
/// implementation of "is this empty" would drift, and the drift would show up as a badge
/// promising a chart that turns out to be blank.
enum ProgressChart: String, CaseIterable {
    case weekday, timeOfDay, effort, goalSplit
    case deferral, underestimate, slip, priority, habit
    case burndown, estimate

    /// Used only in the day-one pitch, so it has to read as a promise rather than a feature
    /// name: something the app will tell you, in the words it will tell you it in.
    var promise: String {
        switch self {
        case .weekday: "which day of the week you actually deliver on"
        case .timeOfDay: "what time of day your work really happens"
        case .effort: "how your planned hours compare with the ones you did"
        case .goalSplit: "where your time actually goes, by goal"
        case .deferral: "what you keep pushing to tomorrow"
        case .underestimate: "what you keep giving too little time to"
        case .slip: "how far you move things when you move them"
        case .priority: "whether you do the things you marked important"
        case .habit: "which repeats you keep and which you quietly drop"
        case .burndown: "whether you're on pace for a goal's deadline"
        case .estimate: "how far off your time estimates are"
        }
    }
}

enum ProgressReadiness {

    /// Which charts currently have data. Same inputs and same functions the cards use.
    static func ready(
        tasks: [TaskEntity],
        events: [TaskEventEntity],
        sessions: [FocusSessionEntity],
        goal: GoalEntity?,
        effortWeeks: Int
    ) -> Set<ProgressChart> {
        var ready: Set<ProgressChart> = []

        if ProgressAnalytics.completionByWeekday(tasks).contains(where: { $0.total > 0 }) {
            ready.insert(.weekday)
        }
        // Eight is the card's own threshold, not a round number: below it the clock positions
        // are too sparse to read as a time of day rather than as noise.
        if ProgressAnalytics.observedCompletionCount(tasks) >= 8 {
            ready.insert(.timeOfDay)
        }
        if ProgressAnalytics.effortByWeek(tasks, weeks: effortWeeks).contains(where: { $0.plannedMinutes > 0 }) {
            ready.insert(.effort)
        }
        if !ProgressAnalytics.effortByGoal(tasks).isEmpty { ready.insert(.goalSplit) }
        if !ProgressAnalytics.deferralLeaderboard(events).isEmpty { ready.insert(.deferral) }
        if !ProgressAnalytics.underestimates(events).isEmpty { ready.insert(.underestimate) }
        // The buckets themselves are fixed — four of them, always returned — so `isEmpty` is
        // never true and would have marked this ready on a brand-new account with no events at
        // all. The card checks the total, and so must this.
        if ProgressAnalytics.slipDistribution(events).reduce(0, { $0 + $1.count }) > 0 {
            ready.insert(.slip)
        }
        if ProgressAnalytics.priorityFollowThrough(tasks).contains(where: { $0.total > 0 }) {
            ready.insert(.priority)
        }
        if !ProgressAnalytics.seriesAdherence(tasks).isEmpty { ready.insert(.habit) }
        if let goal, !ProgressAnalytics.burndown(for: goal).isEmpty { ready.insert(.burndown) }
        if !ProgressAnalytics.estimateAccuracy(sessions: sessions, tasks: tasks, limit: .max).isEmpty {
            ready.insert(.estimate)
        }

        return ready
    }
}

/// Remembers which charts the user has already been told about.
///
/// **The point of the whole feature.** A chart becoming readable is the single most persuasive
/// thing this app does — the moment it tells you something about yourself you hadn't worked
/// out. It used to happen silently, on a tab nobody reopens on day six, and by the time anyone
/// looked the news was old. A dot on the tab turns a static page into one that occasionally
/// has something to say.
///
/// Stored rather than derived, because "new" is a fact about what the user has seen and
/// nothing in the data can answer it.
enum ProgressNews {
    private static let key = "progress.announcedCharts"

    private static var announced: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: key) }
    }

    /// Charts that have become readable since the user last opened Progress.
    static func unseen(in ready: Set<ProgressChart>) -> Set<ProgressChart> {
        ready.subtracting(announced.compactMap(ProgressChart.init(rawValue:)))
    }

    /// Called when Progress is opened: everything readable has now been seen.
    ///
    /// Marks the charts that are ready *now* rather than all of them, so a chart that becomes
    /// readable later still gets its moment.
    static func markSeen(_ ready: Set<ProgressChart>) {
        announced = announced.union(ready.map(\.rawValue))
    }

    static func reset() { UserDefaults.standard.removeObject(forKey: key) }
}
