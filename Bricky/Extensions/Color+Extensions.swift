import SwiftUI

/// Extension for LEGO-themed colors
extension Color {
    static let legoRed = Color(hex: "C91A09")
    static let legoBlue = Color(hex: "0055BF")
    static let legoYellow = Color(hex: "F2CD37")
    static let legoGreen = Color(hex: "237841")
    static let legoOrange = Color(hex: "FE8A18")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    static func legoColor(_ color: LegoColor) -> Color {
        Color(hex: color.hexColor)
    }

    // MARK: - Confidence Colors

    /// Color for scan confidence indicators
    static func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.9...: return .green
        case 0.7..<0.9: return .orange
        default: return .red
        }
    }

    /// SF Symbol name for confidence level
    static func confidenceIcon(_ confidence: Double) -> String {
        switch confidence {
        case 0.9...: return "checkmark.seal.fill"
        case 0.7..<0.9: return "exclamationmark.triangle.fill"
        default: return "questionmark.circle.fill"
        }
    }
}
