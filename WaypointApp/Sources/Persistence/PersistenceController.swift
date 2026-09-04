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

    let container: NSPersistentContainer
    /// Read at launch to tell the user what happened; see `WaypointApp`.
    let recovery: Recovery?

    /// - Parameter storeURL: overrides where the store lives. Only for tests, which need to
    ///   point at a file they've deliberately damaged.
    init(inMemory: Bool = false, storeURL: URL? = nil) {
        let container = NSPersistentContainer(name: "Waypoint")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else if let storeURL {
            container.persistentStoreDescriptions.first?.url = storeURL
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
