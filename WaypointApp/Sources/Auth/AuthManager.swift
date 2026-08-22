import Foundation
import Supabase

/// Every user is signed in from launch. Right now that's via Supabase's anonymous auth as a
/// stand-in -- there's no Apple Developer Program membership yet, which Sign in with Apple's
/// entitlement requires. Swapping in real Sign in with Apple later only touches
/// `bootstrap()`/adds a sign-in screen; every table's RLS is already keyed on auth.uid(), so
/// the schema and repositories underneath don't change.
@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var userID: UUID?
    @Published private(set) var isReady = false

    private init() {
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        if let session = try? await SupabaseManager.client.auth.session {
            userID = session.user.id
        } else {
            await signInAnonymously()
        }
        isReady = true
        observeAuthChanges()
    }

    private func signInAnonymously() async {
        do {
            let session = try await SupabaseManager.client.auth.signInAnonymously()
            userID = session.user.id
        } catch {
            print("Waypoint: anonymous sign-in failed - \(error)")
        }
    }

    private func observeAuthChanges() {
        Task {
            for await (_, session) in SupabaseManager.client.auth.authStateChanges {
                userID = session?.user.id
            }
        }
    }
}
