import Foundation
import CoreData

/// A stretch of focused work, recorded when it ends.
///
/// The one thing the app could never answer before: how long something actually took. Every
/// task carries a `durationMinutes` the user guessed when they created it, and nothing ever
/// checked that guess against reality. A completed task only proves the work happened, not that
/// forty-five minutes was the right number — so plans stayed as wrong as they were on day one.
///
/// Like `TaskEventEntity`, this holds a raw `taskID` and a copy of the title rather than a
/// relationship. A relationship would cascade the record away with the task, which is backwards:
/// the whole value of a focus history is that it outlives the work it describes.
enum FocusSessionLog {

    /// Records a finished session. `actualSeconds` is time actually spent running — pauses are
    /// excluded, because a timer left paused over lunch is not two hours of focus, and counting
    /// it would make every estimate look wildly optimistic.
    ///
    /// Sessions shorter than `minimumSeconds` are dropped. Opening the timer, starting it and
    /// immediately closing it isn't data; it's a misfire, and a pile of nine-second rows would
    /// drag every average down while looking like real evidence.
    @discardableResult
    static func record(
        taskID: UUID?,
        taskTitle: String?,
        startedAt: Date,
        endedAt: Date,
        plannedSeconds: Int,
        actualSeconds: Int,
        ranToCompletion: Bool,
        in context: NSManagedObjectContext,
        minimumSeconds: Int = 30
    ) -> FocusSessionEntity? {
        guard actualSeconds >= minimumSeconds else { return nil }
        let session = FocusSessionEntity(context: context)
        session.id = UUID()
        session.taskID = taskID
        session.taskTitle = taskTitle
        session.startedAt = startedAt
        session.endedAt = endedAt
        session.plannedSeconds = Int32(plannedSeconds)
        session.actualSeconds = Int32(actualSeconds)
        session.ranToCompletion = ranToCompletion
        return session
    }
}

extension FocusSessionEntity {
    /// Minutes actually focused, rounded to the nearest minute for display.
    var actualMinutes: Int { Int((Double(actualSeconds) / 60).rounded()) }

    var plannedMinutes: Int { Int((Double(plannedSeconds) / 60).rounded()) }

    static func fetchRequest(since: Date? = nil) -> NSFetchRequest<FocusSessionEntity> {
        let request = NSFetchRequest<FocusSessionEntity>(entityName: "FocusSessionEntity")
        if let since {
            request.predicate = NSPredicate(format: "endedAt >= %@", since as NSDate)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "endedAt", ascending: false)]
        return request
    }
}
