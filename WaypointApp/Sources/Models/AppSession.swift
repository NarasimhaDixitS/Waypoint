import Foundation
import CoreData

/// When the app was opened, and for how long.
///
/// The one thing here that is purely about *use* rather than about work. It can't be derived
/// from anything else and it can't be backfilled — a year from now there is no way to find out
/// whether someone checked in every morning or twice a month, unless it was written down as it
/// happened.
///
/// A row per open. Ten opens a day for a year is three and a half thousand rows of three dates:
/// a rounding error against the task history sitting beside it.
enum AppSessionLog {
    /// Opens a session, closing any that was left hanging.
    ///
    /// A session is left open when the app is killed rather than backgrounded, which happens
    /// often enough that ignoring it would leave a trail of sessions with no end. Those get
    /// closed at their own start — a zero-length open, which is the truth: we know it began and
    /// nothing more.
    @discardableResult
    static func begin(in context: NSManagedObjectContext, now: Date = .now) -> AppSessionEntity {
        closeDangling(in: context)
        let session = AppSessionEntity(context: context)
        session.id = UUID()
        session.startedAt = now
        return session
    }

    /// Closes the open session. A no-op if there isn't one.
    static func end(in context: NSManagedObjectContext, now: Date = .now) {
        guard let open = openSession(in: context) else { return }
        open.endedAt = now
    }

    static func openSession(in context: NSManagedObjectContext) -> AppSessionEntity? {
        let request = NSFetchRequest<AppSessionEntity>(entityName: "AppSessionEntity")
        request.predicate = NSPredicate(format: "endedAt == nil")
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    private static func closeDangling(in context: NSManagedObjectContext) {
        let request = NSFetchRequest<AppSessionEntity>(entityName: "AppSessionEntity")
        request.predicate = NSPredicate(format: "endedAt == nil")
        for session in (try? context.fetch(request)) ?? [] {
            session.endedAt = session.startedAt
        }
    }
}

extension AppSessionEntity {
    var duration: TimeInterval {
        guard let startedAt, let endedAt else { return 0 }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    static func fetchRequest(since: Date? = nil) -> NSFetchRequest<AppSessionEntity> {
        let request = NSFetchRequest<AppSessionEntity>(entityName: "AppSessionEntity")
        if let since {
            request.predicate = NSPredicate(format: "startedAt >= %@", since as NSDate)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        return request
    }
}
