import SwiftUI
import UIKit

enum ColorTokens {
    // MARK: - Palette

    static let surface0 = dynamic(light: hex(0xF5F5F3), dark: hex(0x1C1C1A))
    static let surface1 = dynamic(light: hex(0xFFFFFF), dark: hex(0x242422))
    static let textPrimary = dynamic(light: hex(0x2C2C2A), dark: hex(0xF1EFE8))
    static let textSecondary = dynamic(light: hex(0x5F5E5A), dark: hex(0xB4B2A9))
    static let textMuted = Color(hex(0x888780))
    static let border = dynamic(light: hex(0xE5E3DB), dark: hex(0x3A3A37))

    static let success = Color(hex(0x639922))
    static let textSuccess = dynamic(light: hex(0x3B6D11), dark: hex(0xC0DD97))
    static let successTint = dynamic(
        light: mix(hex(0x639922), over: hex(0xFFFFFF), amount: 0.24),
        dark: mix(hex(0x639922), over: hex(0x242422), amount: 0.24)
    )

    /// "In progress" role token — fixed semantic color, independent of the user's accent swatch.
    static let inProgress = dynamic(light: hex(0x378ADD), dark: hex(0x85B7EB))
    static let textInProgress = dynamic(light: hex(0x185FA5), dark: hex(0xB5D4F4))
    static let inProgressTint = dynamic(
        light: mix(hex(0x378ADD), over: hex(0xFFFFFF), amount: 0.24),
        dark: mix(hex(0x85B7EB), over: hex(0x242422), amount: 0.24)
    )

    /// "Needs attention" role token — schedule conflicts, warnings.
    static let warning = Color(hex(0xD85A30))
    static let textWarning = dynamic(light: hex(0xB0431E), dark: hex(0xF0A583))
    static let warningTint = dynamic(
        light: mix(hex(0xD85A30), over: hex(0xFFFFFF), amount: 0.24),
        dark: mix(hex(0xD85A30), over: hex(0x242422), amount: 0.24)
    )

    /// "Scheduled for later" role token — tasks on a day that hasn't arrived yet.
    static let scheduled = dynamic(light: hex(0x7B5EA7), dark: hex(0xB79BDB))
    static let textScheduled = dynamic(light: hex(0x5C4380), dark: hex(0xD3C0EE))
    static let scheduledTint = dynamic(
        light: mix(hex(0x7B5EA7), over: hex(0xFFFFFF), amount: 0.24),
        dark: mix(hex(0xB79BDB), over: hex(0x242422), amount: 0.24)
    )

    static let cardShadow = Color.black.opacity(0.07)

    // MARK: - Helpers

    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func mix(_ foreground: UIColor, over background: UIColor, amount: CGFloat) -> UIColor {
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        foreground.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        background.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(
            red: fr * amount + br * (1 - amount),
            green: fg * amount + bg * (1 - amount),
            blue: fb * amount + bb * (1 - amount),
            alpha: 1
        )
    }

    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { trait in trait.userInterfaceStyle == .dark ? dark : light })
    }
}
