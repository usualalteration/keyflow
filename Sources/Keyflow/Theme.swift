import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

enum Theme {
    static let bg = Color(hex: 0x09090C)
    static let panel = Color(hex: 0x101015)
    static let line = Color.white.opacity(0.08)
    static let dim = Color.white.opacity(0.5)
    static let mono = Font.system(size: 11, weight: .regular, design: .monospaced)

    /// Main accent (changes with the chosen neon palette).
    static var accent = Color(hex: 0xB4FF78)
    /// Companion accent. Historical name: it started out as cyan; it now follows the palette.
    static var cyan = Color(hex: 0x4DE3F0)

    private static var rgbA: (Double, Double, Double) = rgb(0xB4FF78)
    private static var rgbB: (Double, Double, Double) = rgb(0x4DE3F0)

    private static func rgb(_ h: UInt32) -> (Double, Double, Double) {
        (Double((h >> 16) & 0xFF) / 255, Double((h >> 8) & 0xFF) / 255, Double(h & 0xFF) / 255)
    }

    static func apply(_ a: AccentColor) {
        accent = Color(hex: a.primaryHex)
        cyan = Color(hex: a.secondaryHex)
        rgbA = rgb(a.primaryHex)
        rgbB = rgb(a.secondaryHex)
    }

    /// Blend from accent (t = 0) to companion colour (t = 1).
    static func mix(_ t: Double) -> Color {
        let k = min(1, max(0, t))
        return Color(.sRGB,
                     red: rgbA.0 + (rgbB.0 - rgbA.0) * k,
                     green: rgbA.1 + (rgbB.1 - rgbA.1) * k,
                     blue: rgbA.2 + (rgbB.2 - rgbA.2) * k,
                     opacity: 1)
    }
}
