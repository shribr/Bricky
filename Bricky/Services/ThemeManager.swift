import SwiftUI

/// Manages app appearance: color scheme and accent theme
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    enum AppearanceMode: String, CaseIterable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    enum ColorTheme: String, CaseIterable, Identifiable {
        case classic = "Classic"
        case ocean = "Ocean"
        case sunset = "Sunset"
        case forest = "Forest"
        case neon = "Neon"

        var id: String { rawValue }

        var primary: Color {
            switch self {
            case .classic: return Color.legoRed
            case .ocean: return Color(hex: "0077B6")
            case .sunset: return Color(hex: "FF6B35")
            case .forest: return Color(hex: "2D6A4F")
            case .neon: return Color(hex: "BC00FF")
            }
        }

        var secondary: Color {
            switch self {
            case .classic: return Color.legoBlue
            case .ocean: return Color(hex: "00B4D8")
            case .sunset: return Color(hex: "F7931E")
            case .forest: return Color(hex: "52B788")
            case .neon: return Color(hex: "00F5D4")
            }
        }

        var accent: Color {
            switch self {
            case .classic: return Color.legoYellow
            case .ocean: return Color(hex: "90E0EF")
            case .sunset: return Color(hex: "FFD166")
            case .forest: return Color(hex: "95D5B2")
            case .neon: return Color(hex: "FEE440")
            }
        }

        var gradientColors: [Color] {
            [primary, secondary]
        }

        var previewColors: [Color] {
            [primary, secondary, accent]
        }
    }

    enum ScanOverlayStyle: String, CaseIterable, Identifiable {
        case brickit = "Brickit"
        case clean = "Clean"
        case detailed = "Detailed"
        case minimal = "Minimal"
        case none = "None"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .brickit: return "Orange viewfinder boxes with corner accents (recommended)"
            case .clean: return "White boxes with compact labels"
            case .detailed: return "Color-coded boxes with corner accents"
            case .minimal: return "Boxes only, no labels"
            case .none: return "No overlays — just scan frame with piece count and notifications"
            }
        }

        var iconName: String {
            switch self {
            case .brickit: return "viewfinder.circle.fill"
            case .clean: return "rectangle.dashed"
            case .detailed: return "rectangle.badge.checkmark"
            case .minimal: return "square"
            case .none: return "viewfinder"
            }
        }
    }

    /// Controls the grid resolution of the scan coverage tracker.
    /// Higher detail = more grid cells = finer coverage map but more work per frame.
    enum ScanCoverageDetail: String, CaseIterable, Identifiable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case ultra = "Ultra"

        var id: String { rawValue }

        var columns: Int {
            switch self {
            case .low: return 8
            case .medium: return 12
            case .high: return 20
            case .ultra: return 32
            }
        }

        var rows: Int {
            switch self {
            case .low: return 10
            case .medium: return 16
            case .high: return 28
            case .ultra: return 44
            }
        }

        var description: String {
            switch self {
            case .low: return "Coarse grid (\(columns)×\(rows)) — fast, broad coverage"
            case .medium: return "Balanced grid (\(columns)×\(rows)) — good for most scans"
            case .high: return "Fine grid (\(columns)×\(rows)) — precise coverage mapping"
            case .ultra: return "Very fine grid (\(columns)×\(rows)) — maximum detail"
            }
        }

        var iconName: String {
            switch self {
            case .low: return "square.grid.2x2"
            case .medium: return "square.grid.3x3"
            case .high: return "square.grid.4x3.fill"
            case .ultra: return "circle.grid.3x3.fill"
            }
        }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode") }
    }

    @Published var colorTheme: ColorTheme {
        didSet { UserDefaults.standard.set(colorTheme.rawValue, forKey: "colorTheme") }
    }

    @Published var scanOverlayStyle: ScanOverlayStyle {
        didSet { UserDefaults.standard.set(scanOverlayStyle.rawValue, forKey: "scanOverlayStyle") }
    }

    @Published var scanCoverageDetail: ScanCoverageDetail {
        didSet { UserDefaults.standard.set(scanCoverageDetail.rawValue, forKey: "scanCoverageDetail") }
    }

    private init() {
        let modeStr = UserDefaults.standard.string(forKey: "appearanceMode") ?? "System"
        appearanceMode = AppearanceMode(rawValue: modeStr) ?? .system

        let themeStr = UserDefaults.standard.string(forKey: "colorTheme") ?? "Classic"
        colorTheme = ColorTheme(rawValue: themeStr) ?? .classic

        let overlayStr = UserDefaults.standard.string(forKey: "scanOverlayStyle") ?? "Brickit"
        scanOverlayStyle = ScanOverlayStyle(rawValue: overlayStr) ?? .brickit

        let detailStr = UserDefaults.standard.string(forKey: "scanCoverageDetail") ?? "Medium"
        scanCoverageDetail = ScanCoverageDetail(rawValue: detailStr) ?? .medium
    }
}
