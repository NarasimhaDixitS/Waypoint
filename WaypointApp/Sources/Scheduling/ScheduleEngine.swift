import Foundation
import CoreData

/// One task's start time being pushed later as part of a cascade.
struct CascadeShift: Identifiable {
    var id: NSManagedObjectID { task.objectID }
    let task: TaskEntity
    let newStart: Date
}

enum EditResolution {
    /// No conflict — safe to save as-is.
    case none
    /// Room exists before hitting anything immovable; shift the whole downstream chain in
    /// one confirmation.
    case cascade([CascadeShift])
    /// The change would run into something immovable (sleep, or a high-priority task —
    /// fixed commitments like "Work" or "Gym" are informational only and don't block
    /// scheduling). Offer to bump one of the movable tasks in the way to tomorrow, or cap
    /// the change back to what fits.
    case hardBump(candidates: [TaskEntity], blockedBy: String)
}

/// A wall is anything immovable that scheduling changes can never push through.
private struct Wall {
    let start: Date
    let end: Date
    let label: String
}

/// Brand-new task creation has one option the edit flows don't: if nothing else fits, there
/// may still be room to just tack it onto the end of the day instead of bumping anything.
enum NewTaskResolution {
    /// No conflict — safe to save as-is.
    case none
    /// Collides with something, but there's also room after everything else today (before
    /// sleep) — offer both moving something to tomorrow *and* appending to the end of today.
    case appendable(appendStart: Date, candidates: [TaskEntity], blockedBy: String)
    /// Collides with something and there's no room left today either.
    case hardBump(candidates: [TaskEntity], blockedBy: String)
}

@MainActor
enum ScheduleEngine {
    /// Duration grew (start time unchanged): try to cascade the downstream chain, or
    /// escalate to a hard bump if that would run into something immovable.
    static func resolveDurationIncrease(
        task: TaskEntity,
        newDurationMinutes: Int,
        context: NSManagedObjectContext
    ) -> EditResolution {
        let day = task.resolvedDate
        let originalEnd = task.endTime
        let newEnd = task.resolvedStartTime.addingTimeInterval(TimeInterval(newDurationMinutes * 60))
        guard newEnd > originalEnd else { return .none }

        let others = otherTasks(on: day, excluding: task, context: context)
        let movable = others.filter { $0.priorityValue != .high }
        let highPriorityWalls = others.filter { $0.priorityValue == .high }.map {
            Wall(start: $0.resolvedStartTime, end: $0.endTime, label: $0.title ?? "a high-priority task")
        }
        let allWalls = (highPriorityWalls + sleepWalls(on: day))
            .filter { $0.start >= originalEnd }
            .sorted { $0.start < $1.start }

        let ceiling = allWalls.first?.start ?? .distantFuture
        let ceilingLabel = allWalls.first?.label

        let downstream = movable
            .filter { $0.resolvedStartTime >= originalEnd && $0.resolvedStartTime < ceiling }
            .sorted { $0.resolvedStartTime < $1.resolvedStartTime }

        var cursor = newEnd
        var shifts: [CascadeShift] = []
        for candidate in downstream {
            if candidate.resolvedStartTime >= cursor {
                break // there's already a gap here; nothing further needs to move
            }
            shifts.append(CascadeShift(task: candidate, newStart: cursor))
            cursor = cursor.addingTimeInterval(TimeInterval(candidate.durationMinutes) * 60)
        }

        if cursor > ceiling {
            let jammed = shifts.map(\.task) + downstream.filter { candidate in
                !shifts.contains { $0.task.objectID == candidate.objectID }
            }
            return .hardBump(candidates: jammed, blockedBy: ceilingLabel ?? "the end of your day")
        }

        return shifts.isEmpty ? .none : .cascade(shifts)
    }

