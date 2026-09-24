import XCTest
import CoreData
@testable import Waypoint

/// The behaviour these cover only ever runs at launch, on a user's machine, after an update —
/// the one place you can't watch it happen. So they exercise it against a real file on disk
/// rather than trusting that the error path is written correctly.
final class PersistenceRecoveryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private var storeURL: URL { directory.appendingPathComponent("Waypoint.sqlite") }

    /// Stands in for the real failure — a store this build can't read. Whether that's a rename
    /// Core Data couldn't infer or a genuinely damaged file, it arrives here the same way: the
    /// load returns an error instead of a store.
    private func writeUnreadableStore() throws {
        try Data("this is not a database".utf8).write(to: storeURL)
    }

    func testAHealthyStoreLoadsWithNoRecovery() {
        let controller = PersistenceController(storeURL: storeURL)

        XCTAssertNil(controller.recovery)
        XCTAssertFalse(controller.container.persistentStoreCoordinator.persistentStores.isEmpty)
    }

    /// The whole point: the app opens. It used to `fatalError` here, which bricked it on every
    /// subsequent launch too, since the file stayed exactly as it was.
    func testAnUnreadableStoreStillLeavesAWorkingApp() throws {
        try writeUnreadableStore()

        let controller = PersistenceController(storeURL: storeURL)

        XCTAssertFalse(
            controller.container.persistentStoreCoordinator.persistentStores.isEmpty,
            "the app has to come up with usable storage, not refuse to start"
        )
        let task = TaskEntity.create(
            in: controller.container.viewContext,
            title: "Still works",
            date: .now, startTime: .now, durationMinutes: 30, priority: .medium
        )
        XCTAssertNoThrow(try controller.container.viewContext.save())
        XCTAssertEqual(task.title, "Still works")
    }

    /// The file is moved, never deleted. Everything rests on this: a later build has to be able
    /// to come back for it, and a user who is told "your data is safe" has to be told the truth.
    func testTheUnreadableFileIsPreservedNotDestroyed() throws {
        try writeUnreadableStore()
        let original = try Data(contentsOf: storeURL)

        let controller = PersistenceController(storeURL: storeURL)

        guard case .setAside(let archive)? = controller.recovery else {
            return XCTFail("expected the store to be set aside, got \(String(describing: controller.recovery))")
        }
        let preserved = archive.appendingPathComponent("Waypoint.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: preserved.path))
        XCTAssertEqual(try Data(contentsOf: preserved), original, "byte-for-byte, not a partial copy")
    }

    /// The write-ahead log holds committed changes not yet folded into the main file. Leaving it
    /// behind would lose part of the user's history *and* strand a mismatched journal beside the
    /// fresh store.
    func testTheSidecarJournalFilesTravelWithTheStore() throws {
        try writeUnreadableStore()
        let wal = URL(fileURLWithPath: storeURL.path + "-wal")
        let shm = URL(fileURLWithPath: storeURL.path + "-shm")
        try Data("journal".utf8).write(to: wal)
        try Data("shared".utf8).write(to: shm)

        let controller = PersistenceController(storeURL: storeURL)

        guard case .setAside(let archive)? = controller.recovery else {
            return XCTFail("expected the store to be set aside")
        }
        // Checked by content, not by absence: the fresh store opens its own `-wal`/`-shm` at the
        // same paths straight away, so "no file there" would be testing the wrong thing entirely.
        XCTAssertEqual(try Data(contentsOf: archive.appendingPathComponent("Waypoint.sqlite-wal")), Data("journal".utf8))
        XCTAssertEqual(try Data(contentsOf: archive.appendingPathComponent("Waypoint.sqlite-shm")), Data("shared".utf8))
        if FileManager.default.fileExists(atPath: wal.path) {
            XCTAssertNotEqual(try Data(contentsOf: wal), Data("journal".utf8), "the new store's journal, not the old one")
        }
    }

    /// A second bad launch shouldn't overwrite the rescue from the first one.
    func testASecondFailureDoesNotOverwriteTheFirstArchive() throws {
        try writeUnreadableStore()
        let first = PersistenceController(storeURL: storeURL)
        guard case .setAside(let firstArchive)? = first.recovery else {
            return XCTFail("expected the first store to be set aside")
        }

        try writeUnreadableStore()
        let second = PersistenceController(storeURL: storeURL)
        guard case .setAside(let secondArchive)? = second.recovery else {
            return XCTFail("expected the second store to be set aside")
        }

        XCTAssertNotEqual(firstArchive, secondArchive)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: firstArchive.appendingPathComponent("Waypoint.sqlite").path),
            "the earlier rescue has to survive"
        )
    }

/// The widget runs in its own process and can't see the app's private container, so the
    /// store moves into a shared one. That move happens once, on a real device, over somebody's
    /// only copy of their history — so it's checked here against real files rather than trusted.
    func testMovingAStoreCarriesItsContentAcross() throws {
        let source = directory.appendingPathComponent("Source.sqlite")
        let destination = directory.appendingPathComponent("Shared/Waypoint.sqlite")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        let original = PersistenceController(storeURL: source)
        TaskEntity.create(
            in: original.container.viewContext, title: "Survives the move",
            date: .now, startTime: .now, durationMinutes: 30, priority: .medium
        )
        try original.container.viewContext.save()

        // What `migrateToAppGroupIfNeeded` does, against the same API. Not `copyItem`: a SQLite
        // store is three files, and copying only the database silently drops everything still
        // sitting in the write-ahead log.
        let coordinator = NSPersistentStoreCoordinator(
            managedObjectModel: original.container.managedObjectModel
        )
        try coordinator.replacePersistentStore(
            at: destination, destinationOptions: nil,
            withPersistentStoreFrom: source, sourceOptions: nil, type: .sqlite
        )

        let moved = PersistenceController(storeURL: destination)
        let tasks = try moved.container.viewContext.fetch(TaskEntity.fetchRequest())

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.title, "Survives the move")
        XCTAssertNil(moved.recovery, "a moved store has to open cleanly, not land in recovery")
    }

    /// The source is left alone. It is the only copy of the user's history if the move turns
    /// out to be wrong in a way testing missed.
    func testTheOriginalStoreIsNotDestroyedByTheMove() throws {
        let source = directory.appendingPathComponent("Source.sqlite")
        let destination = directory.appendingPathComponent("Shared2/Waypoint.sqlite")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        let original = PersistenceController(storeURL: source)
        TaskEntity.create(
            in: original.container.viewContext, title: "Still here",
            date: .now, startTime: .now, durationMinutes: 30, priority: .medium
        )
        try original.container.viewContext.save()

        let coordinator = NSPersistentStoreCoordinator(
            managedObjectModel: original.container.managedObjectModel
        )
        try coordinator.replacePersistentStore(
            at: destination, destinationOptions: nil,
            withPersistentStoreFrom: source, sourceOptions: nil, type: .sqlite
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let reopened = PersistenceController(storeURL: source)
        XCTAssertEqual(try reopened.container.viewContext.fetch(TaskEntity.fetchRequest()).count, 1)
    }

    func testInMemoryStoresAreUnaffected() {
        let controller = PersistenceController(inMemory: true)

        XCTAssertNil(controller.recovery)
        XCTAssertFalse(controller.container.persistentStoreCoordinator.persistentStores.isEmpty)
    }
}
