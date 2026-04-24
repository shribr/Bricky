import Foundation
import SwiftUI

// MARK: - Slot taxonomy

/// The anatomical slot a minifigure part belongs to.
/// Used to render the silhouette layout (head→hair→torso→arms/hands→hips→legs).
enum MinifigurePartSlot: String, Codable, CaseIterable, Hashable {
    case head
    case hairOrHeadgear
    case torso
    case armLeft
    case armRight
    case handLeft
    case handRight
    case hips
    case legLeft
    case legRight
    case accessory

    var displayName: String {
        switch self {
        case .head: return "Head"
        case .hairOrHeadgear: return "Hair / Headgear"
        case .torso: return "Torso"
        case .armLeft: return "Left Arm"
        case .armRight: return "Right Arm"
        case .handLeft: return "Left Hand"
        case .handRight: return "Right Hand"
        case .hips: return "Hips"
        case .legLeft: return "Left Leg"
        case .legRight: return "Right Leg"
        case .accessory: return "Accessory"
        }
    }

    /// SF Symbol used in the silhouette tile.
    var systemImage: String {
        switch self {
        case .head: return "face.smiling"
        case .hairOrHeadgear: return "graduationcap.fill"
        case .torso: return "tshirt.fill"
        case .armLeft, .armRight: return "figure.arms.open"
        case .handLeft, .handRight: return "hand.raised.fill"
        case .hips: return "rectangle.fill"
        case .legLeft, .legRight: return "figure.walk"
        case .accessory: return "wand.and.stars"
        }
    }

    /// Anatomical row order for layout (top → bottom).
    var displayOrder: Int {
        switch self {
        case .hairOrHeadgear: return 0
        case .head: return 1
        case .armLeft, .torso, .armRight: return 2
        case .handLeft, .handRight: return 3
        case .hips: return 4
        case .legLeft, .legRight: return 5
        case .accessory: return 6
        }
    }
}

// MARK: - Part requirement

/// One part required to assemble a minifigure.
struct MinifigurePartRequirement: Codable, Hashable {
    let slot: MinifigurePartSlot
    /// BrickLink / Rebrickable part number (e.g. "3626c" head, "973" torso).
    let partNumber: String
    /// Color name matching `LegoColor.rawValue`.
    let color: String
    /// Quantity required (almost always 1; hands are 2 but tracked as separate slots).
    let quantity: Int
    /// Optional parts (e.g. accessories) — excluded from completion %.
    let optional: Bool
    /// Display name (e.g. "Minifigure Helmet Viking").
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case slot
        case partNumber
        case color
        case quantity = "qty"
        case optional
        case displayName
    }

    init(slot: MinifigurePartSlot,
         partNumber: String,
         color: String,
         quantity: Int = 1,
         optional: Bool = false,
         displayName: String = "") {
        self.slot = slot
        self.partNumber = partNumber
        self.color = color
        self.quantity = quantity
        self.optional = optional
        self.displayName = displayName.isEmpty ? "\(slot.displayName) (\(partNumber))" : displayName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.slot = try c.decode(MinifigurePartSlot.self, forKey: .slot)
        self.partNumber = try c.decode(String.self, forKey: .partNumber)
        self.color = try c.decode(String.self, forKey: .color)
        self.quantity = try c.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        self.optional = try c.decodeIfPresent(Bool.self, forKey: .optional) ?? false
        self.displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
    }

    /// Resolve `color` string → `LegoColor` enum, falling back to `.gray`.
    /// Supports both canonical names and aliases (e.g. "Trans Red").
    var legoColor: LegoColor {
        LegoColor(fromString: color) ?? .gray
    }
}

// MARK: - Minifigure

/// A complete LEGO minifigure (catalog entry).
struct Minifigure: Identifiable, Codable, Hashable {
    /// Rebrickable / BrickLink fig id (e.g. "fig-000123" or "sw0001a").
    let id: String
    let name: String
    /// Top-level theme (e.g. "Star Wars", "Castle", "Classic Space").
    let theme: String
    /// First year the figure appeared (used for sort + filter).
    let year: Int
    /// Total part count (for display + sort).
    let partCount: Int
    /// Optional Rebrickable / BrickLink CDN URL for the fig artwork.
    let imgURL: String?
    /// Required + optional parts.
    let parts: [MinifigurePartRequirement]

    /// SF Symbol fallback when artwork fails to load.
    var fallbackSystemImage: String { "person.fill" }

    /// First non-empty image URL to load; nil for SF Symbol fallback.
    var imageURL: URL? {
        guard let imgURL, !imgURL.isEmpty else { return nil }
        return URL(string: imgURL)
    }

    /// Required parts (for completion calc).
    var requiredParts: [MinifigurePartRequirement] {
        parts.filter { !$0.optional }
    }

    /// Convenient lookup of the torso part — used by the torso-scan identifier.
    var torsoPart: MinifigurePartRequirement? {
        parts.first { $0.slot == .torso }
    }

    /// Return a copy of this figure with a different image URL.
    func withImageURL(_ newURL: String?) -> Minifigure {
        Minifigure(id: id, name: name, theme: theme, year: year,
                   partCount: partCount, imgURL: newURL, parts: parts)
    }
}