    /// Start time (and/or duration) changed to a new slot. Same cascade model as growing a
    /// task's duration (see `resolveDurationIncrease`): tries to push anything downstream
    /// later to make room rather than immediately asking to bump something to tomorrow, only
    /// falling back to that if nothing fits before the next immovable thing. Landing inside
    /// something that already occupies the target moment can't be fixed by cascading —
    /// there's nothing "downstream" of it to push — so that still goes straight to a bump.
    static func resolveTimeMove(
        task: TaskEntity,
        newStart: Date,
        newDurationMinutes: Int,
        context: NSManagedObjectContext
    ) -> EditResolution {
        // The move can land on a different calendar day than the task's current one (moving
        // an incomplete task to a future date) — always check collisions against where it's
        // going, not where it currently is.
        let day = newStart
        let newEnd = newStart.addingTimeInterval(TimeInterval(newDurationMinutes * 60))
        let others = otherTasks(on: day, excluding: task, context: context)
        let movable = others.filter { $0.priorityValue != .high }
        let highPriorityWalls = others.filter { $0.priorityValue == .high }.map {
            Wall(start: $0.resolvedStartTime, end: $0.endTime, label: $0.title ?? "a high-priority task")
        }
        let walls = highPriorityWalls + sleepWalls(on: day)

        if let wallHit = walls.first(where: { $0.start < newStart && newStart < $0.end }) {
            let collidingTasks = movable.filter { newStart < $0.endTime && newEnd > $0.resolvedStartTime }
            return .hardBump(candidates: collidingTasks, blockedBy: wallHit.label)
        }
        if let earlierTask = movable.first(where: { $0.resolvedStartTime < newStart && newStart < $0.endTime }) {
            return .hardBump(candidates: [earlierTask], blockedBy: earlierTask.title ?? "another task")
        }

        let allWalls = walls
            .filter { $0.start >= newStart }
            .sorted { $0.start < $1.start }
        let ceiling = allWalls.first?.start ?? .distantFuture
        let ceilingLabel = allWalls.first?.label

        if newEnd > ceiling {
            let collidingTasks = movable.filter { newStart < $0.endTime && newEnd > $0.resolvedStartTime }
            return .hardBump(candidates: collidingTasks, blockedBy: ceilingLabel ?? "the end of your day")
        }

        let downstream = movable
            .filter { $0.resolvedStartTime >= newStart && $0.resolvedStartTime < ceiling }
            .sorted { $0.resolvedStartTime < $1.resolvedStartTime }

        var cursor = newEnd
        var shifts: [CascadeShift] = []
        for candidate in downstream {
            if candidate.resolvedStartTime >= cursor {
                break // there's already a gap here; nothing further needs to move
            }
            shifts.append(CascadeShift(task: candidate, newStart: cursor))
            cursor = cursor.addingTimeInterval(TimeInterval(candidate.durationMinutes) * 60)
        }

        if cursor > ceiling {
            let jammed = shifts.map(\.task) + downstream.filter { candidate in
                !shifts.contains { $0.task.objectID == candidate.objectID }
            }
            return .hardBump(candidates: jammed, blockedBy: ceilingLabel ?? "the end of your day")
        }

        return shifts.isEmpty ? .none : .cascade(shifts)
    }

    /// Collision check for a brand-new, not-yet-persisted task — unlike the old task-only
    /// check this replaced, it also catches sleep, not just other tasks. Fixed commitments
    /// like "Work" or "Gym" are informational only and never block a new task.
    static func resolveNewTask(start: Date, end: Date, on day: Date, context: NSManagedObjectContext) -> NewTaskResolution {
        let request = TaskEntity.fetchRequest(on: day, context: context)
        let dayTasks = (try? context.fetch(request)) ?? []
        let collidingTasks = dayTasks.filter { start < $0.endTime && end > $0.resolvedStartTime }
        let sleep = sleepWalls(on: day)
        let wallHit = sleep.first { start < $0.end && end > $0.start }

        guard wallHit != nil || !collidingTasks.isEmpty else { return .none }
        let blockedBy = wallHit?.label ?? collidingTasks.first?.title ?? "another task"

        // Scan the whole day (not just after the requested time) for the first gap that's
        // actually big enough — a free hour at 1pm should be found even if you asked for
        // 8pm. The morning tail of last night's sleep sets the earliest possible floor.
        let cal = Calendar.current
        let tonightSleep = sleep.first { cal.isDate($0.start, inSameDayAs: day) }
        let morningSleepTail = sleep.first { !cal.isDate($0.start, inSameDayAs: day) }
        let dayFloor = morningSleepTail?.end ?? cal.startOfDay(for: day)
        let sleepBoundary = tonightSleep?.start ?? .distantFuture
        let duration = end.timeIntervalSince(start)

        let occupied = dayTasks.map { ($0.resolvedStartTime, $0.endTime) }.sorted { $0.0 < $1.0 }

        var cursor = dayFloor
        for (occStart, occEnd) in occupied {
            if occStart > cursor, occStart.timeIntervalSince(cursor) >= duration {
                break // the gap right before this item is big enough
            }
            cursor = max(cursor, occEnd)
        }

        let appendStart = cursor
        let appendEnd = appendStart.addingTimeInterval(duration)
        if appendEnd <= sleepBoundary {
            return .appendable(appendStart: appendStart, candidates: collidingTasks, blockedBy: blockedBy)
        }
        return .hardBump(candidates: collidingTasks, blockedBy: blockedBy)
    }

