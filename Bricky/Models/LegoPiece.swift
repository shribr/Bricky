import Foundation
import UIKit

/// Represents a single identified LEGO piece with its properties
struct LegoPiece: Identifiable, Codable, Hashable {
    let id: UUID
    let partNumber: String
    let name: String
    let category: PieceCategory
    let color: LegoColor
    let dimensions: PieceDimensions
    let confidence: Double
    var quantity: Int

    /// Normalized bounding box from Vision (origin bottom-left) for the first detection
    var boundingBox: CGRect?

    /// All detected locations for this piece type (normalized Vision coords)
    /// Used for deduplication — prevents counting the same physical piece twice
    var detectionLocations: [CGRect]

    /// Optional per-detection depth (meters from camera) for 3D-aware dedup.
    /// Indices correspond to `detectionLocations`. nil entries mean depth was unknown.
    var detectionDepths: [Float?] = []

    /// Snapshot of the source image with this piece's location highlighted (not persisted)
    var locationSnapshot: UIImage?

    /// Index into the ScanSession's sourceImages array (used for composite screenshot mode)
    var captureIndex: Int?

    enum CodingKeys: String, CodingKey {
        case id, partNumber, name, category, color, dimensions, confidence, quantity, boundingBox, detectionLocations, captureIndex
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(partNumber, forKey: .partNumber)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(color, forKey: .color)
        try container.encode(dimensions, forKey: .dimensions)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(quantity, forKey: .quantity)
        if let box = boundingBox {
            try container.encode(CodableRect(rect: box), forKey: .boundingBox)
        }
        try container.encode(detectionLocations.map { CodableRect(rect: $0) }, forKey: .detectionLocations)
        try container.encodeIfPresent(captureIndex, forKey: .captureIndex)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        partNumber = try container.decode(String.self, forKey: .partNumber)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(PieceCategory.self, forKey: .category)
        color = try container.decode(LegoColor.self, forKey: .color)
        dimensions = try container.decode(PieceDimensions.self, forKey: .dimensions)
        confidence = try container.decode(Double.self, forKey: .confidence)
        quantity = try container.decode(Int.self, forKey: .quantity)
        if let codableBox = try container.decodeIfPresent(CodableRect.self, forKey: .boundingBox) {
            boundingBox = codableBox.rect
        } else {
            boundingBox = nil
        }
        detectionLocations = (try container.decodeIfPresent([CodableRect].self, forKey: .detectionLocations) ?? []).map { $0.rect }
        locationSnapshot = nil
        captureIndex = try container.decodeIfPresent(Int.self, forKey: .captureIndex)
    }

    static func == (lhs: LegoPiece, rhs: LegoPiece) -> Bool {
        lhs.id == rhs.id && lhs.partNumber == rhs.partNumber &&
        lhs.name == rhs.name && lhs.category == rhs.category &&
        lhs.color == rhs.color && lhs.dimensions == rhs.dimensions &&
        lhs.confidence == rhs.confidence && lhs.quantity == rhs.quantity &&
        lhs.boundingBox == rhs.boundingBox
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(partNumber)
        hasher.combine(name)
        hasher.combine(category)
        hasher.combine(color)
        hasher.combine(dimensions)
        hasher.combine(confidence)
        hasher.combine(quantity)
    }

    init(
        id: UUID = UUID(),
        partNumber: String,
        name: String,
        category: PieceCategory,
        color: LegoColor,
        dimensions: PieceDimensions,
        confidence: Double = 1.0,
        quantity: Int = 1,
        boundingBox: CGRect? = nil,
        detectionLocations: [CGRect] = [],
        locationSnapshot: UIImage? = nil,
        captureIndex: Int? = nil
    ) {
        self.id = id
        self.partNumber = partNumber
        self.name = name
        self.category = category
        self.color = color
        self.dimensions = dimensions
        self.confidence = confidence
        self.quantity = quantity
        self.boundingBox = boundingBox
        self.detectionLocations = detectionLocations
        self.locationSnapshot = locationSnapshot
        self.captureIndex = captureIndex
    }
}

/// Codable wrapper for CGRect since CGRect doesn't conform to Codable
struct CodableRect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct PieceDimensions: Codable, Hashable {
    let studsWide: Int
    let studsLong: Int
    let heightUnits: Int // 1 = plate height, 3 = brick height

    var displayString: String {
        if heightUnits == 1 {
            return "\(studsWide)×\(studsLong) Plate"
        } else if heightUnits == 3 {
            return "\(studsWide)×\(studsLong) Brick"
        } else {
            return "\(studsWide)×\(studsLong)×\(heightUnits)"
        }
    }
}

enum PieceCategory: String, Codable, CaseIterable, Hashable {
    case brick = "Brick"
    case plate = "Plate"
    case tile = "Tile"
    case slope = "Slope"
    case arch = "Arch"
    case round = "Round"
    case technic = "Technic"
    case specialty = "Specialty"
    case minifigure = "Minifigure"
    case window = "Window/Door"
    case wheel = "Wheel"
    case connector = "Connector"
    case hinge = "Hinge"
    case bracket = "Bracket"
    case wedge = "Wedge"
    case other = "Other"

