import Foundation
import Security

/// When this person's trial began, stored where deleting the app doesn't reach.
///
/// It lived in `UserDefaults`, which iOS deletes with the app — so uninstalling and reinstalling
/// handed out a fresh fourteen days, forever, for free. Keychain items survive app deletion,
/// which makes this the one place a trial start can be written without a server.
///
/// **What it does and doesn't stop.** It stops the casual "I'll just reinstall it". It does not
/// stop a new device, an erased device, or a different Apple ID — nothing without a backend can.
/// That's a deliberate ceiling rather than an oversight: the airtight options are Apple's own
/// introductory free trial (which costs the introductory *price*, since a customer gets one
/// offer per subscription group, and which demands payment details before anyone can try the
/// app) and DeviceCheck (which needs a server to call Apple's API). Both were weighed and
/// declined for v1.
///
/// There is also a deterrent here that most apps don't have: every task, goal, focus session and
/// milestone lives on this device and nowhere else, so reinstalling to reset the trial destroys
/// the entire record the app exists to keep. The longer somebody uses Waypoint, the more a free
/// fortnight costs them.
enum TrialRecord {
    /// Namespaced to the bundle so a second app from the same team can't read or clobber it.
    private static let service = Bundle.main.bundleIdentifier ?? "com.waypoint.app"
    static let defaultAccount = "trial.startedAt"

    /// Where the trial start used to live. Read once, so an existing install doesn't have its
    /// trial restarted by the upgrade that moved it.
    private static let legacyDefaultsKey = "subscription.trialStartedAt"

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// `nil` means no trial has ever been started on this device — which callers must treat as
    /// "it hasn't begun yet", never as "it's over". A keychain that can't be read is a reason to
    /// let somebody use the app, not a reason to lock them out of it.
    static func start(account: String = defaultAccount) -> Date? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              data.count == MemoryLayout<Double>.size else { return nil }
        return Date(timeIntervalSince1970: data.withUnsafeBytes { $0.load(as: Double.self) })
    }

    @discardableResult
    static func setStart(_ date: Date, account: String = defaultAccount) -> Bool {
        var seconds = date.timeIntervalSince1970
        let data = Data(bytes: &seconds, count: MemoryLayout<Double>.size)

        // Update first, add if there was nothing — `SecItemAdd` fails outright on a duplicate,
        // which would otherwise make every write after the first one silently do nothing.
        let updated = SecItemUpdate(query(account: account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return true }

        var insert = query(account: account)
        insert[kSecValueData as String] = data
        // `AfterFirstUnlock`, not `WhenUnlocked`: entitlement is re-resolved from background
        // wake-ups too — a widget timeline refresh, a notification — and those can land on a
        // locked phone. Not `ThisDeviceOnly`, so an encrypted backup restored onto a new handset
        // carries the trial with it rather than handing out a second one.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    static func clear(account: String = defaultAccount) {
        SecItemDelete(query(account: account) as CFDictionary)
    }

    /// The trial start for this install, creating one if this is genuinely the first run.
    ///
    /// Carries over anything the `UserDefaults` version wrote, so upgrading doesn't reset the
    /// clock for people who are mid-trial — their start date moves into the keychain rather than
    /// being replaced by today.
    static func startOrBegin(now: Date = .now, account: String = defaultAccount) -> Date {
        if let existing = start(account: account) { return existing }

        let defaults = UserDefaults.standard
        if let migrated = defaults.object(forKey: legacyDefaultsKey) as? Date {
            setStart(migrated, account: account)
            return migrated
        }

        setStart(now, account: account)
        // Mirrored, so a keychain that refuses to write doesn't restart the trial on every
        // single launch. The keychain is the durable copy; this is the one that keeps today
        // working if it isn't available.
        defaults.set(now, forKey: legacyDefaultsKey)
        return now
    }
}
