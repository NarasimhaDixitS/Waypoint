import SwiftUI
import UIKit

/// Hides scrolling content behind the status bar instead of letting it collide with the clock.
///
/// Every screen here sets `navigationBarHidden(true)` and draws its own header inside a
/// ScrollView, so there is nothing between the content and the status bar. The page background
/// already extends up there — but so does the content, which meant a title scrolling up landed
/// on top of the clock and behind the Dynamic Island.
///
/// A plain opaque strip would fix it and slice the content off at a hard line. This fades over
/// its last third instead, so text dissolves on the way out — the same treatment the Week tab's
/// day separators use at their ends, rather than a new idea invented for this.
private struct TopFade: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: ColorTokens.surface0, location: 0),
                    .init(color: ColorTokens.surface0, location: 0.68),
                    .init(color: ColorTokens.surface0.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.statusBarInset + 16)
            .ignoresSafeArea(edges: .top)
            // Purely a mask — the header underneath keeps its own taps.
            .allowsHitTesting(false)
        }
    }

    /// Read from the window rather than a `GeometryReader`: a reader placed here reports the
    /// geometry of the view it's inside, which is already inset by the very number we need.
    ///
    /// Safe to read once. The app is portrait-only, so this can't change while it runs, and the
    /// fallback covers a notch-era device if the window isn't up yet.
    private static let statusBarInset: CGFloat = {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let inset = scenes.first?.keyWindow?.safeAreaInsets.top ?? 0
        return inset > 0 ? inset : 47
    }()
}

extension View {
    /// Applied once, around the whole tab container, rather than per screen — all four tabs
    /// share the same background and the same problem.
    func wpTopFade() -> some View { modifier(TopFade()) }
}
