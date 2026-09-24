import CoreData
import Foundation

struct PersistenceController {
    /// What happened on the way in, when the launch wasn't a clean one. `nil` is the normal case.
    ///
    /// The store is loaded exactly once, at launch, and that load is where a data-structure
    /// change gets applied to the file already on the phone. Simple changes Core Data works out
    /// by itself; a rename, a changed type, or a split it cannot, and without explicit
    /// instructions the load fails. This used to `fatalError` there — which meant the app died
    /// on its launch screen and did so on every subsequent open, because the file stayed in the
    /// state it couldn't handle. The user's data was intact and unreachable, and with no backend
    /// their only way to a working app was to delete and reinstall, throwing all of it away.
    enum Recovery: Equatable {
        /// The store wouldn't open. The file was moved aside — intact, not deleted — to this
        /// folder, and the app opened on an empty store so it still works. A later build can
        /// migrate what's there properly and hand it back.
        case setAside(URL)
        /// Even a fresh store wouldn't open, so there's no storage at all this launch. The app
        /// runs, but nothing will persist. Rare enough to be a bug worth hearing about, and
        /// still better than refusing to start.
        case unavailable(String)
    }

    static let shared = PersistenceController()

    /// Shared with the widget extension, which runs in its own process and cannot see the app's
    /// private container at all.
    static let appGroupID = "group.com.waypoint.app"

    /// Where the store lives. The App Group container once it's reachable, the app's own
    /// Application Support directory otherwise.
    ///
    /// The fallback is not defensive padding: `containerURL` returns nil whenever the
    /// entitlement isn't in the running build — a provisioning profile without the capability,
    /// or a configuration that hasn't picked it up. Treating that as fatal would turn a
    /// signing problem into an app that won't open, which is a much worse failure than a widget
    /// that has nothing to show.
    static var storeDirectory: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? NSPersistentContainer.defaultDirectoryURL()
    }

    static var defaultStoreURL: URL {
        storeDirectory.appendingPathComponent("Waypoint.sqlite")
    }

    /// Where the store used to live, before the widget needed to read it.
    private static var legacyStoreURL: URL {
        NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("Waypoint.sqlite")
    }

    let container: NSPersistentContainer
    /// Read at launch to tell the user what happened; see `WaypointApp`.
    let recovery: Recovery?

    /// Loaded once and shared by every container.
    ///
    /// `NSPersistentContainer(name:)` parses the model file afresh each time it's called, and
    /// each parse produces entity descriptions that all claim the same generated classes —
    /// `TaskEntity`, `GoalEntity` and the rest. Core Data then can't decide which description a
    /// class belongs to, logs "Failed to find a unique match for an NSEntityDescription", and
    /// hands back fetch requests with no entity attached, which throw on execution.
    ///
    /// The app only ever builds one container so it never noticed. The test suite builds one
    /// per test case, which is why every run ended in a wall of Core Data errors and an uncaught
    /// exception after the last test — alarming, unrelated to any failure, and exactly the kind
    /// of noise a real crash would one day hide in.
    private static let model: NSManagedObjectModel = {
        guard let url = Bundle.main.url(forResource: "Waypoint", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            // Only reachable if the compiled model is missing from the bundle, which is a build
            // configuration error rather than anything a user can cause or recover from.
            fatalError("Waypoint.momd is missing from the app bundle")
        }
        return model
    }()

    /// - Parameter storeURL: overrides where the store lives. Only for tests, which need to
    ///   point at a file they've deliberately damaged.
    init(inMemory: Bool = false, storeURL: URL? = nil) {
        let container = NSPersistentContainer(name: "Waypoint", managedObjectModel: Self.model)
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else if let storeURL {
            container.persistentStoreDescriptions.first?.url = storeURL
        } else {
            Self.migrateToAppGroupIfNeeded()
            container.persistentStoreDescriptions.first?.url = Self.defaultStoreURL
        }
        self.container = container
        self.recovery = Self.load(container, inMemory: inMemory)
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    private static func load(_ container: NSPersistentContainer, inMemory: Bool) -> Recovery? {
        guard let error = attemptLoad(container) else { return nil }

        // An in-memory store has nothing on disk to rescue, and a missing URL leaves nothing to
        // move — either way the honest answer is that there's no storage, not a crash.
        guard !inMemory, let url = container.persistentStoreDescriptions.first?.url else {
            return .unavailable(error.localizedDescription)
        }
        guard let archive = setAside(storeAt: url) else {
            return .unavailable(error.localizedDescription)
        }
        if let retryError = attemptLoad(container) {
            return .unavailable(retryError.localizedDescription)
        }
        return .setAside(archive)
    }

/// Moves an existing store into the App Group container, once.
    ///
    /// Done through `replacePersistentStore` rather than `FileManager.copyItem`, because a
    /// SQLite store is three files — the database, the write-ahead log and the shared-memory
    /// file — and copying only the first silently loses every change still sitting in the WAL.
    /// Core Data checkpoints and moves the set as a unit.
    ///
    /// The original is left where it is. It costs a few hundred kilobytes and it is the only
    /// copy of the user's history if this move turns out to be wrong in a way testing missed;
    /// a later release can delete it once this has been in the wild long enough to trust.
    /// Everything here is best-effort — a migration that fails leaves the app opening on the
    /// old store, which is the behaviour it had yesterday.
    private static func migrateToAppGroupIfNeeded() {
        let fileManager = FileManager.default
        let destination = defaultStoreURL
        let legacy = legacyStoreURL

        // Same path means the container isn't available, so there is nothing to move into.
        guard destination != legacy else { return }
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        guard !fileManager.fileExists(atPath: destination.path) else { return }

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        do {
            try coordinator.replacePersistentStore(
                at: destination,
                destinationOptions: nil,
                withPersistentStoreFrom: legacy,
                sourceOptions: nil,
                type: .sqlite
            )
        } catch {
            assertionFailure("Store migration to the App Group failed: \(error)")
        }
    }

    private static func attemptLoad(_ container: NSPersistentContainer) -> Error? {
        // `loadPersistentStores` reports through a closure but runs synchronously for a local
        // store, so the error is already captured by the time this returns.
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        return failure
    }

    /// Moves the store and its two sidecar files into a timestamped folder beside it. A move,
    /// never a delete: the whole point is that the data survives an update that couldn't read
    /// it, so a later build can come back for it.
    private static func setAside(storeAt url: URL) -> URL? {
        let fileManager = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        // Uniquified, because the stamp is only accurate to the second and two failed launches
        // can land inside the same one — which quietly turned the second rescue into a failed
        // move onto an existing file, losing exactly the data this function exists to keep.
        let parent = url.deletingLastPathComponent()
        let base = "Unreadable-\(formatter.string(from: .now))"
        var archive = parent.appendingPathComponent(base, isDirectory: true)
        var attempt = 2
        while fileManager.fileExists(atPath: archive.path) {
            archive = parent.appendingPathComponent("\(base)-\(attempt)", isDirectory: true)
            attempt += 1
        }
        do {
            try fileManager.createDirectory(at: archive, withIntermediateDirectories: true)
            // The write-ahead log and shared-memory files hold committed data that hasn't been
            // folded into the main file yet. Leaving them behind would both lose part of the
            // user's history and leave the fresh store sitting next to a mismatched journal.
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: url.path + suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.moveItem(at: source, to: archive.appendingPathComponent(source.lastPathComponent))
            }
            return archive
        } catch {
            return nil
        }
    }

    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save context: \(error)")
        }
    }
}
