import Foundation
import CoreData

/// Something worth having reached.
///
/// Deliberately not a points system. The app's whole character is that it records what you put
/// off rather than flattering you, and a milestone for opening the app or ticking ten boxes
/// would undo that in one screen. Each of these takes work, and the interesting ones take work
/// no other app could see you doing.
enum MilestoneKind: String, CaseIterable {

    // MARK: Consistency

    /// A calendar week where every day that had work finished at least something.
    case perfectWeek
    /// A calendar month with nothing abandoned.
    case cleanMonth
    /// Thirty consecutive days with at least one completion.
    case thirtyDayStreak

    // MARK: Follow-through

    /// A goal seen through end to end. The first one is the one that matters.
    case firstGoalCompleted
    /// A calendar week where nothing was pushed to a later day.
    case zeroDeferralWeek
    /// A goal still being worked ninety days after it started.
    case longHaulGoal

    // MARK: Self-knowledge
    //
    // These are the ones only this app can award, because only this app keeps the deferral log
    // and the focus sessions. Everything above could be counted by any task app; nothing below
    // could be.

    /// Finished a task that had been pushed back five times or more.
    case finallyDidIt
    /// A week where the time work actually took landed within a tenth of what was budgeted.
    case knowsOwnPace
    /// A month where high-priority work was completed at a better rate than low-priority.
    case hardThingsFirst

    // MARK: Volume

    case hundredTasks
    case fiveHundredTasks
    case thousandTasks
    /// A hundred hours of measured, focused work.
    case hundredFocusHours

    var title: String {
        switch self {
        case .perfectWeek: "A week without a gap"
        case .cleanMonth: "A month with nothing abandoned"
        case .thirtyDayStreak: "Thirty days running"
        case .firstGoalCompleted: "First goal finished"
        case .zeroDeferralWeek: "A week with nothing put off"
        case .longHaulGoal: "Ninety days on one goal"
        case .finallyDidIt: "You finally did it"
        case .knowsOwnPace: "You know your own pace"
        case .hardThingsFirst: "Hard things first"
        case .hundredTasks: "A hundred tasks"
        case .fiveHundredTasks: "Five hundred tasks"
        case .thousandTasks: "A thousand tasks"
        case .hundredFocusHours: "A hundred hours of focus"
        }
    }

    /// Said plainly, and without congratulating anyone for turning up.
    var detail: String {
        switch self {
        case .perfectWeek: "Every day you had work on, you finished something."
        case .cleanMonth: "A whole month and you didn't give up on anything."
        case .thirtyDayStreak: "Thirty days in a row with something finished."
        case .firstGoalCompleted: "You set a goal and saw it through."
        case .zeroDeferralWeek: "A week where nothing got pushed to tomorrow."
        case .longHaulGoal: "Still at it three months later."
        case .finallyDidIt: "You'd put this off five times. Then you didn't."
        case .knowsOwnPace: "Your estimates matched what the work actually took."
        case .hardThingsFirst: "You finished more of the important work than the easy work."
        case .hundredTasks: "A hundred things done."
        case .fiveHundredTasks: "Five hundred things done."
        case .thousandTasks: "A thousand things done."
        case .hundredFocusHours: "A hundred hours, measured, not estimated."
        }
    }
}

extension MilestoneEntity {
    var kindValue: MilestoneKind? { kind.flatMap(MilestoneKind.init(rawValue:)) }

    static func fetchRequest(since: Date? = nil) -> NSFetchRequest<MilestoneEntity> {
        let request = NSFetchRequest<MilestoneEntity>(entityName: "MilestoneEntity")
        if let since {
            request.predicate = NSPredicate(format: "achievedAt >= %@", since as NSDate)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "achievedAt", ascending: false)]
        return request
    }
}
