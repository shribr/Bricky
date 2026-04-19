import Foundation

/// Engine that suggests buildable projects based on available LEGO pieces
final class BuildSuggestionEngine {
    static let shared = BuildSuggestionEngine()

    private(set) var allProjects: [LegoProject] = []

    private init() {
        loadProjects()
    }

    /// Get build suggestions sorted by match percentage
    func getSuggestions(for pieces: [LegoPiece]) -> [BuildSuggestion] {
        allProjects.map { project in
            BuildSuggestion(
                project: project,
                matchPercentage: project.matchPercentage(with: pieces),
                missingPieces: project.missingPieces(from: pieces)
            )
        }
        .filter { $0.matchPercentage > 0.3 } // At least 30% match
        .sorted { $0.matchPercentage > $1.matchPercentage }
    }

    /// Get projects that can be fully built
    func getCompleteBuildable(for pieces: [LegoPiece]) -> [LegoProject] {
        allProjects.filter { $0.matchPercentage(with: pieces) >= 1.0 }
    }

    struct BuildSuggestion: Identifiable {
        let id = UUID()
        let project: LegoProject
        let matchPercentage: Double
        let missingPieces: [RequiredPiece]

        var isCompleteBuild: Bool { matchPercentage >= 1.0 }
        var percentageText: String { "\(Int(matchPercentage * 100))%" }
    }

    // MARK: - Project Library

    private func loadProjects() {
        allProjects = [
            // VEHICLES
            LegoProject(
                name: "Classic Race Car",
                description: "A sleek racing car with aerodynamic design. Perfect for beginners wanting to build their first vehicle.",
                difficulty: .easy,
                category: .vehicle,
                estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .white, quantity: 2, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the base chassis using the 2×4 plates side by side", piecesUsed: "2× 2×4 Plate", tip: "Make sure they're flush"),
                    BuildStep(stepNumber: 2, instruction: "Add 2×4 bricks on each end for the body", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Place 1×2 bricks along the sides for the doors", piecesUsed: "4× 1×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add slopes at the front and back for the hood and trunk", piecesUsed: "2× 2×2 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Attach wheels to the underside", piecesUsed: "4× Wheel"),
                    BuildStep(stepNumber: 6, instruction: "Add the windshield tile on top", piecesUsed: "1× 1×2 Tile", tip: "Use a transparent piece for the windshield"),
                ],
                imageSystemName: "car.fill",
                funFact: "The LEGO Group has produced over 4 billion tiny wheels, making them the world's largest tire manufacturer!"
            ),

            LegoProject(
                name: "Monster Truck",
                description: "A big, beefy monster truck with oversized wheels and a raised chassis. Looks awesome on any shelf.",
                difficulty: .medium,
                category: .vehicle,
                estimatedTime: "25 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .black, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .green, quantity: 4, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 6, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 2, flexible: true),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Start with the large 4×6 plate as the base", piecesUsed: "1× 4×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build up the raised body with 2×2 and 2×4 bricks", piecesUsed: "4× 2×4 Brick, 6× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add 1×4 bricks along the sides for the frame rails", piecesUsed: "4× 1×4 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Use Technic bricks for the axle supports", piecesUsed: "2× Technic 1×4"),
                    BuildStep(stepNumber: 5, instruction: "Add slopes for the cab roof", piecesUsed: "2× 2×2 Slope", tip: "Angle them to create an aggressive look"),
                    BuildStep(stepNumber: 6, instruction: "Mount the large wheels", piecesUsed: "4× Large Wheel"),
                ],
                imageSystemName: "truck.box.fill",
                funFact: "If you stacked all the LEGO bricks ever produced, they'd reach from Earth to the Moon ten times!"
            ),

