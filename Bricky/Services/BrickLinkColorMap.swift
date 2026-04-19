import Foundation

/// Single source of truth mapping `LegoColor` ↔ BrickLink color IDs.
/// Used by `InventoryExporter` (XML export), `BrickLinkService` (deep links),
/// and any future BrickLink integrations.
///
/// Reference: https://www.bricklink.com/catalogColors.asp
enum BrickLinkColorMap {

    /// Map our enum to BrickLink's numeric color id.
    static func id(for color: LegoColor) -> Int {
        switch color {
        case .red: return 5
        case .blue: return 7
        case .yellow: return 3
        case .green: return 6
        case .black: return 11
        case .white: return 1
        case .orange: return 4
        case .brown: return 8
        case .gray: return 9
        case .darkGray: return 10
        case .tan: return 2
        case .darkGreen: return 80
        case .darkBlue: return 63
        case .darkRed: return 59
        case .lime: return 34
        case .pink: return 23
        case .purple: return 24
        case .lightBlue: return 105
        case .transparent: return 12
        case .transparentBlue: return 15
        case .transparentRed: return 17
        }
    }

    /// Reverse map BrickLink color id → our enum. Used when importing data
    /// from BrickLink/Rebrickable. Returns `.gray` for unknown ids.
    static func color(forId id: Int) -> LegoColor {
        switch id {
        case 5: return .red
        case 7: return .blue
        case 3: return .yellow
        case 6: return .green
        case 11: return .black
        case 1: return .white
        case 4: return .orange
        case 8: return .brown
        case 9: return .gray
        case 10: return .darkGray
        case 2: return .tan
        case 80: return .darkGreen
        case 63: return .darkBlue
        case 59: return .darkRed
        case 34: return .lime
        case 23: return .pink
        case 24: return .purple
        case 105: return .lightBlue
        case 12: return .transparent
        case 15: return .transparentBlue
        case 17: return .transparentRed
        default: return .gray
        }
    }
}
