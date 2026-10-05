import Foundation

/// Opens the whole app while it is being beta tested, and closes again by itself.
///
/// **Why this exists.** The purchase path is still a mock — `SubscriptionManager.purchase`
/// writes to `UserDefaults` and no money or StoreKit is involved. A tester whose fourteen days
/// run out would meet a Subscribe button showing prices for products that do not exist. That is
/// a bad first impression and arguably a review problem, and it would be the one screen testers
/// remember.
///
/// So during the beta everything is open. The free tier is real work and deserves testing, but
/// it will be tested in a later round against real sandbox purchases, where what testers see is
/// the truth.
///
/// **Why it is detected rather than configured.** The obvious version of this is a constant
/// somebody flips back before shipping. That is a paywall held open by a thing a person has to
/// remember, and the failure is silent and total: the App Store build gives the app away and
/// nothing reports it.
///
/// A TestFlight or development build carries an embedded provisioning profile; a build
/// downloaded from the App Store has none, because the App Store strips it. Looking for that
/// file answers the question directly, and it fails in the safe direction — an App Store build
/// cannot accidentally be in beta mode, because there is no profile there to find.
///
/// (The receipt name is the other common test for this, but `appStoreReceiptURL` is deprecated
/// and its replacement is async, which a synchronous gate read on every view update can't use.)
///
/// **This whole file is deleted once RevenueCat lands.** By then purchases are real, the sandbox
/// is where testers buy things for free, and nothing needs opening by hand.
enum BetaAccess {

    /// True in TestFlight and in builds run from Xcode; false in anything installed from the
    /// App Store.
    ///
    /// Resolved once. The answer cannot change while the app is running, and this is read on
    /// every gate check in the app.
    /// A `var` only so the tests can turn it off.
    ///
    /// The free-tier rules are the one thing in this app that must keep working when the beta
    /// ends, and with this on they are unreachable — ten tests went green for the wrong reason
    /// the moment it was added. They set it false and assert the real gate underneath.
    ///
    /// Nothing in the app ever writes to it. The default is detected, so an App Store build is
    /// still closed without anybody remembering to close it.
    static var grantsFullAccess: Bool = detected

    private static let detected: Bool = {
        #if DEBUG
        return true
        #else
        // Belt and braces, because this check is wrong in the *dangerous* direction if it is
        // wrong at all: a false positive on the App Store gives the app away silently. The
        // profile test is the standard way to tell TestFlight from the App Store and is
        // verified present in this project's own signed .ipa — but a date the override cannot
        // outlive bounds the damage if Apple ever changes what it strips.
        //
        // If a build somehow reaches a user after this date with the override still in it, the
        // paywall simply works. That is the right way round to fail.
        guard Date.now < expiry else { return false }
        return Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil
        #endif
    }()

    /// Well past any sensible beta, and long before this file should still exist.
    static let expiry = Calendar.current.date(from: DateComponents(year: 2027, month: 3, day: 1))!
}
