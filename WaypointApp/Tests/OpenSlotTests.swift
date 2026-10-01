import XCTest
import CoreData
@testable import Waypoint

/// The gaps in a day, which the clash sheet offers as alternative times.
///
/// Worth testing rather than eyeballing: a wrong slot here is a time the app *offers* and then
/// collides with, which is a worse failure than refusing to suggest anything at all.
@MainActor
final class OpenSlotTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: hour, minute: minute))!
    }

    private var day: Date { at(0) }

    @discardableResult
    private func task(from hour: Int, minutes: Int) -> TaskEntity {
        TaskEntity.create(
            in: context, title: "T\(hour)", date: day, startTime: at(hour),
            durationMinutes: minutes, priority: .medium
        )
    }

    private func slots(minimum: Int = 1) -> [ScheduleEngine.OpenSlot] {
        ScheduleEngine.openSlots(on: day, minimumMinutes: minimum, context: context)
    }

    func testAnEmptyDayIsOneLongSlot() {
        XCTAssertEqual(slots().count, 1)
    }

    /// The whole point of listing them: a day with work at 10 and at 2 has gaps either side and
    /// between, and only seeing all of them makes "move it to" a real choice.
    func testGapsBetweenTasksAreAllReturnedInOrder() {
        task(from: 10, minutes: 60)
        task(from: 14, minutes: 60)

        let found = slots()

        XCTAssertGreaterThanOrEqual(found.count, 3, "before, between, and after")
        XCTAssertEqual(found.map(\.start), found.map(\.start).sorted(), "offered times have to read in order")
        XCTAssertTrue(found.contains { $0.start == at(11) }, "the gap after the first task is missing")
    }

    /// A slot that can't hold the task is not an option. Offering one makes the sheet look full
    /// of answers and then collides when you take it.
    func testSlotsTooShortForTheTaskAreNotOffered() {
        task(from: 10, minutes: 60)
        task(from: 11, minutes: 60) // no gap between these two at all
        task(from: 12, minutes: 30)

        let narrow = slots(minimum: 45)

        XCTAssertFalse(narrow.contains { $0.start == at(11) }, "there is no gap at 11 to offer")
        XCTAssertTrue(narrow.allSatisfy { $0.availableMinutes >= 45 })
    }

    /// Tasks already overlapping each other in the store must not walk the cursor backwards and
    /// invent a gap that isn't there — the app allows overlaps through other routes, so this
    /// isn't hypothetical.
    func testOverlappingExistingTasksDoNotInventAGap() {
        task(from: 10, minutes: 120) // 10:00–12:00
        task(from: 11, minutes: 30)  // 11:00–11:30, inside the first

        XCTAssertFalse(slots().contains { $0.start >= at(10) && $0.start < at(12) })
    }

    /// `notBefore` keeps today from suggesting a time that has already gone.
    func testSlotsNeverStartBeforeTheFloor() {
        let found = ScheduleEngine.openSlots(on: day, notBefore: at(15), context: context)
        XCTAssertTrue(found.allSatisfy { $0.start >= at(15) })
    }

    /// The single-slot helper the rest of the app defaults from must stay the first of these,
    /// or a new task's default time and the clash sheet's first suggestion disagree.
    func testTheDefaultSlotIsTheFirstOpenOne() {
        task(from: 9, minutes: 60)
        let earliest = ScheduleEngine.earliestOpenSlot(on: day, context: context)
        XCTAssertEqual(earliest?.start, slots().first?.start)
    }
}
