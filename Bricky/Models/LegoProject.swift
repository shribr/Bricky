import Foundation

/// Represents a buildable LEGO creation with required pieces
struct LegoProject: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let difficulty: Difficulty
    let category: ProjectCategory
    let estimatedTime: String
    let requiredPieces: [RequiredPiece]
    let instructions: [BuildStep]
    let imageSystemName: String
    let funFact: String?
    var isFavorited: Bool

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        difficulty: Difficulty,
        category: ProjectCategory,
        estimatedTime: String,
        requiredPieces: [RequiredPiece],
        instructions: [BuildStep],
        imageSystemName: String,
        funFact: String? = nil,
        isFavorited: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.difficulty = difficulty
        self.category = category
        self.estimatedTime = estimatedTime
        self.requiredPieces = requiredPieces
        self.instructions = instructions
        self.imageSystemName = imageSystemName
        self.funFact = funFact
        self.isFavorited = isFavorited
    }

    /// How many of the required pieces the user has
    func matchPercentage(with inventory: [LegoPiece]) -> Double {
        guard !requiredPieces.isEmpty else { return 0 }

        var matched = 0
        var total = 0

        for required in requiredPieces {
            total += required.quantity
            let available = inventory.filter { piece in
                piece.category == required.category &&
                piece.dimensions.studsWide == required.dimensions.studsWide &&
                piece.dimensions.studsLong == required.dimensions.studsLong &&
                (required.flexible || required.colorPreference == nil || piece.color == required.colorPreference)
            }.reduce(0) { $0 + $1.quantity }
            matched += min(available, required.quantity)
        }

        return total > 0 ? Double(matched) / Double(total) : 0
    }

    /// Pieces the user is missing
    func missingPieces(from inventory: [LegoPiece]) -> [RequiredPiece] {
        requiredPieces.compactMap { required in
            let available = inventory.filter { piece in
                piece.category == required.category &&
                piece.dimensions.studsWide == required.dimensions.studsWide &&
                piece.dimensions.studsLong == required.dimensions.studsLong &&
                (required.flexible || required.colorPreference == nil || piece.color == required.colorPreference)
            }.reduce(0) { $0 + $1.quantity }

            let missing = required.quantity - available
            if missing > 0 {
                return RequiredPiece(
                    category: required.category,
                    dimensions: required.dimensions,
                    colorPreference: required.colorPreference,
                    quantity: missing,
                    flexible: required.flexible
                )
            }
            return nil
        }
    }

    /// Estimated build time in minutes based on piece count and difficulty
    var estimatedMinutes: Int {
        let pieceCount = requiredPieces.reduce(0) { $0 + $1.quantity }
        let multiplier: Double = switch difficulty {
        case .beginner: 0.5
        case .easy: 0.75
        case .medium: 1.0
        case .hard: 1.5
        case .expert: 2.0
        }
        return max(5, Int(Double(pieceCount) * multiplier))
    }
}

struct RequiredPiece: Codable, Identifiable {
    var id: String {
        "\(category.rawValue)-\(dimensions.studsWide)x\(dimensions.studsLong)x\(dimensions.heightUnits)-\(colorPreference?.rawValue ?? "any")-\(quantity)"
    }
    let category: PieceCategory
    let dimensions: PieceDimensions
    let colorPreference: LegoColor?
    let quantity: Int
    let flexible: Bool // true if any color works

    var displayName: String {
        let colorStr = flexible ? "Any Color" : (colorPreference?.rawValue ?? "Any Color")
        return "\(quantity)× \(colorStr) \(dimensions.displayString)"
    }
}

struct BuildStep: Identifiable, Codable {
    let id: UUID
    let stepNumber: Int
    let instruction: String
    let piecesUsed: String
    let tip: String?

    init(
        id: UUID = UUID(),
        stepNumber: Int,
        instruction: String,
        piecesUsed: String,
        tip: String? = nil
    ) {
        self.id = id
        self.stepNumber = stepNumber
        self.instruction = instruction
        self.piecesUsed = piecesUsed
        self.tip = tip
    }
}

enum Difficulty: String, Codable, CaseIterable {
    case beginner = "Beginner"
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
    case expert = "Expert"

    var color: String {
        switch self {
        case .beginner: return "green"
        case .easy: return "green"
        case .medium: return "yellow"
        case .hard: return "orange"
        case .expert: return "red"
        }
    }

    var stars: Int {
        switch self {
        case .beginner: return 1
        case .easy: return 2
        case .medium: return 3
        case .hard: return 4
        case .expert: return 5
        }
    }
}

enum ProjectCategory: String, Codable, CaseIterable {
    case vehicle = "Vehicles"
    case building = "Buildings"
    case animal = "Animals"
    case robot = "Robots"
    case spaceship = "Spaceships"
    case furniture = "Furniture"
    case weapon = "Weapons"
    case art = "Art & Mosaic"
    case game = "Games"
    case gadget = "Gadgets"
    case nature = "Nature"
    case character = "Characters"
    case decoration = "Decorations"

    var systemImage: String {
        switch self {
        case .vehicle: return "car.fill"
        case .building: return "building.2.fill"
        case .animal: return "pawprint.fill"
        case .robot: return "cpu"
        case .spaceship: return "airplane"
        case .furniture: return "chair.fill"
        case .weapon: return "shield.fill"
        case .art: return "paintpalette.fill"
        case .game: return "gamecontroller.fill"
        case .gadget: return "wrench.and.screwdriver.fill"
        case .nature: return "leaf.fill"
        case .character: return "person.fill"
        case .decoration: return "sparkles"
        }
    }
}
