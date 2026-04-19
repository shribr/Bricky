import Foundation

/// Pure functions to map a part name → `MinifigurePartSlot`.
/// Used by the catalog seeder + future inventory analytics.
enum MinifigurePartClassifier {

    /// Classify a `LegoPiece`. Only minifigure-category pieces produce a non-nil slot.
    static func slot(for piece: LegoPiece) -> MinifigurePartSlot? {
        guard piece.category == .minifigure else { return nil }
        return slot(forName: piece.name)
    }

    /// Classify by name keyword. Returns `.accessory` as a sensible default for
    /// minifig-category pieces that don't match a specific anatomical keyword.
    static func slot(forName rawName: String) -> MinifigurePartSlot? {
        let name = rawName.lowercased()

        // Headgear (checked BEFORE head, so "headgear" doesn't match "head")
        if name.contains("hair") ||
            name.contains("cap") ||
            name.contains("hat") ||
            name.contains("helmet") ||
            name.contains("hood") ||
            name.contains("headdress") ||
            name.contains("headgear") ||
            name.contains("crown") ||
            name.contains("turban") ||
            name.contains("mask") {
            return .hairOrHeadgear
        }

        if name.contains("head") {
            return .head
        }

        if name.contains("torso") || name.contains("body") {
            return .torso
        }

        if name.contains("hand") {
            return .handLeft
        }

        if name.contains("arm") {
            return .armLeft
        }

        if name.contains("hip") || name.contains("pelvis") {
            return .hips
        }

        if name.contains("leg") {
            return .legLeft
        }

        // Anything else categorized as a minifig part is treated as an accessory
        // (sword, wand, pickaxe, fishing rod, shield, torch, etc.).
        return .accessory
    }
}
