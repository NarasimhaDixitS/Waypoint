import SwiftUI
import Combine

enum AppearanceMode: String, CaseIterable, Hashable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum CompletionMode: String, CaseIterable, Hashable {
    case manual
    case autoByTime

    var label: String {
        switch self {
        case .manual: "Mark done manually"
        case .autoByTime: "Auto-complete when time passes"
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var appearanceMode: AppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: Keys.appearance) }
    }
    @Published var accentSwatch: AccentSwatch {
        didSet { UserDefaults.standard.set(accentSwatch.rawValue, forKey: Keys.accent) }
    }
    @Published var completionMode: CompletionMode {
        didSet { UserDefaults.standard.set(completionMode.rawValue, forKey: Keys.completion) }
    }
    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notifications)
            if notificationsEnabled {
                NotificationManager.requestAuthorizationIfNeeded()
                NotificationManager.scheduleDailySummary()
            } else {
                NotificationManager.disableAll()
            }
        }
    }
    /// Dev-only toggle standing in for a resolved StoreKit subscription state.
    @Published var isPro: Bool {
        didSet { UserDefaults.standard.set(isPro, forKey: Keys.isPro) }
    }

    private enum Keys {
        static let appearance = "themeAppearanceMode"
        static let accent = "themeAccentSwatch"
        static let completion = "themeCompletionMode"
        static let notifications = "themeNotificationsEnabled"
        static let isPro = "themeIsPro"
    }

    private init() {
        let defaults = UserDefaults.standard
        appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        accentSwatch = AccentSwatch(rawValue: defaults.string(forKey: Keys.accent) ?? "") ?? .green
        completionMode = CompletionMode(rawValue: defaults.string(forKey: Keys.completion) ?? "") ?? .manual
        notificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? true
        isPro = defaults.object(forKey: Keys.isPro) as? Bool ?? false
    }
}