    /// Finds the earliest free moment on a day and how much room follows it before the next
    /// task or sleep, so a new task's time/duration can default to something already open
    /// instead of an arbitrary next-round-hour guess that might already be taken. `notBefore`
    /// keeps "today" from suggesting a slot earlier than right now — pass `.distantPast` for
    /// a future day, where the whole day is fair game from its start.
    static func earliestOpenSlot(on day: Date, notBefore: Date = .distantPast, context: NSManagedObjectContext) -> (start: Date, availableMinutes: Int)? {
        let request = TaskEntity.fetchRequest(on: day, context: context)
        let dayTasks = (try? context.fetch(request)) ?? []
        let sleep = sleepWalls(on: day)

        let cal = Calendar.current
        let tonightSleep = sleep.first { cal.isDate($0.start, inSameDayAs: day) }
        let morningSleepTail = sleep.first { !cal.isDate($0.start, inSameDayAs: day) }
        let dayFloor = max(morningSleepTail?.end ?? cal.startOfDay(for: day), notBefore)
        let sleepBoundary = tonightSleep?.start ?? .distantFuture

        let occupied = dayTasks.map { ($0.resolvedStartTime, $0.endTime) }.sorted { $0.0 < $1.0 }

        var cursor = dayFloor
        for (occStart, occEnd) in occupied {
            if occStart > cursor {
                let availableMinutes = Int(occStart.timeIntervalSince(cursor) / 60)
                if availableMinutes > 0 {
                    return (cursor, availableMinutes)
                }
            }
            cursor = max(cursor, occEnd)
        }

        guard cursor < sleepBoundary else { return nil }
        let availableMinutes = Int(sleepBoundary.timeIntervalSince(cursor) / 60)
        return availableMinutes > 0 ? (cursor, availableMinutes) : nil
    }

    /// Whether a task with this exact window would collide with anything on that day —
    /// used by replication to silently skip occurrences that would land on top of another
    /// task or sleep. Fixed commitments don't block, so they're not checked here either.
    static func wouldCollide(start: Date, end: Date, on day: Date, context: NSManagedObjectContext) -> Bool {
        let request = TaskEntity.fetchRequest(on: day, context: context)
        let existing = (try? context.fetch(request)) ?? []
        if existing.contains(where: { start < $0.endTime && end > $0.resolvedStartTime }) {
            return true
        }
        return sleepWalls(on: day).contains { start < $0.end && end > $0.start }
    }

    // MARK: - Helpers

    private static func otherTasks(on day: Date, excluding task: TaskEntity, context: NSManagedObjectContext) -> [TaskEntity] {
        let request = TaskEntity.fetchRequest(on: day, context: context)
        let all = (try? context.fetch(request)) ?? []
        return all.filter { $0.objectID != task.objectID }
    }

    private static func sleepWalls(on day: Date) -> [Wall] {
        SleepSettings.shared.rangesTouching(day).map { Wall(start: $0.start, end: $0.end, label: "sleep") }
    }
}