            // BUILDINGS
            LegoProject(
                name: "Cozy Cottage",
                description: "A charming little house with a door, windows, and a peaked roof. A classic build that teaches fundamental techniques.",
                difficulty: .easy,
                category: .building,
                estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 8, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 8, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 6, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 4, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .red, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the 4×8 base plate — this is your foundation", piecesUsed: "1× 4×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build the walls 3 bricks high, leaving gaps for the door and windows", piecesUsed: "8× 1×4, 6× 1×2, 4× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add slope bricks on each side to form the peaked roof", piecesUsed: "4× 2×4 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Add tile pieces for the door and window shutters", piecesUsed: "2× 1×2 Tile"),
                    BuildStep(stepNumber: 5, instruction: "Top it off with plates along the roof ridge", piecesUsed: "4× 1×2 Plate", tip: "Use contrasting colors for the trim"),
                ],
                imageSystemName: "house.fill",
                funFact: "There are over 400 billion LEGO bricks in the world — about 62 for every person on Earth!"
            ),

            LegoProject(
                name: "Skyscraper Tower",
                description: "A tall, modern skyscraper with a sleek design. Stack it high and show off your architectural skills.",
                difficulty: .medium,
                category: .building,
                estimatedTime: "30 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .blue, quantity: 16, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .blue, quantity: 12, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .lightBlue, quantity: 8, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 4, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Start with two 4×4 plates stacked for a solid base", piecesUsed: "2× 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build alternating rows of 2×2 bricks, offsetting each layer for the interlocking pattern", piecesUsed: "16× 2×2 Brick", tip: "Offset each row by one stud"),
                    BuildStep(stepNumber: 3, instruction: "Add 1×2 bricks as window columns between floors", piecesUsed: "12× 1×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Insert tile pieces as glass windows every 3 rows", piecesUsed: "8× 1×2 Tile"),
                    BuildStep(stepNumber: 5, instruction: "Create floor separators with 2×4 plates", piecesUsed: "4× 2×4 Plate"),
                    BuildStep(stepNumber: 6, instruction: "Top with slopes for the crown of the building", piecesUsed: "4× 2×2 Slope"),
                ],
                imageSystemName: "building.2.fill"
            ),

            // ANIMALS
            LegoProject(
                name: "Friendly Dog",
                description: "An adorable blocky dog with floppy ears. Simple enough for kids, cute enough for everyone.",
                difficulty: .beginner,
                category: .animal,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 3, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .black, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the body with two 2×4 bricks stacked", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add 2×2 bricks for the legs on each end", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Stack a 2×2 brick on top for the head", piecesUsed: "1× 2×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add 1×2 bricks as floppy ears on each side", piecesUsed: "2× 1×2 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Place 1×1 black bricks as eyes", piecesUsed: "2× 1×1 Black Brick"),
                    BuildStep(stepNumber: 6, instruction: "Add a black plate for the nose", piecesUsed: "1× 1×1 Black Plate"),
                    BuildStep(stepNumber: 7, instruction: "Use a slope brick for the tail", piecesUsed: "1× 1×2 Slope"),
                ],
                imageSystemName: "pawprint.fill",
                funFact: "LEGO dogs are the most popular animal build among LEGO fans worldwide!"
            ),

            LegoProject(
                name: "Dragon",
                description: "A fearsome dragon with wings, a long tail, and a menacing stance. The crown jewel of any brick collection.",
                difficulty: .hard,
                category: .animal,
                estimatedTime: "45 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .green, quantity: 6, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 8, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .green, quantity: 6, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 8, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 6, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .green, quantity: 4, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .green, quantity: 6, flexible: true),
                    RequiredPiece(category: .wedge, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .green, quantity: 4, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: true),
                    RequiredPiece(category: .hinge, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .gray, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the body — a tapered shape using 2×4 and 2×2 bricks", piecesUsed: "6× 2×4, 4× 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Construct the neck by stacking offset 1×4 bricks upward at an angle", piecesUsed: "6× 1×4 Brick", tip: "Offset each brick by one stud for a curved look"),
                    BuildStep(stepNumber: 3, instruction: "Build the head with 2×2 bricks, add yellow eyes and red round bricks for nostrils", piecesUsed: "4× 2×2, 2× 1×1 Yellow, 2× Round Red"),
                    BuildStep(stepNumber: 4, instruction: "Create wings using plates and wedge pieces, attach with hinge pieces", piecesUsed: "6× 2×4 Plate, 4× Wedge, 4× Hinge"),
                    BuildStep(stepNumber: 5, instruction: "Build the tail tapering from 2×2 down to 1×2 bricks", piecesUsed: "8× 1×2 Brick"),
                    BuildStep(stepNumber: 6, instruction: "Add 4 legs using 2×2 bricks with slope feet", piecesUsed: "6× 2×2 Slope"),
                    BuildStep(stepNumber: 7, instruction: "Add spine details with slopes along the back", piecesUsed: "4× 2×4 Slope", tip: "The spine ridges give it a fierce look!"),
                ],
                imageSystemName: "flame.fill",
                funFact: "The largest LEGO dragon ever built used over 2 million bricks and was 5 meters long!"
            ),

            // ROBOTS
            LegoProject(
                name: "Mini Mech",
                description: "A small but mighty robot mech with articulated arms. Compact and satisfying to build.",
                difficulty: .easy,
                category: .robot,
                estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: true),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the torso with 2×4 bricks stacked 2 high", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Attach 2×2 bricks as legs", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add plates to the feet for stability", piecesUsed: "2× 2×2 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Build arms with 1×2 bricks, two per arm", piecesUsed: "4× 1×2 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Place 2×2 brick on top for the head", piecesUsed: "2× 2×2 Brick", tip: "The head should overhang slightly for a cool look"),
                    BuildStep(stepNumber: 6, instruction: "Add round bricks as eyes and slopes as antennas", piecesUsed: "2× Round 1×1, 2× 1×2 Slope"),
                ],
                imageSystemName: "cpu",
                funFact: "LEGO Mindstorms was one of the first consumer robotics kits, released in 1998!"
            ),

            // SPACESHIPS
            LegoProject(
                name: "Star Fighter",
                description: "A sleek interstellar fighter craft with swept wings and dual engines. Ready for galactic adventures.",
                difficulty: .medium,
                category: .spaceship,
                estimatedTime: "25 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 4, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: true),
                    RequiredPiece(category: .wedge, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 4, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: true),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .blue, quantity: 2, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .lightBlue, quantity: 1, flexible: true),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the central fuselage with 2×4 plates and bricks", piecesUsed: "4× 2×4 Plate, 2× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add 1×4 bricks along each side for the wing roots", piecesUsed: "4× 1×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Attach wedge pieces as the swept wings", piecesUsed: "4× 2×4 Wedge"),
                    BuildStep(stepNumber: 4, instruction: "Build the cockpit with slopes and a transparent tile", piecesUsed: "2× 2×2 Slope, 1× 1×2 Tile"),
                    BuildStep(stepNumber: 5, instruction: "Add round plates as engine nacelles", piecesUsed: "2× 2×2 Round Plate"),
                    BuildStep(stepNumber: 6, instruction: "Place red round bricks as engine exhausts", piecesUsed: "2× 1×1 Round", tip: "Use transparent red for a glow effect!"),
                ],
                imageSystemName: "airplane",
                funFact: "The LEGO Classic Space theme, launched in 1978, is one of the most beloved LEGO themes ever."
            ),

            // ART & MOSAIC
            LegoProject(
                name: "Pixel Art Heart",
                description: "A beautiful pixel art heart mosaic. Simple, colorful, and makes a great display piece or gift.",
                difficulty: .beginner,
                category: .art,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .red, quantity: 20, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .white, quantity: 16, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the base plate as your canvas", piecesUsed: "1× 4×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Following the pixel pattern, place red 1×1 plates to form the heart shape", piecesUsed: "20× Red 1×1 Plate", tip: "Start from the center and work outward"),
                    BuildStep(stepNumber: 3, instruction: "Fill the remaining spaces with white 1×1 plates", piecesUsed: "16× White 1×1 Plate"),
                ],
                imageSystemName: "heart.fill"
            ),

            // NATURE
            LegoProject(
                name: "Pine Tree",
                description: "A lovely evergreen tree to add to any LEGO scene. Uses clever stacking of plates for a natural look.",
                difficulty: .beginner,
                category: .nature,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .green, quantity: 3, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 3, heightUnits: 1), colorPreference: .green, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .green, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack the brown 2×2 bricks for the trunk", piecesUsed: "2× Brown 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add the largest green plates at the bottom, rotated 45° from each other", piecesUsed: "3× 2×4 Green Plate"),
                    BuildStep(stepNumber: 3, instruction: "Stack medium green plates, offset and rotated", piecesUsed: "2× 2×3 Green Plate"),
                    BuildStep(stepNumber: 4, instruction: "Add small plates near the top", piecesUsed: "2× 1×2 Green Plate"),
                    BuildStep(stepNumber: 5, instruction: "Top with a single 1×1 plate", piecesUsed: "1× 1×1 Green Plate"),
                ],
                imageSystemName: "leaf.fill"
            ),

            // GADGETS
            LegoProject(
                name: "Phone Stand",
                description: "A functional phone stand you can actually use! Holds your phone at the perfect viewing angle.",
                difficulty: .easy,
                category: .gadget,
                estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 8, heightUnits: 1), colorPreference: .black, quantity: 2, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .black, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place two 4×8 plates overlapping to create the wide base", piecesUsed: "2× 4×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build the back support wall, 4 bricks high at an angle using 2×4 and 2×2 bricks", piecesUsed: "4× 2×4, 4× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add 1×4 bricks as the phone lip at the front edge", piecesUsed: "2× 1×4 Brick", tip: "This catches the bottom of your phone"),
                    BuildStep(stepNumber: 4, instruction: "Add slopes on the back for the angled support", piecesUsed: "2× 2×4 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Place tiles on top for a smooth finish", piecesUsed: "2× 2×2 Tile"),
                ],
                imageSystemName: "iphone",
                funFact: "This phone stand is actually functional — try it with your phone!"
            ),

            // GAMES
            LegoProject(
                name: "Tic Tac Toe Board",
                description: "A playable tic tac toe game with a board and X/O pieces. Build it, then play it!",
                difficulty: .easy,
                category: .game,
                estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 5, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .blue, quantity: 5, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .blue, quantity: 10, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the base plate", piecesUsed: "1× 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Create the grid lines using black tiles — 2 horizontal and 2 vertical", piecesUsed: "4× 1×2 Black Tile"),
                    BuildStep(stepNumber: 3, instruction: "Build 5 X pieces from blue 1×1 bricks arranged diagonally on small plates", piecesUsed: "5× Blue 1×1 Brick, 10× 1×1 Plate"),
                    BuildStep(stepNumber: 4, instruction: "The red round bricks serve as O pieces", piecesUsed: "5× Red Round 1×1", tip: "Now challenge someone to a game!"),
                ],
                imageSystemName: "gamecontroller.fill",
                funFact: "LEGO board games were a short-lived but beloved product line from 2009-2013."
            ),

            // CHARACTERS
            LegoProject(
                name: "Brick Bot Buddy",
                description: "A cute little brick-built character with a big round head and tiny body. Pure personality in a small package.",
                difficulty: .beginner,
                category: .character,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 3, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .blue, quantity: 2, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .blue, quantity: 1, flexible: true),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 1, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .yellow, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place a 2×2 plate as the feet base", piecesUsed: "1× 2×2 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Stack 2 yellow 2×2 bricks for the body", piecesUsed: "2× Yellow 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add blue 1×2 bricks on each side as arms", piecesUsed: "2× Blue 1×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Place the last 2×2 yellow brick as the head", piecesUsed: "1× Yellow 2×2 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Add black 1×1 bricks as eyes", piecesUsed: "2× Black 1×1 Brick"),
                    BuildStep(stepNumber: 6, instruction: "Add a red round brick as the nose and 1×2 plates as eyebrows", piecesUsed: "1× Red Round 1×1, 2× 1×2 Plate"),
                ],
                imageSystemName: "person.fill",
                funFact: "The classic LEGO minifigure has the same permanent smile since 1978!"
            ),

            // FURNITURE
            LegoProject(
                name: "Mini Desk & Chair",
                description: "A tiny desk and chair set, perfect for a minifigure office or study scene.",
                difficulty: .beginner,
                category: .furniture,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 8, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 4 single 1×1 bricks as desk legs", piecesUsed: "4× 1×1 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Set the 2×4 plate on top as the desk surface", piecesUsed: "1× 2×4 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Build the chair: place 4 more 1×1 bricks as legs topped with a 2×2 plate seat", piecesUsed: "4× 1×1 Brick, 1× 2×2 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Add a 1×2 brick behind the seat as the backrest, and a 2×4 plate on top for the desktop", piecesUsed: "1× 1×2 Brick, 1× 2×4 Plate"),
                ],
                imageSystemName: "chair.fill"
            ),

            // ADDITIONAL VEHICLES, BUILDINGS, ANIMALS, ROBOTS & SPACESHIPS
            LegoProject(
                name: "Pickup Truck",
                description: "A rugged pickup truck with an open bed and chunky tires",
                difficulty: .medium,
                category: .vehicle,
                estimatedTime: "25 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .blue, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 1), colorPreference: .blue, quantity: 2, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .blue, quantity: 2, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Lay two 2×6 plates side by side to form the truck chassis", piecesUsed: "2× Blue Plate 2×6"),
                    BuildStep(stepNumber: 2, instruction: "Attach four wheels to the underside of the chassis", piecesUsed: "4× Black Wheel"),
                    BuildStep(stepNumber: 3, instruction: "Stack bricks on the front half to build the cab", piecesUsed: "2× Blue Brick 2×4"),
                    BuildStep(stepNumber: 4, instruction: "Add slopes to the front for the hood and windshield", piecesUsed: "2× Blue Slope 2×2, 2× Trans Tile 1×2"),
                    BuildStep(stepNumber: 5, instruction: "Place remaining bricks around the rear to form the truck bed walls", piecesUsed: "2× Blue Brick 2×4"),
                ],
                imageSystemName: "truck.box.fill",
                funFact: "The first LEGO vehicle set was released in 1958, just one year after the modern brick was patented!"
            ),
            LegoProject(
                name: "Sailboat",
                description: "A charming little sailboat with a tall mast and colorful sail",
                difficulty: .easy,
                category: .vehicle,
                estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 3, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .tan, quantity: 3, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the hull using brown bricks stacked two high with plates on top", piecesUsed: "2× Brown Brick 2×6, 2× Brown Plate 2×4"),
                    BuildStep(stepNumber: 2, instruction: "Stack three round bricks in the center to form the mast", piecesUsed: "3× Tan Round 1×1"),
                    BuildStep(stepNumber: 3, instruction: "Attach white slopes beside the mast to create the sail", piecesUsed: "3× White Slope 2×2"),
                ],
                imageSystemName: "sailboat.fill",
                funFact: "A full-size LEGO sailboat with over 400,000 bricks was built and actually floated on water in 2018!"
            ),
            LegoProject(
                name: "Helicopter",
                description: "A detailed helicopter with spinning rotors and a tail boom",
                difficulty: .hard,
                category: .vehicle,
                estimatedTime: "35 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 1), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .transparent, quantity: 2, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .darkGray, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Lay the two long plates as the fuselage base", piecesUsed: "2× Red Plate 2×8"),
                    BuildStep(stepNumber: 2, instruction: "Stack red bricks on the front half to form the cockpit body", piecesUsed: "4× Red Brick 2×4"),
                    BuildStep(stepNumber: 3, instruction: "Add slopes at the front for the nose and transparent tiles for the windshield", piecesUsed: "2× Red Slope 2×2, 2× Trans Tile 1×4"),
                    BuildStep(stepNumber: 4, instruction: "Attach technic beams crossing on top of a round plate to create the main rotor", piecesUsed: "2× Gray Technic 1×8, 1× Dark Gray Round 2×2"),
                ],
                imageSystemName: "helicopter.fill",
                funFact: "The longest LEGO helicopter ever built measured over 7 feet and used more than 25,000 pieces!"
            ),
            LegoProject(
                name: "Bicycle",
                description: "A simple miniature bicycle with two wheels and handlebars",
                difficulty: .beginner,
                category: .vehicle,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .red, quantity: 1, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Use the technic beam as the bicycle frame", piecesUsed: "1× Red Technic 1×6"),
                    BuildStep(stepNumber: 2, instruction: "Attach a wheel to each end of the frame", piecesUsed: "2× Black Wheel"),
                    BuildStep(stepNumber: 3, instruction: "Place round plates on top near the front as handlebars", piecesUsed: "2× Gray Round 1×1"),
                ],
                imageSystemName: "bicycle",
                funFact: "There are more bicycles in the world than cars — over 1 billion!"
            ),
            LegoProject(
                name: "Lighthouse",
                description: "A tall striped lighthouse perched on a rocky base with a glowing top",
                difficulty: .hard,
                category: .building,
                estimatedTime: "40 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 6, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 6, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .darkGray, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place gray plates as the rocky base and add slopes around the edges", piecesUsed: "2× Gray Plate 4×4, 4× Dark Gray Slope 2×2"),
                    BuildStep(stepNumber: 2, instruction: "Alternate stacking white and red 2×2 bricks to build the tower", piecesUsed: "6× White Brick 2×2, 6× Red Brick 2×2"),
                    BuildStep(stepNumber: 3, instruction: "Place the yellow round brick on top as the lantern room light", piecesUsed: "1× Yellow Round 2×2"),
                ],
                imageSystemName: "light.beacon.max",
                funFact: "The oldest working lighthouse in the world, Tower of Hercules in Spain, has been guiding ships for nearly 2,000 years!"
            ),
            LegoProject(
                name: "Castle Tower",
                description: "An imposing medieval castle tower with battlements, arrow slits, and a flag on top",
                difficulty: .expert,
                category: .building,
                estimatedTime: "50 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 12, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 8, flexible: false),
                    RequiredPiece(category: .arch, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .darkGray, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 6, heightUnits: 1), colorPreference: .darkGray, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .red, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Lay two large plates as the tower foundation", piecesUsed: "2× Dark Gray Plate 6×6"),
                    BuildStep(stepNumber: 2, instruction: "Build four walls using 2×4 gray bricks, leaving gaps for arrow slits", piecesUsed: "12× Gray Brick 2×4"),
                    BuildStep(stepNumber: 3, instruction: "Place arches across the front wall to form the entrance gate", piecesUsed: "2× Dark Gray Arch 1×4"),
                    BuildStep(stepNumber: 4, instruction: "Add 1×2 bricks in alternating positions along the top to create battlements", piecesUsed: "8× Gray Brick 1×2"),
                    BuildStep(stepNumber: 5, instruction: "Attach a red tile on top of a 1×2 brick as a flag", piecesUsed: "1× Red Tile 1×2"),
                ],
                imageSystemName: "building.columns.fill",
                funFact: "The original LEGO Castle line launched in 1978 and remains one of the most beloved themes ever!"
            ),
            LegoProject(
                name: "Windmill",
                description: "A classic Dutch-style windmill with spinning blades and a brick base",
                difficulty: .medium,
                category: .building,
                estimatedTime: "30 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .tan, quantity: 6, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .white, quantity: 4, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .darkGray, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack tan bricks into a tapered tower shape, wider at the base", piecesUsed: "6× Tan Brick 2×4"),
                    BuildStep(stepNumber: 2, instruction: "Add brown slopes around the top to form the cap roof", piecesUsed: "4× Brown Slope 2×2"),
                    BuildStep(stepNumber: 3, instruction: "Attach the round brick to the front as the hub", piecesUsed: "1× Dark Gray Round 2×2"),
                    BuildStep(stepNumber: 4, instruction: "Connect four technic beams to the hub in an X pattern as windmill blades", piecesUsed: "4× White Technic 1×8"),
                ],
                imageSystemName: "wind",
                funFact: "The Netherlands once had over 10,000 windmills — today about 1,000 still stand!"
            ),
            LegoProject(
                name: "Treehouse",
                description: "A cozy elevated treehouse nestled in a brick-built tree with a ladder",
                difficulty: .hard,
                category: .building,
                estimatedTime: "40 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 8, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 6, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .tan, quantity: 4, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .yellow, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack brown 2×2 bricks into a tall trunk, about 8 bricks high", piecesUsed: "8× Brown Brick 2×2"),
                    BuildStep(stepNumber: 2, instruction: "Place brown plates on top of the trunk as the treehouse floor", piecesUsed: "2× Brown Plate 4×4"),
                    BuildStep(stepNumber: 3, instruction: "Build short tan brick walls on three sides and add yellow tiles as windows", piecesUsed: "4× Tan Brick 1×4, 2× Yellow Tile 1×1"),
                    BuildStep(stepNumber: 4, instruction: "Arrange green slopes all around the top and sides as leafy canopy", piecesUsed: "6× Green Slope 2×2"),
                ],
                imageSystemName: "tree.fill",
                funFact: "The LEGO Ideas Treehouse set (#21318) uses botanical elements made from plant-based plastic sourced from sugarcane!"
            ),
            LegoProject(
                name: "Bridge",
                description: "A sturdy arch bridge spanning a gap with road plates on top",
                difficulty: .medium,
                category: .building,
                estimatedTime: "25 min",
                requiredPieces: [
                    RequiredPiece(category: .arch, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .gray, quantity: 3, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 1), colorPreference: .darkGray, quantity: 3, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .white, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build two pillars from 2×2 gray bricks, two bricks tall each", piecesUsed: "4× Gray Brick 2×2"),
                    BuildStep(stepNumber: 2, instruction: "Place the three arches between the pillars to form the bridge span", piecesUsed: "3× Gray Arch 1×6"),
                    BuildStep(stepNumber: 3, instruction: "Lay dark gray plates across the top of the arches as the road surface", piecesUsed: "3× Dark Gray Plate 2×8"),
                    BuildStep(stepNumber: 4, instruction: "Add white tiles along each edge as road markings and guard rails", piecesUsed: "2× White Tile 1×4"),
                ],
                imageSystemName: "road.lanes",
                funFact: "The longest LEGO bridge ever built stretched over 104 feet at a 2019 event in Prague!"
            ),
            LegoProject(
                name: "Penguin",
                description: "An adorable tuxedo penguin with a bright orange beak",
                difficulty: .beginner,
                category: .animal,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 3, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .orange, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack two white bricks as the penguin's belly", piecesUsed: "2× White Brick 2×2"),
                    BuildStep(stepNumber: 2, instruction: "Place black bricks on the sides and back to form the body and wings", piecesUsed: "3× Black Brick 2×2"),
                    BuildStep(stepNumber: 3, instruction: "Attach the orange slope at the front as the beak", piecesUsed: "1× Orange Slope 1×2"),
                ],
                imageSystemName: "bird.fill",
                funFact: "Emperor penguins can dive to depths of over 1,800 feet — deeper than any other bird!"
            ),
            LegoProject(
                name: "Giraffe",
                description: "A tall giraffe with a long spotted neck and four sturdy legs",
                difficulty: .medium,
                category: .animal,
                estimatedTime: "25 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 6, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .orange, quantity: 4, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Use two 2×4 yellow bricks to build the giraffe's body", piecesUsed: "2× Yellow Brick 2×4"),
                    BuildStep(stepNumber: 2, instruction: "Attach four orange 1×2 bricks underneath as the four legs", piecesUsed: "4× Orange Brick 1×2"),
                    BuildStep(stepNumber: 3, instruction: "Stack six 2×2 yellow bricks vertically at the front to create the long neck", piecesUsed: "6× Yellow Brick 2×2"),
                    BuildStep(stepNumber: 4, instruction: "Place two brown round bricks on top as little ossicone horns", piecesUsed: "2× Brown Round 1×1"),
                ],
                imageSystemName: "figure.walk",
                funFact: "A giraffe's legs alone are taller than most adult humans — about 6 feet long!"
            ),
            LegoProject(
                name: "Butterfly",
                description: "A colorful butterfly with symmetrical patterned wings spread wide",
                difficulty: .easy,
                category: .animal,
                estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .purple, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .pink, quantity: 2, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .black, quantity: 1, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .yellow, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the black brick vertically as the butterfly's body", piecesUsed: "1× Black Brick 1×4"),
                    BuildStep(stepNumber: 2, instruction: "Attach purple plates on each side as the upper wings", piecesUsed: "2× Purple Plate 2×4"),
                    BuildStep(stepNumber: 3, instruction: "Add pink plates below the purple ones as the lower wings", piecesUsed: "2× Pink Plate 2×2"),
                    BuildStep(stepNumber: 4, instruction: "Place yellow round plates on the wings for decorative spots", piecesUsed: "4× Yellow Round 1×1"),
                ],
                imageSystemName: "ladybug.fill",
                funFact: "Butterflies taste with their feet and can detect food just by landing on it!"
            ),
            LegoProject(
                name: "Shark",
                description: "A sleek gray shark with a pointed nose and menacing open jaw",
                difficulty: .medium,
                category: .animal,
                estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 3, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Lay white plates as the shark's underside belly", piecesUsed: "2× White Plate 2×4"),
                    BuildStep(stepNumber: 2, instruction: "Stack gray bricks on top to build the main body", piecesUsed: "3× Gray Brick 2×4"),
                    BuildStep(stepNumber: 3, instruction: "Attach gray slopes at the front to form the pointed snout", piecesUsed: "2× Gray Slope 2×2"),
                    BuildStep(stepNumber: 4, instruction: "Place gray tiles angled on top and sides as the dorsal and pectoral fins", piecesUsed: "2× Gray Tile 1×2"),
                ],
                imageSystemName: "fish.fill",
                funFact: "Sharks have been around for over 400 million years — they predate dinosaurs and even trees!"
            ),
            LegoProject(
                name: "Battle Mech",
                description: "A towering humanoid battle mech armed with cannons and heavy armor plating",
                difficulty: .expert,
                category: .robot,
                estimatedTime: "55 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .darkGray, quantity: 6, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: true),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 1), colorPreference: .darkGray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .darkGray, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the torso using 2×4 dark gray bricks with plates as shoulder mounts", piecesUsed: "3× Dark Gray Brick 2×4, 2× Dark Gray Plate 2×6"),
                    BuildStep(stepNumber: 2, instruction: "Attach technic beams as the two arms and two legs, angled outward", piecesUsed: "4× Black Technic 1×6"),
                    BuildStep(stepNumber: 3, instruction: "Stack 2×2 bricks at the bottom of each leg for armored feet", piecesUsed: "4× Dark Gray Brick 2×2"),
                    BuildStep(stepNumber: 4, instruction: "Add red slopes on the shoulders as armor plating and yellow rounds as cannon barrels", piecesUsed: "2× Red Slope 2×2, 2× Yellow Round 1×1"),
                    BuildStep(stepNumber: 5, instruction: "Place the remaining bricks on top as the cockpit head module", piecesUsed: "3× Dark Gray Brick 2×4"),
                ],
                imageSystemName: "figure.martial.arts",
                funFact: "The Japanese tradition of giant mech robots (mecha) started with the manga Mazinger Z in 1972!"
            ),
            LegoProject(
                name: "Helper Bot",
                description: "A friendly little helper robot with big eyes and articulated arms",
                difficulty: .easy,
                category: .robot,
                estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .lightBlue, quantity: 3, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .lightBlue, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the gray plate as the base and stack two light blue bricks as the body", piecesUsed: "1× Gray Plate 2×4, 2× Light Blue Brick 2×2"),
                    BuildStep(stepNumber: 2, instruction: "Add the third brick on top as the head and attach white rounds as eyes", piecesUsed: "1× Light Blue Brick 2×2, 2× White Round 1×1"),
                    BuildStep(stepNumber: 3, instruction: "Attach 1×2 bricks on each side as the robot's arms", piecesUsed: "2× Light Blue Brick 1×2"),
                ],
                imageSystemName: "gearshape.2.fill",
                funFact: "The word 'robot' comes from the Czech word 'robota', meaning forced labor, coined in a 1920 play!"
            ),
            LegoProject(
                name: "Drone",
                description: "A quadcopter drone with four rotors and a camera gimbal underneath",
                difficulty: .medium,
                category: .robot,
                estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .transparent, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Start with the white plate as the central body frame", piecesUsed: "1× White Plate 4×4"),
                    BuildStep(stepNumber: 2, instruction: "Attach four technic beams radiating outward from each corner as arms", piecesUsed: "4× Gray Technic 1×4"),
                    BuildStep(stepNumber: 3, instruction: "Place a round plate at the end of each arm as the rotor housings", piecesUsed: "4× Black Round 2×2"),
                    BuildStep(stepNumber: 4, instruction: "Add the transparent tile underneath the center as the camera lens", piecesUsed: "1× Trans Tile 1×1"),
                ],
                imageSystemName: "drone.fill",
                funFact: "The first consumer drone with a camera, the Parrot AR.Drone, was announced at CES in 2010!"
            ),
            LegoProject(
                name: "Rocket Ship",
                description: "A classic pointed rocket with fins, a porthole, and flame exhaust at the base",
                difficulty: .hard,
                category: .spaceship,
                estimatedTime: "35 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 6, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .transparent, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .darkGray, quantity: 1, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .orange, quantity: 3, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the dark gray plate as the base and add orange rounds underneath as exhaust flames", piecesUsed: "1× Dark Gray Plate 2×4, 3× Orange Round 1×1"),
                    BuildStep(stepNumber: 2, instruction: "Stack white bricks six high to form the rocket fuselage", piecesUsed: "6× White Brick 2×2"),
                    BuildStep(stepNumber: 3, instruction: "Attach the transparent round plate on one side as the porthole window", piecesUsed: "1× Trans Round 1×1"),
                    BuildStep(stepNumber: 4, instruction: "Place four red slopes at the top to form the pointed nose cone", piecesUsed: "4× Red Slope 2×2"),
                ],
                imageSystemName: "airplane.departure",
                funFact: "The Saturn V rocket used to reach the Moon stood 363 feet tall — about the height of a 36-story building!"
            ),
            LegoProject(
                name: "Flying Saucer",
                description: "A retro flying saucer with a domed cockpit and circular ring of lights",
                difficulty: .medium,
                category: .spaceship,
                estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .transparent, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .lime, quantity: 6, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .darkGray, quantity: 3, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack the two large round plates together as the saucer disc", piecesUsed: "2× Gray Round 4×4"),
                    BuildStep(stepNumber: 2, instruction: "Place small dark gray plates on top as the cockpit base structure", piecesUsed: "3× Dark Gray Plate 2×2"),
                    BuildStep(stepNumber: 3, instruction: "Add the transparent dome on top as the cockpit canopy", piecesUsed: "1× Trans Round 2×2"),
                    BuildStep(stepNumber: 4, instruction: "Attach lime tiles around the rim of the saucer as glowing lights", piecesUsed: "6× Lime Tile 1×1"),
                ],
                imageSystemName: "ufo.fill",
                funFact: "The term 'flying saucer' was coined by a journalist in 1947 who misquoted pilot Kenneth Arnold's description!"
            ),
            LegoProject(
                name: "Space Station",
                description: "A modular orbital space station with solar panels, docking ports, and a central habitat module",
                difficulty: .expert,
                category: .spaceship,
                estimatedTime: "60 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 3), colorPreference: .white, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 1), colorPreference: .darkBlue, quantity: 4, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 4, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Connect four white 2×6 bricks end-to-end to form the central habitat cylinder", piecesUsed: "4× White Brick 2×6"),
                    BuildStep(stepNumber: 2, instruction: "Attach two technic beams through the center, extending outward as the truss structure", piecesUsed: "2× Gray Technic 1×8"),
                    BuildStep(stepNumber: 3, instruction: "Mount dark blue plates at each end of the truss beams as solar panel arrays", piecesUsed: "4× Dark Blue Plate 2×8"),
                    BuildStep(stepNumber: 4, instruction: "Add white round bricks at each end of the habitat as docking port modules", piecesUsed: "2× White Round 2×2"),
                    BuildStep(stepNumber: 5, instruction: "Place transparent tiles along the habitat module as observation windows and add the center plate as a radiator", piecesUsed: "4× Trans Tile 1×2, 1× White Plate 4×4"),
                ],
                imageSystemName: "network",
                funFact: "The International Space Station is the most expensive object ever built, costing over $150 billion!"
            ),

            // ART & MOSAIC
            LegoProject(
                name: "Mosaic Flower",
                description: "A colorful flat mosaic flower built entirely from plates and tiles. Great for wall art.",
                difficulty: .easy,
                category: .art,
                estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .red, quantity: 6, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .yellow, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .green, quantity: 3, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .white, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Arrange yellow plates in a 2×2 cluster for the flower center", piecesUsed: "4× Yellow 1×1 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Surround the center with red plates as petals", piecesUsed: "6× Red 1×1 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Attach green 1×2 plates downward for the stem", piecesUsed: "3× Green 1×2 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Place white tiles around the edges to frame the mosaic", piecesUsed: "4× White 1×1 Tile"),
                ],
                imageSystemName: "paintbrush.fill",
                funFact: "LEGO mosaics became so popular that LEGO released an entire Art theme in 2020!"
            ),

            LegoProject(
                name: "Abstract Tower",
                description: "A tall, twisting tower that mixes slopes, arches, and bricks in contrasting colors. A challenging artistic build.",
                difficulty: .hard,
                category: .art,
                estimatedTime: "35 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 6, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 4, flexible: false),
                    RequiredPiece(category: .arch, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .darkGray, quantity: 1, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .yellow, quantity: 3, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the 4×4 dark gray plate as a stable base", piecesUsed: "1× Dark Gray 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Stack black 2×2 bricks, rotating each 45° conceptually for a spiral effect", piecesUsed: "6× Black 2×2 Brick", tip: "Offset each layer by half a stud"),
                    BuildStep(stepNumber: 3, instruction: "Insert red arches on opposite sides halfway up the tower", piecesUsed: "2× Red 1×4 Arch"),
                    BuildStep(stepNumber: 4, instruction: "Add white slopes at the top angled outward for a crown effect", piecesUsed: "4× White 2×2 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Cap with yellow round bricks as decorative finials", piecesUsed: "3× Yellow Round 1×1"),
                ],
                imageSystemName: "cube.fill",
                funFact: "Professional LEGO artists can earn over $100,000 a year building large-scale sculptures!"
            ),

            // NATURE
            LegoProject(
                name: "Bonsai Tree",
                description: "A miniature bonsai tree with a brown trunk and green leafy canopy on a tan base plate.",
                difficulty: .medium,
                category: .nature,
                estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 5, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .green, quantity: 4, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .darkGreen, quantity: 6, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .tan, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the tan 4×4 plate as the pot base", piecesUsed: "1× Tan 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Stack brown 1×2 bricks in a zigzag to form the trunk", piecesUsed: "5× Brown 1×2 Brick", tip: "Offset each brick slightly for a natural look"),
                    BuildStep(stepNumber: 3, instruction: "Attach green 2×2 plates around the top as the canopy base", piecesUsed: "4× Green 2×2 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Add dark green round bricks on top for leafy clusters", piecesUsed: "6× Dark Green Round 1×1"),
                ],
                imageSystemName: "leaf.fill",
                funFact: "LEGO released a real Bonsai Tree set (#10281) in 2021 with swappable cherry blossoms!"
            ),

            LegoProject(
                name: "Cactus",
                description: "A cute little cactus in a pot. Just a few green pieces and you're done!",
                difficulty: .beginner,
                category: .nature,
                estimatedTime: "8 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 3, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 2, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 1, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .yellow, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the brown round brick as the pot", piecesUsed: "1× Brown Round 2×2"),
                    BuildStep(stepNumber: 2, instruction: "Stack three green 2×2 bricks on top for the main trunk", piecesUsed: "3× Green 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Attach 1×2 green bricks on each side as arms", piecesUsed: "2× Green 1×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add tiny yellow plates as flowers on top", piecesUsed: "2× Yellow 1×1 Plate"),
                ],
                imageSystemName: "laurel.leading",
                funFact: "The saguaro cactus can live over 200 years — your LEGO one will last even longer!"
            ),

            LegoProject(
                name: "Mushroom",
                description: "A whimsical toadstool with a red spotted cap and white stem.",
                difficulty: .easy,
                category: .nature,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .white, quantity: 3, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the green 2×4 plate as the grassy base", piecesUsed: "1× Green 2×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Stack two white 2×2 bricks for the stem", piecesUsed: "2× White 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Arrange four red slopes pointing outward to form the cap", piecesUsed: "4× Red 2×2 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Place white round 1×1 pieces on the cap as spots", piecesUsed: "3× White Round 1×1"),
                ],
                imageSystemName: "aqi.medium",
                funFact: "The fly agaric mushroom's red and white pattern inspired the mushrooms in Super Mario Bros!"
            ),

            // GADGETS
            LegoProject(
                name: "Spinning Top",
                description: "A functional spinning top that actually spins! Uses a Technic axle through layered plates.",
                difficulty: .easy,
                category: .gadget,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .blue, quantity: 2, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .yellow, quantity: 1, flexible: true),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the 4×4 plate as the top's body", piecesUsed: "1× Yellow 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Stack 2×2 plates on center for weight", piecesUsed: "2× Blue 2×2 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Add slopes around the edges angled downward", piecesUsed: "4× Red 2×2 Slope", tip: "Point them down for the spinning shape"),
                    BuildStep(stepNumber: 4, instruction: "Push the Technic pin through the center hole as the axle", piecesUsed: "1× Gray Technic Pin"),
                ],
                imageSystemName: "tornado",
                funFact: "LEGO spinning tops can reach over 3,000 RPM when launched with a Technic string launcher!"
            ),

            LegoProject(
                name: "Catapult",
                description: "A working mini catapult that can launch small bricks across the table using a Technic lever arm.",
                difficulty: .hard,
                category: .gadget,
                estimatedTime: "30 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .darkGray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .black, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .red, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the 4×6 dark gray plate as the base", piecesUsed: "1× Dark Gray 4×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build two brown 2×4 brick pillars on each side for the fulcrum", piecesUsed: "2× Brown 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Rest the Technic beam across the pillars as the lever arm", piecesUsed: "1× Black Technic 1×8"),
                    BuildStep(stepNumber: 4, instruction: "Add gray bricks as a stopper on one end", piecesUsed: "4× Gray 1×2 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Attach a 2×2 plate bucket on the launch end to hold ammo", piecesUsed: "1× Red 2×2 Plate"),
                ],
                imageSystemName: "scope",
                funFact: "Medieval trebuchets could hurl 300-pound stones over 900 feet!"
            ),

            LegoProject(
                name: "Dice",
                description: "A buildable die with dots on all six faces. Roll it for board game night!",
                difficulty: .easy,
                category: .game,
                estimatedTime: "12 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 4, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .black, quantity: 8, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place a 2×2 plate, then stack two 2×2 white bricks on it", piecesUsed: "1× White 2×2 Plate, 2× White 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add another 2×2 plate, then two more bricks to complete the cube", piecesUsed: "1× White 2×2 Plate, 2× White 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Cap the top with a 2×2 tile for a smooth face", piecesUsed: "1× White 2×2 Tile"),
                    BuildStep(stepNumber: 4, instruction: "Place black round dots on the visible faces to represent numbers 1–6", piecesUsed: "8× Black Round 1×1", tip: "Use 1 on top, 6 on bottom, etc."),
                ],
                imageSystemName: "dice.fill",
                funFact: "The opposite sides of a standard die always add up to 7!"
            ),

            LegoProject(
                name: "Tic-Tac-Toe Deluxe",
                description: "A playable tic-tac-toe set with a grid and colored markers for X and O.",
                difficulty: .medium,
                category: .game,
                estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 6, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .red, quantity: 5, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .blue, quantity: 5, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the 6×6 gray plate as the board", piecesUsed: "1× Gray 6×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Lay two black 1×4 tiles vertically to divide into 3 columns", piecesUsed: "2× Black 1×4 Tile"),
                    BuildStep(stepNumber: 3, instruction: "Lay two more black 1×4 tiles horizontally to create the grid", piecesUsed: "2× Black 1×4 Tile"),
                    BuildStep(stepNumber: 4, instruction: "Use red round pieces for O and blue plates for X markers", piecesUsed: "5× Red Round 1×1, 5× Blue 1×1 Plate", tip: "Stack blue plates in an X shape for each marker"),
                ],
                imageSystemName: "number",
                funFact: "Tic-tac-toe has 255,168 possible games but only 138 unique ending positions!"
            ),

            // CHARACTERS
            LegoProject(
                name: "Knight",
                description: "A brave brick-built knight with a shield and sword, ready for castle defense.",
                difficulty: .medium,
                category: .character,
                estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 3, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .darkGray, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .blue, quantity: 2, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .black, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack two gray 2×2 bricks for the body armor", piecesUsed: "2× Gray 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add a third 2×2 brick on top as the head, with black round eyes", piecesUsed: "1× Gray 2×2 Brick, 2× Black Round 1×1"),
                    BuildStep(stepNumber: 3, instruction: "Place dark gray slopes on top as the helmet visor", piecesUsed: "2× Dark Gray 2×2 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Attach 1×4 plates on each side — one as a sword, one as a shield arm", piecesUsed: "2× Gray 1×4 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Add blue tiles on the chest as a coat of arms", piecesUsed: "2× Blue 1×2 Tile"),
                ],
                imageSystemName: "shield.lefthalf.filled",
                funFact: "The first LEGO Castle set was released in 1978 and is one of the longest-running themes!"
            ),

            LegoProject(
                name: "Wizard",
                description: "A mystical wizard with a pointy hat and a magic staff. Easy but enchanting.",
                difficulty: .easy,
                category: .character,
                estimatedTime: "12 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .purple, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .purple, quantity: 1, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack two purple 2×2 bricks for the robed body", piecesUsed: "2× Purple 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Place the purple slope on top as the pointy wizard hat", piecesUsed: "1× Purple 2×2 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Add yellow round pieces as glowing eyes", piecesUsed: "2× Yellow Round 1×1"),
                    BuildStep(stepNumber: 4, instruction: "Attach the brown 1×4 plate to the side as a magic staff", piecesUsed: "1× Brown 1×4 Plate"),
                ],
                imageSystemName: "wand.and.stars",
                funFact: "LEGO minifigure wizards have appeared in over 30 different sets since 1993!"
            ),

            LegoProject(
                name: "Pirate",
                description: "A swashbuckling pirate with an eye patch and a cutlass. Arrr!",
                difficulty: .medium,
                category: .character,
                estimatedTime: "18 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .tan, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .black, quantity: 3, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack two red 2×2 bricks for the pirate's coat", piecesUsed: "2× Red 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Place the tan 2×2 brick on top as the head", piecesUsed: "1× Tan 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add a black tile on one eye as the eye patch, white round on the other", piecesUsed: "1× Black 1×1 Tile, 1× White Round 1×1"),
                    BuildStep(stepNumber: 4, instruction: "Place two black tiles on top as the hat", piecesUsed: "2× Black 1×1 Tile"),
                    BuildStep(stepNumber: 5, instruction: "Attach the gray 1×4 plate to one side as the cutlass", piecesUsed: "1× Gray 1×4 Plate"),
                ],
                imageSystemName: "flag.fill",
                funFact: "LEGO Pirates was launched in 1989 and featured the first minifigure with a hook hand!"
            ),

            // FURNITURE
            LegoProject(
                name: "Desk",
                description: "A sturdy miniature desk with drawer detail and a smooth top surface.",
                difficulty: .medium,
                category: .furniture,
                estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 1, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .tan, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place four 1×1 bricks as table legs in a rectangle", piecesUsed: "4× Brown 1×1 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Set the 4×6 plate on top as the desk surface", piecesUsed: "1× Brown 4×6 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Add a 2×4 brick underneath as the drawer block", piecesUsed: "1× Brown 2×4 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Place tan tiles on the drawer front as drawer handles", piecesUsed: "2× Tan 1×2 Tile"),
                ],
                imageSystemName: "desktopcomputer",
                funFact: "The most expensive desk ever sold was a Badminton Cabinet — it went for $36 million!"
            ),

            LegoProject(
                name: "Bookshelf",
                description: "A miniature bookshelf with colorful book spines. Perfect for a mini room scene.",
                difficulty: .easy,
                category: .furniture,
                estimatedTime: "12 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 3, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 3, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .red, quantity: 2, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .blue, quantity: 2, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .green, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place a 1×4 brown plate as the bottom shelf", piecesUsed: "1× Brown 1×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add 1×4 brown bricks on each side and one in the middle as dividers", piecesUsed: "3× Brown 1×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Place 1×4 plates on top of the bricks for upper shelves", piecesUsed: "2× Brown 1×4 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Stand colored tiles upright on the shelves as books", piecesUsed: "2× Red, 2× Blue, 2× Green 1×1 Tile"),
                ],
                imageSystemName: "books.vertical.fill",
                funFact: "The Library of Congress holds over 170 million items — you'd need a LOT of LEGO bookshelves!"
            ),

            LegoProject(
                name: "Chair",
                description: "A simple single chair. The most basic piece of LEGO furniture.",
                difficulty: .beginner,
                category: .furniture,
                estimatedTime: "5 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place four 1×1 bricks in a square as chair legs", piecesUsed: "4× Brown 1×1 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Set the 2×2 plate on top as the seat", piecesUsed: "1× Brown 2×2 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Add the 1×2 brick at the back of the seat as the backrest", piecesUsed: "1× Brown 1×2 Brick"),
                ],
                imageSystemName: "chair.fill",
                funFact: "The world's most expensive chair is the Dragons Chair, sold for $28 million at auction!"
            ),

            // DECORATIONS
            LegoProject(
                name: "Snowflake Ornament",
                description: "A delicate snowflake built from white plates and tiles. Hang it anywhere for winter vibes.",
                difficulty: .easy,
                category: .decoration,
                estimatedTime: "12 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .white, quantity: 3, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .white, quantity: 6, flexible: false),
                    RequiredPiece(category: .round, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .lightBlue, quantity: 6, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .transparent, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Cross three 1×4 plates at their centers to form a six-armed star", piecesUsed: "3× White 1×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Attach 1×2 plates at the end of each arm as branches", piecesUsed: "6× White 1×2 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Place light blue round pieces at each branch tip", piecesUsed: "6× Light Blue Round 1×1"),
                    BuildStep(stepNumber: 4, instruction: "Add a transparent tile at the center for sparkle", piecesUsed: "1× Transparent 1×1 Tile"),
                ],
                imageSystemName: "snowflake",
                funFact: "No two real snowflakes are identical — but LEGO lets you build the same one every time!"
            ),

            LegoProject(
                name: "Picture Frame",
                description: "A brick-built picture frame sized for a tiny photo or drawing. Simple and sweet.",
                difficulty: .beginner,
                category: .decoration,
                estimatedTime: "8 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 1), colorPreference: .orange, quantity: 2, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .orange, quantity: 2, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Lay down the white 4×4 tile as the picture area", piecesUsed: "1× White 4×4 Tile"),
                    BuildStep(stepNumber: 2, instruction: "Place 1×6 plates along the top and bottom edges", piecesUsed: "2× Orange 1×6 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Place 1×4 plates along the left and right sides to complete the frame", piecesUsed: "2× Orange 1×4 Plate"),
                ],
                imageSystemName: "photo.fill",
                funFact: "The first picture frame patent was filed in 1898, but people have been framing art since ancient Egypt!"
            ),

            LegoProject(
                name: "Trophy",
                description: "A golden trophy cup on a dark base. Award it to the best builder in the house!",
                difficulty: .medium,
                category: .decoration,
                estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .darkGray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .darkGray, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .yellow, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the dark gray 2×4 plate as the base pedestal", piecesUsed: "1× Dark Gray 2×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add the dark gray 1×2 brick centered on top as the stem", piecesUsed: "1× Dark Gray 1×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Stack two yellow 2×2 bricks on the stem for the cup body", piecesUsed: "2× Yellow 2×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add inverted yellow slopes on each side as the cup handles", piecesUsed: "2× Yellow 2×2 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Place yellow 1×2 plates on top as the cup rim", piecesUsed: "2× Yellow 1×2 Plate"),
                ],
                imageSystemName: "trophy.fill",
                funFact: "The FIFA World Cup trophy is made of 18-karat gold and weighs 13.6 pounds!"
            ),
        ]

        // Load extended project libraries
        allProjects.append(contentsOf: loadExtendedProjects())
        allProjects.append(contentsOf: loadExtendedProjects2())
        allProjects.append(contentsOf: loadExtendedProjects3())
    }
}
