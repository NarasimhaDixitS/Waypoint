import SwiftUI

enum AccentSwatch: String, CaseIterable, Identifiable, Hashable {
    case green, blue, orange, pink

    var id: String { rawValue }

    private var hexValue: UInt32 {
        switch self {
        case .green: 0x3B6D11
        case .blue: 0x378ADD
        case .orange: 0xD85A30
        case .pink: 0xD4537E
        }
    }

    var color: Color { Color(ColorTokens.hex(hexValue)) }

    /// The color-wheel opposite of `color` (~180° hue rotation) — used for `CurvedBackground`,
    /// which tints toward this instead of the accent itself so accent-colored elements (the
    /// FAB, in-progress borders) get real contrast against the background rather than blending
    /// into a same-hue tint.
    private var complementaryHexValue: UInt32 {
        switch self {
        case .green: 0xC8A1E9
        case .blue: 0xDD8A37
        case .orange: 0x30AED8
        case .pink: 0x53D4A9
        }
    }

    var complementaryColor: Color { Color(ColorTokens.hex(complementaryHexValue)) }
}
