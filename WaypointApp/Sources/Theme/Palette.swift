import SwiftUI

/// Which set of colours the app draws itself in — a second axis, independent of light/dark.
///
/// **Why a palette and not a third appearance mode.** `ColorTokens.dynamic(light:dark:)`
/// resolves through `UIColor`'s trait collection, which only knows two states, so "paper" could
/// never have been a third one without unpicking every token. Keeping it on its own axis leaves
/// `dynamic` exactly as it was — paper simply hands it the same value twice.
///
/// **Paper is monochrome, and it is one thing.** Not a warm skin over the same coloured app —
/// the first attempt at this was exactly that, a sepia accent on a cream ground, and it read as
/// a ninth accent rather than a different mode. There is no hue in paper at all: one ink, a
/// couple of greys, an off-white ground, and nothing else. Where the standard palette reaches
/// for a colour to carry meaning, paper reaches for weight — solid ink against outline, bold
/// against muted.
///
/// It also has **no light and dark**. Paper is a single appearance, the way a printed page is,
/// so the light/dark control does nothing while it's on and says so. That's why every paper
/// value below is the same for both schemes, and why the app pins the colour scheme to light
/// when paper is selected: a dark status bar over an off-white page is the one piece of chrome
/// the palette can't reach.
///
/// Measured ratios are recorded against each token in `ColorTokens`.
enum Palette: String, CaseIterable, Identifiable, Hashable {
    case standard, paper

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .paper: "Paper"
        }
    }

    var detail: String {
        switch self {
        case .standard: "Full colour, with depth and highlights"
        case .paper: "Monochrome and flat, like a printed page. No light or dark."
        }
    }

    /// Paper draws itself identically whatever the system or the user asks for, so the app pins
    /// the scheme rather than leaving the status bar and keyboard to guess.
    var forcedColorScheme: ColorScheme? { self == .paper ? .light : nil }

    /// Cards are outlined rather than lifted. With no shadow and almost no fill difference
    /// between a card and the page, an edge is the only thing left that can say "this is a
    /// separate object" — and an outline *is* the look, not a substitute for it.
    var usesOutlines: Bool { self == .paper }

    /// Paper is matte: no drop shadows, no halo on the progress ring, no aura behind the
    /// today dot. Those are the cues that say "lit screen", and removing them does more for
    /// how the app feels than the colours do.
    var usesDepth: Bool { self == .standard }

    /// A mutable global, deliberately.
    ///
    /// `ColorTokens` is an enum of statics reached from every view in the app without being
    /// passed anywhere, and a palette has to be readable from exactly the same places. Threading
    /// it through the environment would mean touching all twenty-nine files that read a token,
    /// to solve a problem that is genuinely global: there is one app, drawn one way at a time.
    ///
    /// `ThemeManager` owns writing it. Read it anywhere.
    static var current: Palette = {
        let raw = sharedDefaults?.string(forKey: storageKey)
            ?? UserDefaults.standard.string(forKey: storageKey)
        return Palette(rawValue: raw ?? "") ?? .standard
    }()

    /// Mirrored into the app group for the same reason the accent is: the widget runs in its own
    /// process, can't see the app's `UserDefaults`, and a bright widget sitting beside a paper
    /// app is the thing that makes both look unfinished.
    static let sharedDefaults = UserDefaults(suiteName: PersistenceController.appGroupID)
    static let storageKey = "themePalette"
}
