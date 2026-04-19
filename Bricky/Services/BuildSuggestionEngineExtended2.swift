import Foundation

// MARK: - Extended Build Projects Part 2 (~55 projects)
// Focus: More of every category + fill difficulty gaps (beginner, hard, expert)

extension BuildSuggestionEngine {

    func loadExtendedProjects2() -> [LegoProject] {
        [
            // VEHICLES - beginner/expert gaps
            LegoProject(
                name: "Tricycle",
                description: "A simple three-wheeled bike. Great for absolute beginners.",
                difficulty: .beginner, category: .vehicle, estimatedTime: "8 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .red, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: true),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 3, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 2×4 plate as the frame", piecesUsed: "1× 2×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add handlebars from 1×2 bricks", piecesUsed: "2× 1×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Attach three wheels", piecesUsed: "3× Wheel"),
                ],
                imageSystemName: "bicycle", funFact: "The first tricycle was built in 1680 by a German man named Stephan Farffler."
            ),

            LegoProject(
                name: "Steam Train",
                description: "A vintage steam locomotive with smokestack and coal tender.",
                difficulty: .expert, category: .vehicle, estimatedTime: "50 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 12, heightUnits: 1), colorPreference: .black, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 6, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the chassis on 4×12 plate", piecesUsed: "1× 4×12 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build the boiler from 2×6 black bricks", piecesUsed: "4× 2×6 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add cab with 2×4 bricks and red trim", piecesUsed: "4× 2×4 Brick, 4× 2×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Build smokestack from 1×1 gray bricks", piecesUsed: "4× 1×1 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Add cowcatcher with slopes", piecesUsed: "2× 2×4 Slope"),
                    BuildStep(stepNumber: 6, instruction: "Mount six drive wheels", piecesUsed: "6× Wheel"),
                ],
                imageSystemName: "train.side.front.car", funFact: "The first steam locomotive was built in 1804 and could pull 10 tons of iron."
            ),

            LegoProject(
                name: "Ambulance",
                description: "A white ambulance with red cross and emergency lights.",
                difficulty: .easy, category: .vehicle, estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 3, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build chassis on 4×6 plate", piecesUsed: "1× 4×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build body from white 2×4 bricks", piecesUsed: "3× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add red lights on top", piecesUsed: "2× 1×1 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Mount wheels", piecesUsed: "4× Wheel"),
                ],
                imageSystemName: "cross.fill", funFact: "The first ambulance service started in 1487 during the Spanish siege of Málaga."
            ),

            LegoProject(
                name: "Dump Truck",
                description: "A construction dump truck with tilting bed.",
                difficulty: .medium, category: .vehicle, estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 8, heightUnits: 1), colorPreference: .yellow, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .yellow, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .yellow, quantity: 1, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 6, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build frame on 4×8 plate", piecesUsed: "1× 4×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build cab and dump bed from yellow bricks", piecesUsed: "4× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add slope for cab roof", piecesUsed: "1× 2×4 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Mount six wheels (dual rear axle)", piecesUsed: "6× Wheel"),
                ],
                imageSystemName: "truck.box.fill", funFact: "The world's largest dump truck can carry 496 tons — the weight of about 330 cars."
            ),

            // BUILDINGS - beginner/expert
            LegoProject(
                name: "Dog House",
                description: "A simple dog house with peaked roof and nameplate.",
                difficulty: .beginner, category: .building, estimatedTime: "8 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 4×4 plate base", piecesUsed: "1× 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build three walls from 1×4 bricks, leave front open", piecesUsed: "4× 1×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add peaked roof with slopes", piecesUsed: "2× 2×4 Slope"),
                ],
                imageSystemName: "house.fill", funFact: "Snoopy's iconic red doghouse first appeared in Peanuts comics in 1960."
            ),

            LegoProject(
                name: "Space Station Module",
                description: "A cylindrical space station module with solar panels and docking port.",
                difficulty: .expert, category: .building, estimatedTime: "45 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 3), colorPreference: .white, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 8, heightUnits: 1), colorPreference: .blue, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the module cylinder from 2×8 white bricks", piecesUsed: "4× 2×8 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add solar panel wings from 4×8 blue plates", piecesUsed: "4× 4×8 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Build docking ports on each end from 2×2 gray bricks and plates", piecesUsed: "4× 2×2 Brick, 2× 2×2 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Add window viewports with transparent tiles", piecesUsed: "4× 1×2 Tile"),
                ],
                imageSystemName: "globe.americas.fill", funFact: "The ISS orbits Earth every 90 minutes and has been continuously inhabited since 2000."
            ),

            LegoProject(
                name: "Gazebo",
                description: "An octagonal garden gazebo with roof and bench seating.",
                difficulty: .medium, category: .building, estimatedTime: "25 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 6, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .white, quantity: 8, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .brown, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 6×6 green plate as the floor", piecesUsed: "1× 6×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build 8 corner pillars from 1×1 white bricks", piecesUsed: "8× 1×1 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add roof platform with 4×4 plate", piecesUsed: "1× 4×4 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Build peaked roof with slopes", piecesUsed: "4× 2×2 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Add bench seats from 1×2 plates", piecesUsed: "4× 1×2 Plate"),
                ],
                imageSystemName: "building.fill", funFact: "The word 'gazebo' likely comes from the joke Latin phrase meaning 'I shall gaze'."
            ),

            // ANIMALS - filling gaps
            LegoProject(
                name: "Horse",
                description: "A galloping horse with mane and tail.",
                difficulty: .medium, category: .animal, estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 3), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .black, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the body from 2×6 brick", piecesUsed: "1× 2×6 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add four legs from 2×2 bricks", piecesUsed: "4× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build neck and head from 2×4 brick and slopes", piecesUsed: "1× 2×4 Brick, 2× 2×2 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Add mane and tail from black plates", piecesUsed: "2× 1×2 Plate"),
                ],
                imageSystemName: "hare.fill", funFact: "Horses can sleep both lying down and standing up."
            ),

            LegoProject(
                name: "Turtle",
                description: "A small sea turtle with flippers and patterned shell.",
                difficulty: .beginner, category: .animal, estimatedTime: "8 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .green, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .green, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 2×4 plate as the body", piecesUsed: "1× 2×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add slopes on top for the shell", piecesUsed: "2× 2×2 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Attach four 1×2 plates as flippers", piecesUsed: "4× 1×2 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Add 1×1 brick as the head", piecesUsed: "1× 1×1 Brick"),
                ],
                imageSystemName: "tortoise.fill", funFact: "Sea turtles can hold their breath for up to 7 hours while sleeping."
            ),

            LegoProject(
                name: "Whale",
                description: "A majestic blue whale breaching from the waves.",
                difficulty: .hard, category: .animal, estimatedTime: "30 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 3), colorPreference: .blue, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .blue, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .blue, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .blue, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the main body from 2×8 blue bricks", piecesUsed: "2× 2×8 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add white underbelly bricks", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Taper head and tail with 2×4 bricks and slopes", piecesUsed: "2× 2×4 Brick, 2× 2×4 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Build tail flukes from 4×4 plate", piecesUsed: "1× 4×4 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Add eyes", piecesUsed: "2× 1×1 Brick"),
                ],
                imageSystemName: "water.waves", funFact: "Blue whales are the largest animals ever to have lived — bigger than any dinosaur."
            ),

            LegoProject(
                name: "Spider",
                description: "A creepy-crawly spider with eight poseable legs.",
                difficulty: .easy, category: .animal, estimatedTime: "12 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the body from two 2×2 black bricks", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Attach four 1×4 plates as legs on each side", piecesUsed: "4× 1×4 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Add red eyes", piecesUsed: "2× 1×1 Brick"),
                ],
                imageSystemName: "ant.fill", funFact: "Spiders have been on Earth for over 380 million years — before dinosaurs."
            ),

            LegoProject(
                name: "Eagle",
                description: "A soaring bald eagle with outstretched wings.",
                difficulty: .hard, category: .animal, estimatedTime: "30 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 8, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the body from brown 2×4 bricks", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add 4×8 plates as outstretched wings", piecesUsed: "2× 4×8 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Build white head from 2×2 bricks", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add yellow beak slope and black eyes", piecesUsed: "1× 1×2 Slope, 2× 1×1 Brick"),
                ],
                imageSystemName: "bird.fill", funFact: "Bald eagles can see fish from over a mile away and dive at 100 mph."
            ),

            // ROBOTS - beginner/expert
            LegoProject(
                name: "Tiny Bot",
                description: "The smallest robot you can build — just 8 pieces!",
                difficulty: .beginner, category: .robot, estimatedTime: "5 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack two 2×2 bricks for the body", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add 1×2 bricks as arms", piecesUsed: "2× 1×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add red eyes and plate feet", piecesUsed: "2× 1×1 Brick, 2× 2×2 Plate"),
                ],
                imageSystemName: "cpu", funFact: "The smallest walking robot ever built is just 0.8mm wide — smaller than an ant's head."
            ),

            LegoProject(
                name: "Giant Mech Suit",
                description: "A pilot-able mech suit with cockpit, missile pods, and articulated limbs.",
                difficulty: .expert, category: .robot, estimatedTime: "55 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 6, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 8, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the torso from 4×6 bricks", piecesUsed: "2× 4×6 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Build legs from 2×4 and 2×2 bricks", piecesUsed: "4× 2×4 Brick, 4× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add plate feet", piecesUsed: "2× 4×4 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Build arms from Technic beams", piecesUsed: "4× Technic 1×6"),
                    BuildStep(stepNumber: 5, instruction: "Add shoulder armor with slopes", piecesUsed: "4× 2×4 Slope"),
                    BuildStep(stepNumber: 6, instruction: "Build cockpit head from 2×4 and 2×2 bricks", piecesUsed: "2× 2×4 Brick, 4× 2×2 Brick"),
                    BuildStep(stepNumber: 7, instruction: "Add transparent cockpit viewport", piecesUsed: "1× 2×2 Tile"),
                ],
                imageSystemName: "cpu", funFact: "The Kuratas mech suit is a real 13-foot robot you can buy for $1.35 million."
            ),

            // SPACESHIPS
            LegoProject(
                name: "Mini Shuttle",
                description: "A tiny space shuttle — great beginner build.",
                difficulty: .beginner, category: .spaceship, estimatedTime: "8 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .white, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 2×4 brick as the fuselage", piecesUsed: "1× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add slope as nose cone", piecesUsed: "1× 2×2 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Attach 2×4 plates as wings", piecesUsed: "2× 2×4 Plate"),
                ],
                imageSystemName: "airplane", funFact: "The Space Shuttle made 135 missions over 30 years of service."
            ),

            LegoProject(
                name: "Alien Battlecruiser",
                description: "A menacing alien warship with multiple weapon arrays.",
                difficulty: .expert, category: .spaceship, estimatedTime: "50 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 12, heightUnits: 1), colorPreference: .darkGray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 3), colorPreference: .darkGray, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .darkGray, quantity: 6, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .darkGray, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 8, heightUnits: 1), colorPreference: .darkGray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .green, quantity: 6, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the main hull on 6×12 plate", piecesUsed: "1× 6×12 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build the central body from 2×6 bricks", piecesUsed: "4× 2×6 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add wing struts from 2×4 bricks", piecesUsed: "6× 2×4 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Attach weapon wing plates", piecesUsed: "2× 4×8 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Add aggressive slopes at front", piecesUsed: "4× 2×4 Slope"),
                    BuildStep(stepNumber: 6, instruction: "Mount green weapon turrets", piecesUsed: "6× 1×1 Brick"),
                    BuildStep(stepNumber: 7, instruction: "Add bridge viewports", piecesUsed: "2× 1×2 Tile"),
                ],
                imageSystemName: "airplane", funFact: "If alien civilizations exist, their ships would need to overcome the light-speed barrier — or find wormholes."
            ),

            // ART - more variety
            LegoProject(
                name: "Brick Flag",
                description: "A flat flag design — customize with your country's colors.",
                difficulty: .beginner, category: .art, estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 8, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .red, quantity: 12, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .blue, quantity: 12, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 6×8 white plate as canvas", piecesUsed: "1× 6×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Fill top rows with one color", piecesUsed: "12× Red Tiles"),
                    BuildStep(stepNumber: 3, instruction: "Fill bottom rows with another", piecesUsed: "12× Blue Tiles"),
                ],
                imageSystemName: "flag.fill", funFact: "Nepal's flag is the only national flag that isn't rectangular."
            ),

            LegoProject(
                name: "3D Star Sculpture",
                description: "A freestanding 3D star made from slopes and plates.",
                difficulty: .hard, category: .art, estimatedTime: "30 min",
                requiredPieces: [
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 10, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the core from 2×2 bricks and 4×4 plates", piecesUsed: "4× 2×2 Brick, 2× 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add slopes as star points radiating outward", piecesUsed: "10× 2×2 Slope"),
                ],
                imageSystemName: "star.fill", funFact: "The Hollywood Walk of Fame has over 2,700 brass stars embedded in the sidewalk."
            ),

            // NATURE - more variety
            LegoProject(
                name: "Volcano",
                description: "A smoking volcano with lava flow and rock base.",
                difficulty: .hard, category: .nature, estimatedTime: "35 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 6, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .darkGray, quantity: 6, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .orange, quantity: 4, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build base on 8×8 plate", piecesUsed: "1× 8×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build mountain body with gray bricks tapering inward", piecesUsed: "6× 2×4 Brick, 6× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add lava slopes cascading down", piecesUsed: "4× 2×2 Red Slope, 4× 2×2 Orange Slope"),
                    BuildStep(stepNumber: 4, instruction: "Top with yellow bricks as the eruption glow", piecesUsed: "2× 1×1 Brick"),
                ],
                imageSystemName: "mountain.2.fill", funFact: "There are about 1,500 potentially active volcanoes worldwide — and 80% are underwater."
            ),

            LegoProject(
                name: "Desert Oasis",
                description: "A desert scene with palm trees, a pond, and sand dunes.",
                difficulty: .medium, category: .nature, estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .tan, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 6, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .blue, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .tan, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place tan 8×8 plate as desert floor", piecesUsed: "1× 8×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build palm trunk from 1×1 brown bricks", piecesUsed: "6× 1×1 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add palm fronds with green slopes", piecesUsed: "4× 2×2 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Place blue plate as pond", piecesUsed: "1× 2×4 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Add sand dune slopes", piecesUsed: "2× 2×2 Slope"),
                ],
                imageSystemName: "sun.max.fill", funFact: "The Sahara Desert is roughly the same size as the entire United States."
            ),

            // GADGETS
            LegoProject(
                name: "Grandfather Clock",
                description: "A tall grandfather clock with pendulum and Roman numeral face.",
                difficulty: .hard, category: .gadget, estimatedTime: "30 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .yellow, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build base from 4×4 plate", piecesUsed: "1× 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build the tall body from brown bricks", piecesUsed: "4× 2×4 Brick, 4× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add clock face tile", piecesUsed: "1× 2×2 Tile"),
                    BuildStep(stepNumber: 4, instruction: "Build peaked top with slopes", piecesUsed: "2× 2×2 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Add pendulum from yellow plate", piecesUsed: "1× 1×2 Plate"),
                ],
                imageSystemName: "clock.fill", funFact: "Grandfather clocks got their name from an 1876 song called 'My Grandfather's Clock'."
            ),

            LegoProject(
                name: "Camera",
                description: "A retro box camera with lens, viewfinder, and flash.",
                difficulty: .easy, category: .gadget, estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 3), colorPreference: .black, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .transparent, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 4×4 brick as camera body", piecesUsed: "1× 4×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add 2×2 brick as viewfinder bump", piecesUsed: "1× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add gray bricks as lens barrel and flash", piecesUsed: "2× 1×1 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add transparent tile as lens glass", piecesUsed: "1× 1×1 Tile"),
                ],
                imageSystemName: "camera.fill", funFact: "The first photograph ever taken in 1826 required an 8-hour exposure time."
            ),

            // GAMES
            LegoProject(
                name: "Bowling Alley",
                description: "A mini bowling lane with 10 pin targets you can actually knock over.",
                difficulty: .easy, category: .game, estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 12, heightUnits: 1), colorPreference: .tan, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .white, quantity: 10, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 4×12 plate as the lane", piecesUsed: "1× 4×12 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Stand 10 white 1×1 bricks as pins in triangle formation", piecesUsed: "10× 1×1 White Brick", tip: "Don't attach them — they should be knockable!"),
                    BuildStep(stepNumber: 3, instruction: "Use black 1×1 brick as the bowling ball", piecesUsed: "1× 1×1 Black Brick"),
                ],
                imageSystemName: "figure.bowling", funFact: "A perfect game in bowling (300) requires 12 consecutive strikes."
            ),

            LegoProject(
                name: "Ring Toss Game",
                description: "A ring toss target with pegs of different heights for scoring.",
                difficulty: .beginner, category: .game, estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 6, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 3, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .blue, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 6×6 green plate as base", piecesUsed: "1× 6×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Stack 1×1 bricks at various heights as pegs: 1 high (3 pts), 2 high (5 pts), 3 high (10 pts)", piecesUsed: "3× Red, 2× Yellow, 1× Blue"),
                ],
                imageSystemName: "target", funFact: "Ring toss has been a carnival game since the early 1900s."
            ),

            // CHARACTERS - more variety
            LegoProject(
                name: "Viking Chieftain",
                description: "A Norse chieftain with horned helmet and cloak.",
                difficulty: .medium, category: .character, estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build legs from brown 2×2 bricks", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Build armored torso from gray 2×4 bricks", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build head with gray 2×2 bricks", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add horn slopes on helmet", piecesUsed: "2× 1×2 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Add cloak with brown plate", piecesUsed: "1× 2×4 Plate"),
                ],
                imageSystemName: "figure.wave", funFact: "Real Vikings probably didn't wear horned helmets — that's a 19th-century myth."
            ),

            LegoProject(
                name: "Ninja",
                description: "A stealthy ninja in a crouching pose with katana.",
                difficulty: .easy, category: .character, estimatedTime: "12 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .white, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build body from black 2×2 bricks", piecesUsed: "4× 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add hood slopes", piecesUsed: "2× 1×2 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Build katana from 1×4 gray plate", piecesUsed: "1× 1×4 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Add eyes with white tiles", piecesUsed: "2× 1×1 Tile"),
                ],
                imageSystemName: "figure.martial.arts", funFact: "Real ninjas (shinobi) were spies and scouts, not just warriors."
            ),

            LegoProject(
                name: "Superhero",
                description: "A caped superhero in a heroic flying pose.",
                difficulty: .medium, category: .character, estimatedTime: "18 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .blue, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .blue, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .red, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .yellow, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build legs from red 2×2 bricks", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Build torso from blue 2×4 bricks", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add head from blue 2×2 bricks", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Attach cape from red plate", piecesUsed: "1× 2×4 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Place chest emblem tile", piecesUsed: "1× 1×1 Tile"),
                ],
                imageSystemName: "bolt.fill", funFact: "Superman first appeared in Action Comics #1 in 1938, selling for 10 cents."
            ),

            // FURNITURE
            LegoProject(
                name: "Dining Table with Chairs",
                description: "A dining set with a rectangular table and four chairs.",
                difficulty: .easy, category: .furniture, estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 8, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build table: 4×6 plate on four 1×1 legs", piecesUsed: "1× 4×6 Plate, 4× 1×1 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Build four chairs: 2×2 plate seats on 1×1 brick legs with 1×1 back", piecesUsed: "4× 2×2 Plate, 8× 1×1 Brick"),
                ],
                imageSystemName: "table.furniture.fill", funFact: "The average family eats about 1,000 meals a year at their dining table."
            ),

            LegoProject(
                name: "Wardrobe",
                description: "A tall wardrobe closet with opening doors.",
                difficulty: .medium, category: .furniture, estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .brown, quantity: 8, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .yellow, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build base from 4×6 plate", piecesUsed: "1× 4×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build side and back walls from 1×6 bricks", piecesUsed: "8× 1×6 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add front panels with 1×4 bricks as doors", piecesUsed: "4× 1×4 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Build internal shelf with 2×6 plates", piecesUsed: "2× 2×6 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Add top plate and door handles", piecesUsed: "1× 4×6 Plate, 2× 1×1 Tile"),
                ],
                imageSystemName: "cabinet.fill", funFact: "In Narnia, a magical wardrobe leads to an entire frozen kingdom."
            ),

            // DECORATIONS
            LegoProject(
                name: "Birthday Cake",
                description: "A two-tier birthday cake with candles on top.",
                difficulty: .beginner, category: .decoration, estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 3, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .yellow, quantity: 3, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 4×4 brick as bottom tier", piecesUsed: "1× 4×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Place 2×2 brick as top tier", piecesUsed: "1× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add red bricks as candles", piecesUsed: "3× 1×1 Red Brick"),
                    BuildStep(stepNumber: 4, instruction: "Top candles with yellow flames", piecesUsed: "3× 1×1 Yellow Brick"),
                ],
                imageSystemName: "birthday.cake.fill", funFact: "The record for the largest birthday cake weighed 128,238 pounds."
            ),

            LegoProject(
                name: "Desk Organizer",
                description: "A practical desk organizer with pen cups and card slot.",
                difficulty: .easy, category: .decoration, estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 8, heightUnits: 1), colorPreference: .blue, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .blue, quantity: 6, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .blue, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .blue, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 6×8 plate as the base", piecesUsed: "1× 6×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build two pen cups from 2×2 bricks stacked 3 high", piecesUsed: "6× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build a card slot from 1×4 and 1×2 bricks", piecesUsed: "4× 1×4 Brick, 4× 1×2 Brick"),
                ],
                imageSystemName: "tray.fill", funFact: "A clean desk can improve productivity by up to 40% according to some studies."
            ),

            LegoProject(
                name: "Wind Chime",
                description: "A decorative wind chime frame with hanging elements.",
                difficulty: .medium, category: .decoration, estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .blue, quantity: 3, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .green, quantity: 3, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the top frame from plate and upright bricks", piecesUsed: "1× 4×4 Plate, 2× 1×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add top crossbar plate", piecesUsed: "1× 4×4 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Hang alternating colored 1×1 bricks as chime elements", piecesUsed: "3× Blue, 3× Green"),
                ],
                imageSystemName: "wind", funFact: "Wind chimes were used in ancient Rome to ward off evil spirits."
            ),

            // WEAPONS - fill more difficulty gaps
            LegoProject(
                name: "Battering Ram",
                description: "A wheeled battering ram with a log and covered roof.",
                difficulty: .hard, category: .weapon, estimatedTime: "30 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 8, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 3), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the chassis from 4×8 plate", piecesUsed: "1× 4×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add wheels", piecesUsed: "4× Wheel"),
                    BuildStep(stepNumber: 3, instruction: "Build the frame with 1×8 bricks", piecesUsed: "4× 1×8 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Hang the ram log (2×8 brick) inside", piecesUsed: "1× 2×8 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Add roof cover with slopes", piecesUsed: "2× 2×4 Slope"),
                ],
                imageSystemName: "building.columns.fill", funFact: "Ancient battering rams were sometimes named — the Romans called one 'Helepolis' (City Taker)."
            ),

            // Additional beginner fills across categories
            LegoProject(
                name: "Simple Rocket",
                description: "A three-piece rocket — the easiest space build possible.",
                difficulty: .beginner, category: .spaceship, estimatedTime: "5 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack two white 2×2 bricks", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add red slope as the nose cone", piecesUsed: "1× 2×2 Slope"),
                ],
                imageSystemName: "airplane", funFact: "The first liquid-fueled rocket flew for only 2.5 seconds in 1926."
            ),

            LegoProject(
                name: "Flower Pot",
                description: "A simple potted flower — great first build.",
                difficulty: .beginner, category: .nature, estimatedTime: "5 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .green, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place brown 2×2 brick as the pot", piecesUsed: "1× 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Stack green 1×1 bricks as the stem", piecesUsed: "2× 1×1 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add red slopes as petals", piecesUsed: "2× 1×2 Slope"),
                ],
                imageSystemName: "leaf.fill", funFact: "The oldest potted plant on record is a 242-year-old Eastern Cape cycad at Kew Gardens."
            ),

            LegoProject(
                name: "Mini Lighthouse",
                description: "A tiny lighthouse with alternating stripes — great for beginners.",
                difficulty: .beginner, category: .building, estimatedTime: "8 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .yellow, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack alternating red and white 2×2 bricks", piecesUsed: "2× Red, 2× White"),
                    BuildStep(stepNumber: 2, instruction: "Add red slope as roof", piecesUsed: "1× 2×2 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Place yellow tile as the light", piecesUsed: "1× 1×1 Tile"),
                ],
                imageSystemName: "light.beacon.max.fill", funFact: "The Lighthouse of Alexandria was one of the Seven Wonders of the Ancient World."
            ),

            LegoProject(
                name: "Robot Dog",
                description: "A mechanical dog companion with antenna ears.",
                difficulty: .easy, category: .robot, estimatedTime: "12 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build body from 2×4 gray brick", piecesUsed: "1× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add four 1×2 bricks as legs", piecesUsed: "4× 1×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add head from 2×2 brick", piecesUsed: "1× 2×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add antenna ears and red LED eyes", piecesUsed: "2× 1×1 Brick, 1× 1×2 Plate"),
                ],
                imageSystemName: "cpu", funFact: "Sony's AIBO robot dog could learn tricks and recognize its owner's face."
            ),

            LegoProject(
                name: "Pendulum Clock",
                description: "A simple wall clock with swinging pendulum detail.",
                difficulty: .beginner, category: .gadget, estimatedTime: "8 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .yellow, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 4×4 plate as mounting plate", piecesUsed: "1× 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add white 2×2 brick as clock face", piecesUsed: "1× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Stack brown bricks below as pendulum rod", piecesUsed: "2× 1×1 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add yellow brick as pendulum bob", piecesUsed: "1× 1×1 Brick"),
                ],
                imageSystemName: "clock.fill", funFact: "Pendulum clocks were the most accurate timekeeping technology for 270 years."
            ),

            LegoProject(
                name: "Medieval Castle Gate",
                description: "A fortified castle entrance with portcullis and flanking towers.",
                difficulty: .expert, category: .building, estimatedTime: "55 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 12, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .gray, quantity: 16, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 8, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 12, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 8, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .darkGray, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build foundation on 8×12 plate", piecesUsed: "1× 8×12 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build two flanking towers from 2×4 and 2×2 bricks, 5 rows high", piecesUsed: "8× 2×4 Brick, 12× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build the connecting wall with archway from 1×8 bricks", piecesUsed: "16× 1×8 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add tower roofs with 4×4 plates", piecesUsed: "2× 4×4 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Add crenellations with slopes", piecesUsed: "8× 1×2 Slope"),
                    BuildStep(stepNumber: 6, instruction: "Build the portcullis from 1×4 dark gray plates", piecesUsed: "4× 1×4 Plate"),
                ],
                imageSystemName: "building.columns.fill", funFact: "A portcullis gate could weigh over 2,000 pounds and was lowered with chains and winches."
            ),

            LegoProject(
                name: "Coral Reef",
                description: "A colorful underwater coral reef with fish and seaweed.",
                difficulty: .medium, category: .nature, estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .blue, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .orange, quantity: 4, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 3, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .green, quantity: 6, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .purple, quantity: 3, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 8×8 blue plate as the ocean floor", piecesUsed: "1× 8×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build coral formations from orange and red slopes", piecesUsed: "4× Orange Slope, 3× Red Slope"),
                    BuildStep(stepNumber: 3, instruction: "Add seaweed from stacked green 1×1 bricks", piecesUsed: "6× 1×1 Green Brick"),
                    BuildStep(stepNumber: 4, instruction: "Build small fish from yellow bricks", piecesUsed: "2× 1×2 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Add sea anemones with purple slopes", piecesUsed: "3× 1×2 Purple Slope"),
                ],
                imageSystemName: "water.waves", funFact: "Coral reefs support 25% of all marine species despite covering less than 1% of the ocean floor."
            ),

            LegoProject(
                name: "Tower of Hanoi",
                description: "A playable Tower of Hanoi puzzle with three pegs and stackable discs.",
                difficulty: .easy, category: .game, estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 12, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 9, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .blue, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .red, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .yellow, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 4×12 plate as base", piecesUsed: "1× 4×12 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build three pegs from stacked 1×1 bricks, 3 high each", piecesUsed: "9× 1×1 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Stack discs on first peg: large (4×4), medium (2×4), small (2×2)", piecesUsed: "1× Blue, 1× Red, 1× Yellow Plate", tip: "Don't press down — discs should be removable!"),
                ],
                imageSystemName: "square.grid.3x3", funFact: "Solving Tower of Hanoi with 64 discs would take 585 billion years at one move per second."
            ),

            // Expert art
            LegoProject(
                name: "Brick Mosaic World Map",
                description: "A large 16×16 world map mosaic on a baseplate.",
                difficulty: .expert, category: .art, estimatedTime: "90 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .blue, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .green, quantity: 60, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .blue, quantity: 80, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .white, quantity: 20, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .tan, quantity: 20, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Assemble 4 baseplates (8×8) into a 16×16 grid", piecesUsed: "4× 8×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Fill oceans with blue tiles", piecesUsed: "80× Blue Tile"),
                    BuildStep(stepNumber: 3, instruction: "Build continents with green tiles", piecesUsed: "60× Green Tile"),
                    BuildStep(stepNumber: 4, instruction: "Add polar regions with white tiles", piecesUsed: "20× White Tile"),
                    BuildStep(stepNumber: 5, instruction: "Add desert regions with tan tiles", piecesUsed: "20× Tan Tile"),
                ],
                imageSystemName: "globe.americas.fill", funFact: "The largest LEGO mosaic was 1,500 square meters, featuring 1 million bricks."
            ),

            // Expert decoration
            LegoProject(
                name: "Grandfather Clock Display",
                description: "An ornate display grandfather clock with working-size pendulum chamber.",
                difficulty: .expert, category: .decoration, estimatedTime: "60 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .brown, quantity: 16, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 8, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .yellow, quantity: 2, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .yellow, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build base from 6×6 plate", piecesUsed: "1× 6×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build the case from 1×6 and 1×4 brown bricks, 8 rows high", piecesUsed: "16× 1×6 Brick, 8× 1×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add clock face with white 2×2 tile", piecesUsed: "1× 2×2 Tile"),
                    BuildStep(stepNumber: 4, instruction: "Add top cap with 6×6 plate and crown slopes", piecesUsed: "1× 6×6 Plate, 2× 2×2 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Add decorative details and pendulum", piecesUsed: "2× 1×1 Tile, 1× 1×4 Plate"),
                ],
                imageSystemName: "clock.fill", funFact: "Big Ben in London isn't actually the clock — it's the name of the largest bell inside."
            ),

            // Expert furniture
            LegoProject(
                name: "Victorian Dollhouse",
                description: "A three-story Victorian dollhouse with detailed rooms.",
                difficulty: .expert, category: .furniture, estimatedTime: "75 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .tan, quantity: 3, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .tan, quantity: 18, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .tan, quantity: 12, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 8, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build ground floor walls on first 8×8 plate", piecesUsed: "1× 8×8 Plate, 6× 1×8 Brick, 4× 1×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add second floor plate and walls", piecesUsed: "1× 8×8 Plate, 6× 1×8 Brick, 4× 1×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add third floor plate and walls", piecesUsed: "1× 8×8 Plate, 6× 1×8 Brick, 4× 1×4 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Build the peaked roof with slopes", piecesUsed: "4× 2×6 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Add windows throughout", piecesUsed: "8× 1×2 Tile"),
                    BuildStep(stepNumber: 6, instruction: "Add interior details: stairs, furniture", piecesUsed: "2× 4×4 Plate"),
                ],
                imageSystemName: "house.fill", funFact: "Queen Mary's Dollhouse at Windsor Castle has working plumbing and electricity."
            ),

            // Expert gadget
            LegoProject(
                name: "Microscope",
                description: "A detailed microscope with adjustable stage and eyepiece.",
                difficulty: .expert, category: .gadget, estimatedTime: "40 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .black, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .black, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .transparent, quantity: 2, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the base from 4×6 plate", piecesUsed: "1× 4×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build the arm/stand from 2×4 and 2×2 gray bricks", piecesUsed: "4× 2×4 Brick, 4× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add the optical tube from Technic beam and 1×1 bricks", piecesUsed: "1× Technic 1×6, 4× 1×1 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add the stage plate", piecesUsed: "1× 2×2 Tile"),
                    BuildStep(stepNumber: 5, instruction: "Add lenses with transparent tiles", piecesUsed: "2× 1×1 Tile"),
                ],
                imageSystemName: "magnifyingglass", funFact: "Antonie van Leeuwenhoek's 1670s microscopes could magnify up to 270× using a single tiny lens."
            ),
        ]
    }
}
