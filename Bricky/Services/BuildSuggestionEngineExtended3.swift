import Foundation

// MARK: - Extended Build Projects Part 3 (~60 projects)
// Final batch: fill remaining difficulty/category gaps to reach 200+

extension BuildSuggestionEngine {

    func loadExtendedProjects3() -> [LegoProject] {
        [
            // Fill beginner gaps
            LegoProject(name: "Mini Duck", description: "A tiny yellow duck — the simplest animal build.",
                difficulty: .beginner, category: .animal, estimatedTime: "5 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .orange, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack two yellow 2×2 bricks for body and head", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add orange slope as beak", piecesUsed: "1× 1×2 Slope"),
                ],
                imageSystemName: "bird.fill", funFact: "The LEGO duck was one of the first builds suggested in early LEGO sets."
            ),

            LegoProject(name: "Pixel Heart", description: "A flat pixel-art heart made from red plates.",
                difficulty: .beginner, category: .art, estimatedTime: "8 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 6, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .red, quantity: 16, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place white 6×6 plate as canvas", piecesUsed: "1× 6×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Arrange red tiles in heart shape pixel pattern", piecesUsed: "16× 1×1 Red Tile"),
                ],
                imageSystemName: "heart.fill", funFact: "The heart shape symbol dates back to the 13th century."
            ),

            LegoProject(name: "Snowman", description: "A three-ball snowman with hat and scarf.",
                difficulty: .beginner, category: .decoration, estimatedTime: "8 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .black, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .orange, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place large white 4×4 brick as base", piecesUsed: "1× 4×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Stack two 2×2 bricks as middle and head", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add black plate hat and orange brick nose", piecesUsed: "1× 2×2 Plate, 1× 1×1 Brick"),
                ],
                imageSystemName: "snowflake", funFact: "The tallest snowman ever built was 122 feet and named Olympia."
            ),

            LegoProject(name: "Simple Car", description: "A four-piece car for absolute beginners.",
                difficulty: .beginner, category: .vehicle, estimatedTime: "5 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .blue, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .blue, quantity: 1, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 2×4 plate as chassis", piecesUsed: "1× 2×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add 2×2 brick as cab", piecesUsed: "1× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Attach four wheels", piecesUsed: "4× Wheel"),
                ],
                imageSystemName: "car.fill", funFact: "LEGO has produced more wheels than any other manufacturer in the world."
            ),

            LegoProject(name: "Mini House", description: "The simplest house build — walls and a roof.",
                difficulty: .beginner, category: .building, estimatedTime: "8 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 4×4 plate", piecesUsed: "1× 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add two 2×4 bricks as walls", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Top with two slopes for roof", piecesUsed: "2× 2×4 Slope"),
                ],
                imageSystemName: "house.fill", funFact: "The first LEGO house was built with wooden bricks in Ole Kirk Christiansen's workshop."
            ),

            // Fill easy gaps
            LegoProject(name: "Frog", description: "A little green frog sitting on a lily pad.",
                difficulty: .easy, category: .animal, estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .green, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place green 4×4 plate as lily pad", piecesUsed: "1× 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add 2×2 brick as body", piecesUsed: "1× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add yellow eyes", piecesUsed: "2× 1×1 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add four legs from 1×2 plates", piecesUsed: "4× 1×2 Plate"),
                ],
                imageSystemName: "tortoise.fill", funFact: "Some frogs can freeze solid in winter and thaw back to life in spring."
            ),

            LegoProject(name: "Dinghy", description: "A small dinghy with mast and triangular sail.",
                difficulty: .easy, category: .vehicle, estimatedTime: "12 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 1), colorPreference: .blue, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 2×6 plate as hull", piecesUsed: "1× 2×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Stack brown 1×1 bricks as mast", piecesUsed: "4× 1×1 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Lean white slope against mast as sail", piecesUsed: "1× 2×4 Slope"),
                ],
                imageSystemName: "sailboat.fill", funFact: "Sailing is one of the oldest forms of transportation, dating back 5,000 years."
            ),

            LegoProject(name: "Rocket Car", description: "A land-speed record car with a rocket booster.",
                difficulty: .easy, category: .vehicle, estimatedTime: "12 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 1), colorPreference: .red, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 2×6 plate as chassis", piecesUsed: "1× 2×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add slope as nose cone", piecesUsed: "1× 2×4 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Add gray brick as rocket engine", piecesUsed: "1× 2×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Mount wheels", piecesUsed: "4× Wheel"),
                ],
                imageSystemName: "car.fill", funFact: "The land speed record is 763 mph, set by ThrustSSC in 1997."
            ),

            LegoProject(name: "Garden Bench", description: "A simple park bench with armrests.",
                difficulty: .easy, category: .furniture, estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place four 1×1 bricks as legs", piecesUsed: "4× 1×1 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add 2×6 plate as seat", piecesUsed: "1× 2×6 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Add 1×2 bricks as armrests/backrest", piecesUsed: "2× 1×2 Brick"),
                ],
                imageSystemName: "chair.fill", funFact: "Central Park in NYC has 9,000 benches, many with dedicated memorial plaques."
            ),

            LegoProject(name: "Binoculars", description: "A pair of binoculars for bird watching.",
                difficulty: .easy, category: .gadget, estimatedTime: "8 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .transparent, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place two 1×4 bricks side by side as barrels", piecesUsed: "2× 1×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Bridge with 1×2 plates", piecesUsed: "2× 1×2 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Add transparent tiles as lenses", piecesUsed: "2× 1×1 Tile"),
                ],
                imageSystemName: "binoculars.fill", funFact: "The first binoculars were invented in 1825 by J.P. Lemière."
            ),

            // Fill medium gaps
            LegoProject(name: "Dutch Windmill", description: "A Dutch-style windmill with rotating sails.",
                difficulty: .medium, category: .building, estimatedTime: "25 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 6, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 1), colorPreference: .white, quantity: 4, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build base on 6×6 plate", piecesUsed: "1× 6×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build tapered body from white bricks", piecesUsed: "4× 2×4 Brick, 4× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add roof with brown slopes", piecesUsed: "4× 2×2 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Build four sail arms from 1×6 plates", piecesUsed: "4× 1×6 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Mount sails on Technic axle", piecesUsed: "1× Technic 1×2"),
                ],
                imageSystemName: "wind", funFact: "The Netherlands has over 1,000 historic windmills still standing."
            ),

            LegoProject(name: "Octopus", description: "A purple octopus with eight curling tentacles.",
                difficulty: .medium, category: .animal, estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 3), colorPreference: .purple, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .purple, quantity: 8, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 4×4 brick as the head", piecesUsed: "1× 4×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add eight 1×4 plates radiating as tentacles", piecesUsed: "8× 1×4 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Add white eyes", piecesUsed: "2× 1×1 Brick"),
                ],
                imageSystemName: "water.waves", funFact: "Octopuses have three hearts and blue blood."
            ),

            LegoProject(name: "Space Rover", description: "A Mars rover with antenna and solar panels.",
                difficulty: .medium, category: .spaceship, estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .blue, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 3, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 6, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build chassis from 4×6 plate", piecesUsed: "1× 4×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add body box from 2×4 brick", piecesUsed: "1× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add solar panels from blue plates", piecesUsed: "2× 2×4 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Build antenna mast from 1×1 bricks", piecesUsed: "3× 1×1 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Mount six wheels (rocker-bogie style)", piecesUsed: "6× Wheel"),
                ],
                imageSystemName: "globe.americas.fill", funFact: "NASA's Perseverance rover has been exploring Mars since February 2021."
            ),

            LegoProject(name: "Catamaran", description: "A twin-hull sailing catamaran.",
                difficulty: .medium, category: .vehicle, estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 1), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place two 2×8 plates parallel as hulls", piecesUsed: "2× 2×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Bridge with 4×4 plate as deck", piecesUsed: "1× 4×4 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Build mast from 1×1 bricks", piecesUsed: "4× 1×1 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add sail with slope", piecesUsed: "1× 2×4 Slope"),
                ],
                imageSystemName: "sailboat.fill", funFact: "Catamarans are faster than monohulls because they create less water resistance."
            ),

            LegoProject(name: "Robot Arm", description: "An industrial robot arm with gripper claw.",
                difficulty: .medium, category: .robot, estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build base on 4×4 plate with yellow bricks", piecesUsed: "1× 4×4 Plate, 2× 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Build upper and lower arm from Technic beams", piecesUsed: "2× Technic 1×6, 2× Technic 1×4"),
                    BuildStep(stepNumber: 3, instruction: "Add gripper claw from slopes", piecesUsed: "2× 1×2 Slope"),
                ],
                imageSystemName: "cpu", funFact: "The first industrial robot, Unimate, was installed at a GM plant in 1961."
            ),

            LegoProject(name: "Totem Pole", description: "A colorful totem pole with stacked faces.",
                difficulty: .medium, category: .art, estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .blue, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack alternating colored 2×2 bricks as the pole", piecesUsed: "2× Red, 2× Blue, 2× Green, 2× Yellow"),
                    BuildStep(stepNumber: 2, instruction: "Add wing plates on sides as arms/wings", piecesUsed: "4× 2×4 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Top with slopes as head crest", piecesUsed: "2× 2×2 Slope"),
                ],
                imageSystemName: "paintpalette.fill", funFact: "Totem poles are monumental sculptures carved from large trees by Indigenous peoples of the Pacific Northwest."
            ),

            LegoProject(name: "Catapult Game", description: "A working catapult — launch bricks at targets!",
                difficulty: .medium, category: .game, estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 5, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build base from 4×6 plate", piecesUsed: "1× 4×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build uprights from 2×4 bricks", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add Technic arm and bucket plate", piecesUsed: "1× Technic 1×6, 1× 2×2 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Set up target pins from red 1×1 bricks", piecesUsed: "5× 1×1 Brick", tip: "Stand the bricks up as targets to knock over!"),
                ],
                imageSystemName: "burst.fill", funFact: "Medieval catapults could hurl projectiles weighing up to 300 pounds."
            ),

            // Fill hard gaps
            LegoProject(name: "Gothic Cathedral", description: "A detailed cathedral with flying buttresses and rose window.",
                difficulty: .hard, category: .building, estimatedTime: "40 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 12, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .gray, quantity: 14, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 8, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 4, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 6, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build on 8×12 plate", piecesUsed: "1× 8×12 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build nave walls from 1×8 bricks", piecesUsed: "14× 1×8 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add stained glass windows", piecesUsed: "4× 2×2 Tile"),
                    BuildStep(stepNumber: 4, instruction: "Build flying buttresses from 2×4 bricks and small slopes", piecesUsed: "8× 2×4 Brick, 6× 1×2 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Add roof with 2×6 slopes", piecesUsed: "4× 2×6 Slope"),
                ],
                imageSystemName: "building.columns.fill", funFact: "Notre-Dame took 182 years to build, from 1163 to 1345."
            ),

            LegoProject(name: "Scorpion", description: "A menacing scorpion with pincers and curled tail.",
                difficulty: .hard, category: .animal, estimatedTime: "25 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 6, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .black, quantity: 6, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build body from 2×4 black bricks", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add six legs from 1×4 plates", piecesUsed: "6× 1×4 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Build pincers from 1×2 bricks and slopes", piecesUsed: "2× 1×2 Brick, 2× 1×2 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Build curled tail from stacked 1×2 bricks and slopes", piecesUsed: "4× 1×2 Brick, 2× 1×2 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Add red stinger at tail tip", piecesUsed: "1× 1×1 Brick"),
                ],
                imageSystemName: "ant.fill", funFact: "Scorpions glow under ultraviolet light due to chemicals in their exoskeleton."
            ),

            LegoProject(name: "Steampunk Airship", description: "A fantastical airship with balloon and gondola.",
                difficulty: .hard, category: .spaceship, estimatedTime: "35 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 3), colorPreference: .tan, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the balloon from tan 2×6 bricks with slopes at ends", piecesUsed: "4× 2×6 Brick, 4× 2×4 Slope"),
                    BuildStep(stepNumber: 2, instruction: "Build the gondola from brown 2×8 and 2×4 bricks", piecesUsed: "2× 2×8 Brick, 2× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Connect with 2×6 plate struts", piecesUsed: "2× 2×6 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Add propeller mounts from 1×1 gray bricks", piecesUsed: "4× 1×1 Brick"),
                ],
                imageSystemName: "airplane", funFact: "The first successful airship flight was by Henri Giffard in 1852, powered by a steam engine."
            ),

            LegoProject(name: "DJ Turntable", description: "A music DJ setup with turntable and mixer.",
                difficulty: .hard, category: .gadget, estimatedTime: "30 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 8, heightUnits: 1), colorPreference: .black, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build base from 6×8 plate", piecesUsed: "1× 6×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Place two 4×4 plates as turntable platters", piecesUsed: "2× 4×4 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Add vinyl record tiles on platters", piecesUsed: "2× 2×2 Tile"),
                    BuildStep(stepNumber: 4, instruction: "Build mixer section with 1×4 gray bricks", piecesUsed: "4× 1×4 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Add fader knobs and buttons", piecesUsed: "4× 1×1 Brick, 2× 1×2 Plate"),
                ],
                imageSystemName: "music.note", funFact: "The first DJ to use two turntables at once was Francis Grasso in 1969."
            ),

            LegoProject(name: "Labyrinth Game", description: "A tilting maze game with walls and a marble path.",
                difficulty: .hard, category: .game, estimatedTime: "35 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .tan, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 8, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 8, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .red, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build floor on 8×8 plate", piecesUsed: "1× 8×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build outer walls from 1×8 bricks", piecesUsed: "4× 1×8 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build internal maze walls from 1×4 and 1×2 bricks", piecesUsed: "8× 1×4 Brick, 8× 1×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Mark start (green) and finish (red) with tiles", piecesUsed: "1× Green Tile, 1× Red Tile"),
                ],
                imageSystemName: "square.grid.3x3", funFact: "Labyrinth wooden games have been popular since the 1940s in Scandinavia."
            ),

            LegoProject(name: "Medieval Joust Arena", description: "A jousting arena with lance racks and spectator stands.",
                difficulty: .hard, category: .decoration, estimatedTime: "35 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 12, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 1), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build arena base on 8×12 green plate", piecesUsed: "1× 8×12 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build the central fence/tilt from 1×8 brown bricks", piecesUsed: "4× 1×8 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build spectator stands from gray bricks", piecesUsed: "4× 2×4 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Build lance racks from 1×4 bricks", piecesUsed: "4× 1×4 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Add lances from 1×6 plates and decorative pennants from slopes", piecesUsed: "4× 1×6 Plate, 4× 2×2 Slope"),
                ],
                imageSystemName: "flag.fill", funFact: "Medieval jousting tournaments could attract thousands of spectators and lasted several days."
            ),

            // Fill expert gaps
            LegoProject(name: "Dragon with Rider", description: "A large dragon with spread wings and a mounted rider.",
                difficulty: .expert, category: .animal, estimatedTime: "60 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 3), colorPreference: .green, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .green, quantity: 6, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 8, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 8, heightUnits: 1), colorPreference: .green, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .green, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the body from 2×8 and 2×4 green bricks", piecesUsed: "2× 2×8 Brick, 4× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Build four legs from 2×2 green bricks", piecesUsed: "8× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add wings from 4×8 green plates", piecesUsed: "2× 4×8 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Build the head and neck from 2×4 bricks and slopes", piecesUsed: "2× 2×4 Brick, 4× 2×4 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Add yellow eyes and red flame breath", piecesUsed: "2× 1×1 Yellow, 4× 1×1 Red"),
                    BuildStep(stepNumber: 6, instruction: "Build the rider from brown 2×2 bricks", piecesUsed: "4× 2×2 Brick"),
                ],
                imageSystemName: "flame.fill", funFact: "Dragon legends appear in nearly every culture, from Chinese long to European wyrms."
            ),

            LegoProject(name: "Space Colony", description: "A domed Mars colony with habitation pods and solar arrays.",
                difficulty: .expert, category: .spaceship, estimatedTime: "60 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 12, heightUnits: 1), colorPreference: .tan, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 8, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 8, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 8, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .blue, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 4, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build Mars surface on tan 8×12 plate", piecesUsed: "1× 8×12 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build three habitat domes from white bricks and slopes", piecesUsed: "8× 2×4 Brick, 8× 2×2 Brick, 8× 2×4 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Add transparent viewport tiles to each dome", piecesUsed: "4× 2×2 Tile"),
                    BuildStep(stepNumber: 4, instruction: "Build solar panel arrays from blue plates", piecesUsed: "4× 4×4 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Connect domes with corridor plates", piecesUsed: "2× 2×6 Plate"),
                ],
                imageSystemName: "globe.americas.fill", funFact: "NASA aims to send humans to Mars in the 2030s for the first crewed mission."
            ),

            LegoProject(name: "Concert Stage", description: "A rock concert stage with speaker stacks and lighting rig.",
                difficulty: .expert, category: .gadget, estimatedTime: "50 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 12, heightUnits: 1), colorPreference: .black, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .black, quantity: 8, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 12, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 8, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .red, quantity: 4, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .blue, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the stage floor on 8×12 plate", piecesUsed: "1× 8×12 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build speaker stacks from black 2×2 bricks on each side", piecesUsed: "12× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build the lighting truss frame from 2×4 bricks and 1×1 posts", piecesUsed: "8× 2×4 Brick, 8× 1×1 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add the overhead lighting plate", piecesUsed: "1× 8×8 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Add colored stage lights", piecesUsed: "4× Red Tile, 4× Blue Tile"),
                ],
                imageSystemName: "music.mic", funFact: "The largest concert ever held was Rod Stewart's 1994 show at Copacabana Beach: 3.5 million people."
            ),

            LegoProject(name: "Rube Goldberg Machine", description: "A chain-reaction contraption with ramps, levers, and falling blocks.",
                difficulty: .expert, category: .game, estimatedTime: "60 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 16, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .blue, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 6, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 8, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .white, quantity: 10, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 1), colorPreference: .orange, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the base on 8×16 plate", piecesUsed: "1× 8×16 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build ramps from slopes at descending heights", piecesUsed: "4× 2×4 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Build domino chains from 1×1 bricks (don't press down!)", piecesUsed: "10× 1×1 Brick", tip: "Stand them up loosely — they need to fall!"),
                    BuildStep(stepNumber: 4, instruction: "Build lever seesaws from Technic beams on 2×2 fulcrums", piecesUsed: "2× Technic 1×8, 2× 2×2 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Build platforms and catching bins from remaining bricks", piecesUsed: "6× 2×4 Brick, 6× 2×2 Brick"),
                    BuildStep(stepNumber: 6, instruction: "Add ramp surfaces from plates", piecesUsed: "2× 2×8 Plate"),
                ],
                imageSystemName: "gearshape.2", funFact: "Rube Goldberg was a Pulitzer Prize-winning cartoonist who drew absurdly complex machines."
            ),

            // More medium/hard fills for underrepresented categories
            LegoProject(name: "Battle Tank", description: "A military tank with turret and tracks.",
                difficulty: .hard, category: .vehicle, estimatedTime: "35 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 8, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .green, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 1), colorPreference: .darkGray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 2, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 6, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build hull on 4×8 plate", piecesUsed: "1× 4×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build hull body from 2×4 green bricks", piecesUsed: "4× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add track plates on each side", piecesUsed: "2× 2×8 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Mount road wheels", piecesUsed: "6× Wheel"),
                    BuildStep(stepNumber: 5, instruction: "Build turret from 2×2 bricks and slopes", piecesUsed: "4× 2×2 Brick, 2× 2×2 Slope"),
                    BuildStep(stepNumber: 6, instruction: "Add cannon barrel from 1×6 brick", piecesUsed: "1× 1×6 Brick"),
                ],
                imageSystemName: "shield.fill", funFact: "The first tanks were used in World War I at the Battle of the Somme in 1916."
            ),

            LegoProject(name: "Android Robot", description: "A friendly android with glowing chest core and articulated limbs.",
                difficulty: .hard, category: .robot, estimatedTime: "30 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 3, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 6, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .transparent, quantity: 3, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build legs from white 2×2 bricks and plate feet", piecesUsed: "4× 2×2 Brick, 2× 2×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build torso from white 2×4 bricks", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add glowing chest core tile", piecesUsed: "1× 1×1 Tile"),
                    BuildStep(stepNumber: 4, instruction: "Build arms from Technic beams", piecesUsed: "4× Technic 1×4"),
                    BuildStep(stepNumber: 5, instruction: "Build head from 2×4 and 2×2 bricks with eye tiles", piecesUsed: "1× 2×4 Brick, 2× 2×2 Brick, 2× 1×1 Tile"),
                ],
                imageSystemName: "cpu", funFact: "The word 'android' comes from Greek meaning 'having the form of a man'."
            ),

            LegoProject(name: "Hanging Garden", description: "A Babylonian-inspired tiered garden with cascading greenery.",
                difficulty: .expert, category: .nature, estimatedTime: "50 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .tan, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .tan, quantity: 8, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .tan, quantity: 8, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .green, quantity: 3, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 8, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .green, quantity: 12, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 6, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build base platform on 8×8 plate", piecesUsed: "1× 8×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build three ascending tiers from tan bricks", piecesUsed: "8× 2×4 Brick, 8× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add garden bed plates on each tier", piecesUsed: "3× 4×6 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Add cascading greenery with green slopes and stacked 1×1 bricks", piecesUsed: "8× 2×2 Slope, 12× 1×1 Green"),
                    BuildStep(stepNumber: 5, instruction: "Add flowers with red 1×1 bricks", piecesUsed: "6× 1×1 Red"),
                ],
                imageSystemName: "leaf.fill", funFact: "The Hanging Gardens of Babylon are one of the Seven Wonders of the Ancient World — though their existence is debated."
            ),

            LegoProject(name: "Colosseum Ruin", description: "A Roman Colosseum section with arches and tiered seating.",
                difficulty: .expert, category: .building, estimatedTime: "70 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 12, heightUnits: 1), colorPreference: .tan, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .tan, quantity: 16, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .tan, quantity: 12, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .tan, quantity: 8, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .tan, quantity: 8, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 8, heightUnits: 1), colorPreference: .tan, quantity: 3, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build foundation on 8×12 plate", piecesUsed: "1× 8×12 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build the curved wall section with 1×8 and 2×4 bricks", piecesUsed: "16× 1×8 Brick, 12× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Create arched openings using gaps between columns", piecesUsed: "8× 1×4 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Build tiered seating from 4×8 plates", piecesUsed: "3× 4×8 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Add the ruined top with slopes at varying heights", piecesUsed: "8× 2×2 Slope"),
                ],
                imageSystemName: "building.columns.fill", funFact: "The Colosseum could hold up to 80,000 spectators and had a retractable canvas awning."
            ),

            LegoProject(name: "Treasure Map Frame", description: "A decorative frame with a brick-built 'parchment' treasure map inside.",
                difficulty: .medium, category: .decoration, estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .tan, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .red, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .blue, quantity: 4, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .green, quantity: 6, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place tan 8×8 plate as the parchment", piecesUsed: "1× 8×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build frame border from brown 1×8 bricks", piecesUsed: "4× 1×8 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add map details: green island tiles, blue water tiles", piecesUsed: "6× Green Tile, 4× Blue Tile"),
                    BuildStep(stepNumber: 4, instruction: "Mark the X with the red tile", piecesUsed: "1× Red Tile"),
                ],
                imageSystemName: "map.fill", funFact: "The most valuable real treasure map led to the discovery of the Dead Sea Scrolls in 1947."
            ),

            LegoProject(name: "Hourglass", description: "A decorative hourglass with frame and sand detail.",
                difficulty: .medium, category: .gadget, estimatedTime: "18 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .transparent, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .yellow, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build top and bottom caps from 4×4 plates", piecesUsed: "2× 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build frame pillars from brown 1×1 bricks at corners", piecesUsed: "4× 1×1 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build the glass bulbs from transparent 2×2 bricks", piecesUsed: "4× 2×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add yellow sand detail bricks inside", piecesUsed: "4× 1×1 Brick"),
                ],
                imageSystemName: "hourglass", funFact: "Hourglasses were used on ships because they worked regardless of the ship's motion."
            ),

            LegoProject(name: "Spy Robot", description: "A sneaky surveillance bot with camera eye and wheels.",
                difficulty: .medium, category: .robot, estimatedTime: "18 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .red, quantity: 1, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build body from 2×4 black bricks", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add camera head from 2×2 bricks", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add camera eye with red tile", piecesUsed: "1× 1×1 Tile"),
                    BuildStep(stepNumber: 4, instruction: "Add antenna with gray brick", piecesUsed: "1× 1×2 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Mount wheels", piecesUsed: "4× Wheel"),
                ],
                imageSystemName: "eye.fill", funFact: "Military spy robots can be as small as insects — DARPA has built moth-sized drones."
            ),

            LegoProject(name: "Dominoes Set", description: "A set of brick dominoes you can line up and knock down.",
                difficulty: .beginner, category: .game, estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 20, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stand all 20 bricks upright in a curving line", piecesUsed: "20× 2×4 Brick", tip: "Space them just close enough to knock each other over!"),
                    BuildStep(stepNumber: 2, instruction: "Tip the first one and watch them fall!", piecesUsed: "none"),
                ],
                imageSystemName: "rectangle.stack.fill", funFact: "The world record for a domino chain is 5 million tiles, set in 2009."
            ),

            LegoProject(name: "Wizard Tower", description: "A tall spiral wizard tower with stargazing platform.",
                difficulty: .expert, category: .character, estimatedTime: "50 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 6, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 12, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 8, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .purple, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 4, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 3, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .yellow, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build base on 6×6 plate", piecesUsed: "1× 6×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build the tower body, rotating offset each level for spiral effect", piecesUsed: "12× 2×4 Brick, 8× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add floor plates between levels", piecesUsed: "3× 4×4 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Add mystical windows", piecesUsed: "4× 1×2 Tile"),
                    BuildStep(stepNumber: 5, instruction: "Build the conical roof from purple slopes", piecesUsed: "4× 2×2 Slope"),
                    BuildStep(stepNumber: 6, instruction: "Add the glowing orb on top", piecesUsed: "1× 1×1 Brick"),
                ],
                imageSystemName: "wand.and.stars", funFact: "The tallest tower in a medieval castle was often the keep — the lord's final refuge."
            ),

            // Additional projects to reach 200+

            LegoProject(name: "Pirate Galleon", description: "A classic pirate galleon with sails and skull flag.",
                difficulty: .hard, category: .vehicle, estimatedTime: "40 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 12, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .brown, quantity: 8, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 8, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .white, quantity: 3, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build hull on 4×12 plate with slopes at bow/stern", piecesUsed: "1× 4×12 Plate, 2× 2×4 Slope"),
                    BuildStep(stepNumber: 2, instruction: "Build hull walls from 1×6 bricks", piecesUsed: "8× 1×6 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build masts from stacked 1×1 bricks", piecesUsed: "8× 1×1 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add sails from white plates", piecesUsed: "3× 4×4 Plate"),
                ],
                imageSystemName: "sailboat.fill", funFact: "The golden age of piracy lasted from 1650 to 1730."
            ),

            LegoProject(name: "Rescue Chopper", description: "A rescue helicopter with spinning rotor blades.",
                difficulty: .medium, category: .vehicle, estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 3), colorPreference: .red, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build fuselage from 2×6 brick", piecesUsed: "1× 2×6 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add cockpit with 2×2 bricks and transparent windshield", piecesUsed: "2× 2×2 Brick, 1× 2×2 Tile"),
                    BuildStep(stepNumber: 3, instruction: "Add tail boom with slopes", piecesUsed: "2× 2×2 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Add rotor blades from 1×8 plates crossed on top", piecesUsed: "2× 1×8 Plate"),
                ],
                imageSystemName: "airplane", funFact: "The first practical helicopter flight was in 1939 by Igor Sikorsky's VS-300."
            ),

            LegoProject(name: "Bonsai Display", description: "A miniature bonsai tree in a rectangular pot.",
                difficulty: .medium, category: .nature, estimatedTime: "18 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 5, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 6, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build rectangular pot from 4×6 plate", piecesUsed: "1× 4×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build trunk from stacked 1×1 brown bricks with branch offsets", piecesUsed: "5× 1×1 Brick, 2× 1×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add foliage canopy from green slopes", piecesUsed: "6× 2×2 Slope"),
                ],
                imageSystemName: "tree.fill", funFact: "The oldest known bonsai tree is over 1,000 years old, kept in Japan."
            ),

            LegoProject(name: "Chess King", description: "An oversized chess king piece for display.",
                difficulty: .medium, category: .decoration, estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build base from 4×4 plate", piecesUsed: "1× 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Stack 2×2 bricks to form the tall body", piecesUsed: "4× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add cross on top from plate and yellow bricks", piecesUsed: "1× 2×4 Plate, 2× 1×1 Brick"),
                ],
                imageSystemName: "crown.fill", funFact: "The Lewis Chessmen from the 12th century are the most famous ancient chess pieces."
            ),

            LegoProject(name: "Yellow Submersible", description: "A yellow research submersible with periscope and propeller.",
                difficulty: .medium, category: .vehicle, estimatedTime: "22 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 2, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 3, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build hull from 2×8 yellow bricks", piecesUsed: "2× 2×8 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Taper bow and stern with slopes", piecesUsed: "2× 2×4 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Add conning tower from 2×2 bricks", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add periscope from 1×1 gray bricks", piecesUsed: "3× 1×1 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Add portholes with transparent tiles", piecesUsed: "2× 2×2 Tile"),
                ],
                imageSystemName: "water.waves", funFact: "The Beatles' 'Yellow Submarine' was released in 1966 and became a beloved animated film."
            ),

            LegoProject(name: "Championship Cup", description: "A golden championship cup with handles and base.",
                difficulty: .easy, category: .decoration, estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .yellow, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 3, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .yellow, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build base from 4×4 plate", piecesUsed: "1× 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Stack 2×2 bricks as the cup", piecesUsed: "3× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add handles from 1×2 plates on each side", piecesUsed: "2× 1×2 Plate"),
                ],
                imageSystemName: "trophy.fill", funFact: "The FIFA World Cup trophy is made of 18-carat gold and weighs 13.6 pounds."
            ),

            LegoProject(name: "Desert Saguaro", description: "A desert saguaro cactus with arms and flower on top.",
                difficulty: .easy, category: .nature, estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .tan, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 3, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .pink, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place tan plate as desert ground", piecesUsed: "1× 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Stack green 2×2 bricks as main trunk", piecesUsed: "3× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add 1×2 bricks as arms branching off", piecesUsed: "2× 1×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add pink flower on top", piecesUsed: "1× 1×1 Brick"),
                ],
                imageSystemName: "leaf.fill", funFact: "Some saguaro cacti can live for over 200 years and grow to 60 feet tall."
            ),

            LegoProject(name: "Timer Watch", description: "A functional-looking timer watch with button and display.",
                difficulty: .easy, category: .gadget, estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 4×4 brick as the watch body", piecesUsed: "1× 4×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add white tile as display face", piecesUsed: "1× 2×2 Tile"),
                    BuildStep(stepNumber: 3, instruction: "Add red button on top", piecesUsed: "1× 1×1 Brick"),
                ],
                imageSystemName: "stopwatch.fill", funFact: "The first stopwatch accurate to 1/100th of a second was made by TAG Heuer in 1916."
            ),

            LegoProject(name: "Mini Rocket Launcher", description: "A shoulder-fired rocket launcher prop.",
                difficulty: .easy, category: .weapon, estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 3), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 2×8 brick as the tube", piecesUsed: "1× 2×8 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add 2×2 brick as grip section", piecesUsed: "1× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add sight from black slope", piecesUsed: "1× 2×2 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Add red brick as rocket tip", piecesUsed: "1× 1×1 Brick"),
                ],
                imageSystemName: "scope", funFact: "The bazooka got its name from a musical instrument played by comedian Bob Burns."
            ),

            LegoProject(name: "Emperor Penguin", description: "A cute emperor penguin with flippers and orange beak.",
                difficulty: .easy, category: .animal, estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .orange, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack black and white 2×2 bricks for body", piecesUsed: "2× Black, 1× White"),
                    BuildStep(stepNumber: 2, instruction: "Add flipper plates on sides", piecesUsed: "2× 1×2 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Add orange beak and white eyes", piecesUsed: "1× 1×2 Slope, 2× 1×1 Brick"),
                ],
                imageSystemName: "bird.fill", funFact: "Emperor penguins can dive to depths of 1,800 feet — deeper than any other bird."
            ),

            LegoProject(name: "Mini Library", description: "A miniature bookshelf with colorful book spines.",
                difficulty: .easy, category: .furniture, estimatedTime: "12 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 3, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .red, quantity: 3, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .blue, quantity: 3, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .green, quantity: 3, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build uprights from 1×1 brown bricks stacked 2 high on each end", piecesUsed: "4× 1×1 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Place 2×6 plates as three shelves", piecesUsed: "3× 2×6 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Fill shelves with colorful tiles as books", piecesUsed: "3× Red, 3× Blue, 3× Green"),
                ],
                imageSystemName: "books.vertical.fill", funFact: "The Library of Congress holds over 170 million items — the largest library in the world."
            ),

            LegoProject(name: "Wishing Well", description: "A stone wishing well with crank and bucket.",
                difficulty: .medium, category: .building, estimatedTime: "18 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build circular well wall on 4×4 plate from 2×2 gray bricks", piecesUsed: "1× 4×4 Plate, 4× 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Build two uprights from brown 1×1 bricks", piecesUsed: "4× 1×1 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add roof with brown plate and slopes", piecesUsed: "1× 4×4 Plate, 2× 2×2 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Add bucket from gray 1×1 brick", piecesUsed: "1× 1×1 Brick"),
                ],
                imageSystemName: "drop.fill", funFact: "The tradition of throwing coins in wishing wells dates back to ancient Celtic water worship."
            ),

            LegoProject(name: "Gold Hoard Chest", description: "A pirate treasure chest overflowing with gold.",
                difficulty: .beginner, category: .decoration, estimatedTime: "8 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .yellow, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack two 2×4 bricks as the chest box", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add slope as the lid", piecesUsed: "1× 2×4 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Place yellow bricks on top as overflowing gold", piecesUsed: "4× 1×1 Brick"),
                ],
                imageSystemName: "lock.fill", funFact: "The most valuable treasure ever found at sea was $17 billion in gold from the San José."
            ),

            LegoProject(name: "Stargazer Scope", description: "A tabletop telescope on a tripod mount.",
                difficulty: .medium, category: .gadget, estimatedTime: "18 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .black, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .black, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 3, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .transparent, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build tripod from three 1×1 gray bricks on 2×2 plate", piecesUsed: "3× 1×1 Brick, 1× 2×2 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build telescope tube from 1×6 and 1×4 black bricks", piecesUsed: "1× 1×6 Brick, 1× 1×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add lenses at each end with transparent tiles", piecesUsed: "2× 1×1 Tile"),
                ],
                imageSystemName: "scope", funFact: "Galileo's telescope had only 20× magnification — less than modern binoculars."
            ),

            LegoProject(name: "Slingshot", description: "A simple Y-shaped slingshot.",
                difficulty: .beginner, category: .weapon, estimatedTime: "5 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 1×4 brick as the handle", piecesUsed: "1× 1×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add two 1×2 bricks as the Y-arms at the top", piecesUsed: "2× 1×2 Brick"),
                ],
                imageSystemName: "target", funFact: "David famously used a sling (not a slingshot) to defeat Goliath."
            ),

            LegoProject(name: "Farm Hauler", description: "A classic farm hauler truck with open bed.",
                difficulty: .medium, category: .vehicle, estimatedTime: "18 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 8, heightUnits: 1), colorPreference: .red, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 1, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build chassis from 4×8 plate", piecesUsed: "1× 4×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build cab from 2×4 bricks with slope windshield", piecesUsed: "1× 2×4 Brick, 1× 2×2 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Build truck bed walls from 1×4 bricks", piecesUsed: "2× 1×4 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add bed floor from remaining 2×4 brick", piecesUsed: "1× 2×4 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Mount wheels", piecesUsed: "4× Wheel"),
                ],
                imageSystemName: "car.fill", funFact: "The Ford F-150 has been America's best-selling vehicle for over 40 years."
            ),

            LegoProject(name: "Country Barn", description: "A red country barn with loft doors and silo.",
                difficulty: .hard, category: .building, estimatedTime: "35 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .red, quantity: 12, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 6, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build base on 8×8 green plate", piecesUsed: "1× 8×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build barn walls from red bricks", piecesUsed: "12× 1×8 Brick, 4× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add loft door from brown plates", piecesUsed: "2× 2×4 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Build peaked roof from brown slopes", piecesUsed: "4× 2×6 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Build silo next to barn from gray 2×2 bricks", piecesUsed: "6× 2×2 Brick"),
                ],
                imageSystemName: "house.fill", funFact: "Red barns are red because farmers mixed rust (iron oxide) into sealant — it was cheap and killed fungi."
            ),

            LegoProject(name: "Toadstool", description: "A cute red-capped toadstool with white spots.",
                difficulty: .beginner, category: .nature, estimatedTime: "5 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .red, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack two white 1×1 bricks as the stem", piecesUsed: "2× 1×1 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Place 2×2 plate on top", piecesUsed: "1× 2×2 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Add red slopes around edges for the cap", piecesUsed: "4× 2×2 Slope"),
                ],
                imageSystemName: "leaf.fill", funFact: "The world's largest living organism is a honey fungus in Oregon spanning 2,385 acres."
            ),

            LegoProject(name: "Anchor", description: "A nautical anchor display piece.",
                difficulty: .easy, category: .decoration, estimatedTime: "8 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build vertical shaft from 1×4 brick", piecesUsed: "1× 1×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add crossbar from 1×4 plate at top", piecesUsed: "1× 1×4 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Add anchor flukes from 1×1 bricks and slopes at bottom", piecesUsed: "2× 1×1 Brick, 2× 1×2 Slope"),
                ],
                imageSystemName: "anchor", funFact: "The anchor of the Titanic weighed over 15 tons and required 20 horses to transport."
            ),

            LegoProject(name: "Panda", description: "A sitting panda bear with bamboo.",
                difficulty: .easy, category: .animal, estimatedTime: "12 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .green, quantity: 3, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build body from alternating black and white 2×2 bricks", piecesUsed: "2× White, 2× Black 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add ears and paws from black 1×1 bricks", piecesUsed: "4× 1×1 Black Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build bamboo stalk from green 1×1 bricks", piecesUsed: "3× 1×1 Green Brick"),
                ],
                imageSystemName: "pawprint.fill", funFact: "Giant pandas spend up to 14 hours a day eating bamboo — consuming up to 38 kg daily."
            ),

            LegoProject(name: "Alien UFO", description: "A flying saucer with dome cockpit and landing gear.",
                difficulty: .medium, category: .spaceship, estimatedTime: "18 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 6, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 1, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 3, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build saucer disc from 6×6 plate", piecesUsed: "1× 6×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add slopes around edges for saucer profile", piecesUsed: "4× 2×2 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Build dome cockpit with green brick and transparent top", piecesUsed: "1× 2×2 Brick, 1× 2×2 Tile"),
                    BuildStep(stepNumber: 4, instruction: "Add three landing legs underneath", piecesUsed: "3× 1×1 Brick"),
                ],
                imageSystemName: "sparkles", funFact: "The first widely reported UFO sighting was by Kenneth Arnold in 1947 near Mount Rainier."
            ),
        ]
    }
}
