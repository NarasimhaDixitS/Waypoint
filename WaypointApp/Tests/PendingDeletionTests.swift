import XCTest
import CoreData
@testable import Waypoint

/// A task mid-undo-window is gone from the screen and still in the store, and everything that
/// schedules around tasks has to agree about that.
///
/// **The bug a tester actually hit:** delete a task, then create another one in the slot it
/// just vacated, and the collision prompt appeared — blocked by a task that was no longer on
/// screen. `ScheduleEngine` reads Core Data directly, and the hidden set was `@State` inside
/// `TodayView`, so the engine never heard about it. The same stale read reached `TaskReplicator`,
/// where a repeating occurrence would be silently skipped for colliding with a ghost.
///
/// Every test here has a control beside it asserting that a task which *isn't* pending deletion
/// still blocks — otherwise "nothing collided" would pass just as well against an engine that
/// had stopped detecting collisions at all.
@MainActor
final class PendingDeletionTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
        SleepSettings.shared.startTimeOfDay = time(23, 0)
        SleepSettings.shared.durationMinutes = 7 * 60
        PendingDeletions.shared.reset()
    }

    override func tearDown() {
        // The store is a singleton the engine reads, so a hidden ID left behind here would
        // quietly change the answer for every later test in the process.
        PendingDeletions.shared.reset()
        super.tearDown()
    }

    private func time(_ hour: Int, _ minute: Int, on day: Date = .now) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    @discardableResult
    private func makeTask(_ title: String, at start: Date, duration: Int = 60) -> TaskEntity {
        let task = TaskEntity.create(
            in: context, title: title, date: start,
            startTime: start, durationMinutes: duration, priority: .medium
        )
        // Saved so the object IDs the store holds are the permanent ones, as in the app.
        try? context.save()
        return task
    }

    private func delete(_ task: TaskEntity) {
        PendingDeletions.shared.requestDelete([task], title: "“\(task.title ?? "")”", in: context)
    }

    private func tasksInStore() -> [TaskEntity] {
        (try? context.fetch(TaskEntity.fetchRequest())) ?? []
    }

    // MARK: - The reported bug

    func testANewTaskCanTakeTheSlotOfATaskWhoseDeleteIsStillPending() {
        let gym = makeTask("Gym", at: time(14, 0))
        delete(gym)

        let resolution = ScheduleEngine.resolveNewTask(
            start: time(14, 0), end: time(15, 0), on: .now, context: context
        )
        guard case .none = resolution else {
            return XCTFail("a deleted task still blocked its own slot: \(resolution)")
        }
    }

    /// The control. Without it the test above would pass against an engine that never
    /// collides with anything.
    func testANewTaskStillCollidesWithATaskNobodyDeleted() {
        makeTask("Gym", at: time(14, 0))

        let resolution = ScheduleEngine.resolveNewTask(
            start: time(14, 0), end: time(15, 0), on: .now, context: context
        )
        if case .none = resolution {
            XCTFail("expected a collision with a live task")
        }
    }

    func testTheVacatedSlotIsOfferedAsOpenAgain() {
        let gym = makeTask("Gym", at: time(14, 0))
        makeTask("Standup", at: time(9, 0), duration: 30)

        let before = ScheduleEngine.openSlots(on: .now, minimumMinutes: 60, context: context)
        XCTAssertFalse(
            before.contains { $0.start <= time(14, 0) && $0.availableMinutes >= 60 && $0.start >= time(13, 0) },
            "2pm shouldn't be free while Gym is live"
        )

        delete(gym)

        let after = ScheduleEngine.openSlots(on: .now, minimumMinutes: 60, context: context)
        let coversTwoPM = after.contains { slot in
            let end = slot.start.addingTimeInterval(TimeInterval(slot.availableMinutes * 60))
            return slot.start <= time(14, 0) && end >= time(15, 0)
        }
        XCTAssertTrue(coversTwoPM, "2pm should be open once Gym is pending deletion: \(after)")
    }

    /// `TaskReplicator` asks this question per occurrence and skips silently when the answer is
    /// yes — so a ghost here costs the user a recurring task with no message at all.
    func testReplicationDoesNotSkipAnOccurrenceBlockedOnlyByAGhost() {
        let gym = makeTask("Gym", at: time(14, 0))

        XCTAssertTrue(
            ScheduleEngine.wouldCollide(start: time(14, 0), end: time(15, 0), on: .now, context: context),
            "control: a live task must still count as a collision"
        )

        delete(gym)

        XCTAssertFalse(
            ScheduleEngine.wouldCollide(start: time(14, 0), end: time(15, 0), on: .now, context: context),
            "a task pending deletion must not block replication"
        )
    }

    /// The edit flows fetch through the same helper, so moving an existing task into the
    /// vacated slot must not ask to bump the ghost either.
    func testMovingAnExistingTaskIntoTheVacatedSlotDoesNotBump() {
        let gym = makeTask("Gym", at: time(14, 0))
        let admin = makeTask("Admin", at: time(9, 0), duration: 30)
        delete(gym)

        let resolution = ScheduleEngine.resolveTimeMove(
            task: admin, newStart: time(14, 0), newDurationMinutes: 60, context: context
        )
        guard case .none = resolution else {
            return XCTFail("moving into a vacated slot asked to bump: \(resolution)")
        }
    }

    // MARK: - Committing and undoing

    func testFinalizeActuallyRemovesTheTaskFromTheStore() {
        let gym = makeTask("Gym", at: time(14, 0))
        delete(gym)
        XCTAssertEqual(tasksInStore().count, 1, "still in the store while the window is open")

        PendingDeletions.shared.finalize()

        XCTAssertTrue(tasksInStore().isEmpty, "finalize must commit the delete")
        XCTAssertNil(PendingDeletions.shared.pending)
        XCTAssertTrue(PendingDeletions.shared.hiddenIDs.isEmpty)
    }

    func testUndoPutsTheTaskBackAndItBlocksItsSlotAgain() {
        let gym = makeTask("Gym", at: time(14, 0))
        delete(gym)

        PendingDeletions.shared.undo()

        XCTAssertEqual(tasksInStore().count, 1)
        XCTAssertTrue(PendingDeletions.shared.hiddenIDs.isEmpty)
        let resolution = ScheduleEngine.resolveNewTask(
            start: time(14, 0), end: time(15, 0), on: .now, context: context
        )
        if case .none = resolution {
            XCTFail("an undone delete must leave the task blocking its slot again")
        }
    }

    func testStartingASecondDeleteCommitsTheFirst() {
        let gym = makeTask("Gym", at: time(14, 0))
        let call = makeTask("Call", at: time(16, 0))

        delete(gym)
        delete(call)

        let titles = tasksInStore().compactMap(\.title)
        XCTAssertEqual(titles, ["Call"], "the first delete should have committed, not been dropped")
        XCTAssertEqual(PendingDeletions.shared.pending?.tasks.count, 1)
    }

    /// The goal page's series delete removes occurrences outright, and a demo reseed empties
    /// the store — either can take a task out from under an open undo window. Touching a
    /// deleted object's properties is undefined, so `finalize` has to step over it.
    func testFinalizeSurvivesATaskThatAlreadyLeftByAnotherDoor() {
        let gym = makeTask("Gym", at: time(14, 0))
        delete(gym)

        context.delete(gym)
        try? context.save()

        PendingDeletions.shared.finalize()

        XCTAssertTrue(tasksInStore().isEmpty)
        XCTAssertNil(PendingDeletions.shared.pending)
    }

    func testDeletingNothingDoesNotOpenAWindow() {
        PendingDeletions.shared.requestDelete([], title: "nothing", in: context)
        XCTAssertNil(PendingDeletions.shared.pending)
    }
}