    var systemImage: String {
        switch self {
        case .brick: return "cube.fill"
        case .plate: return "square.fill"
        case .tile: return "rectangle.fill"
        case .slope: return "triangle.fill"
        case .arch: return "archivebox.fill"
        case .round: return "circle.fill"
        case .technic: return "gearshape.fill"
        case .specialty: return "star.fill"
        case .minifigure: return "person.fill"
        case .window: return "window.vertical.open"
        case .wheel: return "circle.circle.fill"
        case .connector: return "link"
        case .hinge: return "arrow.turn.right.up"
        case .bracket: return "chevron.left.forwardslash.chevron.right"
        case .wedge: return "arrowtriangle.right.fill"
        case .other: return "questionmark.circle.fill"
        }
    }

    /// Parse a category from free-form cloud AI strings like "technic", "Technic Gear", "gear", etc.
    static func fromCloudString(_ value: String) -> PieceCategory {
        // Try exact raw value match first
        if let exact = PieceCategory(rawValue: value) { return exact }
        if let capitalized = PieceCategory(rawValue: value.capitalized) { return capitalized }

        // Fuzzy match on lowercase
        let lower = value.lowercased()
        if lower.contains("technic") || lower.contains("gear") || lower.contains("beam") ||
           lower.contains("axle") || lower.contains("liftarm") { return .technic }
        if lower.contains("wheel") || lower.contains("tire") || lower.contains("tyre") { return .wheel }
        if lower.contains("round") || lower.contains("cone") || lower.contains("dome") ||
           lower.contains("cylinder") || lower.contains("dish") { return .round }
        if lower.contains("slope") { return .slope }
        if lower.contains("arch") { return .arch }
        if lower.contains("tile") { return .tile }
        if lower.contains("wedge") { return .wedge }
        if lower.contains("minifig") { return .minifigure }
        if lower.contains("hinge") { return .hinge }
        if lower.contains("bracket") { return .bracket }
        if lower.contains("connector") { return .connector }
        if lower.contains("window") || lower.contains("door") { return .window }
        if lower.contains("plate") { return .plate }
        if lower.contains("brick") { return .brick }

        return .brick
    }
}

enum LegoColor: String, Codable, CaseIterable, Hashable {
    case red = "Red"
    case blue = "Blue"
    case yellow = "Yellow"
    case green = "Green"
    case black = "Black"
    case white = "White"
    case gray = "Gray"
    case darkGray = "Dark Gray"
    case orange = "Orange"
    case brown = "Brown"
    case tan = "Tan"
    case darkBlue = "Dark Blue"
    case darkGreen = "Dark Green"
    case darkRed = "Dark Red"
    case lime = "Lime"
    case purple = "Purple"
    case pink = "Pink"
    case lightBlue = "Light Blue"
    case transparent = "Transparent"
    case transparentBlue = "Trans Blue"
    case transparentRed = "Trans Red"

    var hexColor: String {
        switch self {
        case .red: return "#C91A09"
        case .blue: return "#0055BF"
        case .yellow: return "#F2CD37"
        case .green: return "#237841"
        case .black: return "#1B2A34"
        case .white: return "#F4F4F4"
        case .gray: return "#9BA19D"
        case .darkGray: return "#6D6E5C"
        case .orange: return "#FE8A18"
        case .brown: return "#583927"
        case .tan: return "#E4CD9E"
        case .darkBlue: return "#143044"
        case .darkGreen: return "#184632"
        case .darkRed: return "#720E0F"
        case .lime: return "#BBE90B"
        case .purple: return "#81007B"
        case .pink: return "#FC97AC"
        case .lightBlue: return "#B4D2E3"
        case .transparent: return "#EEEEEE"
        case .transparentBlue: return "#559AB7"
        case .transparentRed: return "#C91A09"
        }
    }

    /// Integer hex value for color distance calculations
    var hex: UInt32 {
        switch self {
        case .red: return 0xC91A09
        case .blue: return 0x0055BF
        case .yellow: return 0xF2CD37
        case .green: return 0x237841
        case .black: return 0x1B2A34
        case .white: return 0xF4F4F4
        case .gray: return 0x9BA19D
        case .darkGray: return 0x6D6E5C
        case .orange: return 0xFE8A18
        case .brown: return 0x583927
        case .tan: return 0xE4CD9E
        case .darkBlue: return 0x143044
        case .darkGreen: return 0x184632
        case .darkRed: return 0x720E0F
        case .lime: return 0xBBE90B
        case .purple: return 0x81007B
        case .pink: return 0xFC97AC
        case .lightBlue: return 0xB4D2E3
        case .transparent: return 0xEEEEEE
        case .transparentBlue: return 0x559AB7
        case .transparentRed: return 0xC91A09
        }
    }
}
