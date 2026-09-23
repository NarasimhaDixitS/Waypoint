import Foundation
import SwiftUI

/// Who the user is, as far as this app is concerned.
///
/// **Placeholder.** Sign in with Apple needs the `com.apple.developer.applesignin` entitlement,
/// which requires a paid Apple Developer Program membership this project doesn't have yet. The
/// button and the states around it are real so the flow can be designed and walked through;
/// `signIn()` fabricates a result instead of asking Apple for one.
///
/// It replaced a Supabase anonymous sign-in that ran on every launch, blocked the first frame on
/// a network round trip, and produced a user id nothing ever read. Nothing here touches the
/// network — an Apple-only app has no server to ask.
///
/// What signing in is *for* is still the open question: the subscription belongs to the Apple ID
/// and so does iCloud sync, so today it buys a name and an email nothing displays. It earns its
/// place the moment there's a second platform, or a subscriber list worth keeping.
@MainActor
final class AccountManager: ObservableObject {
    static let shared = AccountManager()

    @Published private(set) var displayName: String?
    @Published private(set) var email: String?

    var isSignedIn: Bool { displayName != nil }

    private enum Keys {
        static let name = "account.displayName"
        static let email = "account.email"
    }

    private init() {
        displayName = UserDefaults.standard.string(forKey: Keys.name)
        email = UserDefaults.standard.string(forKey: Keys.email)
    }

    /// Stands in for a real `ASAuthorizationAppleIDCredential`.
    ///
    /// When this becomes real, one detail decides whether it works: **Apple sends the user's
    /// name exactly once**, on the very first authorisation, and returns nil for it on every
    /// sign-in afterwards. It has to be persisted at that moment or it is gone for good.
    func signIn() {
        apply(name: "Narasimha", email: "you@example.com")
    }

    func signOut() {
        apply(name: nil, email: nil)
    }

    private func apply(name: String?, email: String?) {
        displayName = name
        self.email = email
        UserDefaults.standard.set(name, forKey: Keys.name)
        UserDefaults.standard.set(email, forKey: Keys.email)
    }
}
