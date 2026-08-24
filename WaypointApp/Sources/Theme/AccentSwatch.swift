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
}
