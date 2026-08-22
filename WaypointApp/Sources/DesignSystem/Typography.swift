import SwiftUI
import UIKit

enum WPTypography: Equatable {
    case appTitle, screenTitle, cardTitle, body, micro, bigStat

    private var baseSize: CGFloat {
        switch self {
        case .appTitle: 29
        case .screenTitle: 23
        case .cardTitle: 14.5
        case .body: 13
        case .micro: 11
        case .bigStat: 19
        }
    }

    private var weight: UIFont.Weight {
        switch self {
        case .appTitle, .screenTitle, .cardTitle, .bigStat: .semibold
        case .body, .micro: .regular
        }
    }

    /// The closest built-in text style to scale against, so Dynamic Type moves each role a
    /// sensible amount relative to the others rather than uniformly.
    private var relativeStyle: UIFont.TextStyle {
        switch self {
        case .appTitle: .largeTitle
        case .screenTitle: .title2
        case .cardTitle: .headline
        case .body: .subheadline
        case .micro: .caption2
        case .bigStat: .title3
        }
    }

    /// Scaled via UIFontMetrics rather than a plain `.system(size:)`, so these exact base
    /// sizes still respond to the user's Dynamic Type setting instead of staying fixed.
    var font: Font {
        let base = UIFont.systemFont(ofSize: baseSize, weight: weight)
        return Font(UIFontMetrics(forTextStyle: relativeStyle).scaledFont(for: base))
    }

    var tracking: CGFloat {
        self == .appTitle ? -0.5 : 0
    }
}

extension View {
    func wpTypography(_ style: WPTypography) -> some View {
        font(style.font).tracking(style.tracking)
    }
}
