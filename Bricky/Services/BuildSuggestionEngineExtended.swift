import Foundation

// MARK: - Extended Build Projects Part 1 (~50 projects)
// Focus: Weapons (new!), more Vehicles, Buildings, Animals, Robots

extension BuildSuggestionEngine {

    func loadExtendedProjects() -> [LegoProject] {
        [
            // WEAPONS (New category — swords, shields, cannons, etc.)
            LegoProject(
                name: "Medieval Sword",
                description: "A classic knight's longsword with a crossguard and pommel. Display it or arm your minifigure army!",
                difficulty: .easy,
                category: .weapon,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .yellow, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack two 1×6 plates for the blade", piecesUsed: "2× 1×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add 1×2 plates sideways for the crossguard", piecesUsed: "2× 1×2 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Attach 2×2 plate as the handle", piecesUsed: "1× 2×2 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Top with a 1×1 tile as the pommel", piecesUsed: "1× 1×1 Tile"),
                ],
                imageSystemName: "shield.fill",
                funFact: "Medieval swords typically weighed only 2-4 pounds — much lighter than movies suggest!"
            ),

            LegoProject(
                name: "Viking Shield",
                description: "A round Viking shield with boss detail. Perfect companion to the Medieval Sword.",
                difficulty: .easy,
                category: .weapon,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .brown, quantity: 4, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .yellow, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the 4×4 plate as the shield body", piecesUsed: "1× 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Round out with 2×2 plates on edges", piecesUsed: "4× 2×2 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Add the 1×1 brick as the boss center", piecesUsed: "1× 1×1 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Top with decorative tile", piecesUsed: "1× 2×2 Tile"),
                ],
                imageSystemName: "shield.fill",
                funFact: "Viking shields were typically made from linden wood and were about 80-90cm in diameter."
            ),

            LegoProject(
                name: "Pirate Cannon",
                description: "A classic deck-mounted cannon with wheels. Fire away, matey!",
                difficulty: .medium,
                category: .weapon,
                estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .darkGray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .darkGray, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .darkGray, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the carriage from the 2×6 plate base", piecesUsed: "1× 2×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add wheels to each side of the carriage", piecesUsed: "2× Wheel"),
                    BuildStep(stepNumber: 3, instruction: "Stack 2×4 bricks for the barrel", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Cap with 2×2 bricks and a slope for the muzzle", piecesUsed: "2× 2×2 Brick, 1× 2×2 Slope"),
                ],
                imageSystemName: "flame.fill",
                funFact: "Naval cannons in the 1700s could fire a 32-pound ball over a mile!"
            ),

            LegoProject(
                name: "Bow and Arrow Stand",
                description: "A display stand with a recurve bow and quiver of arrows.",
                difficulty: .medium,
                category: .weapon,
                estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 3, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .tan, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the display base with 4×4 plate", piecesUsed: "1× 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Create the bow limbs with 1×6 bricks and slopes", piecesUsed: "2× 1×6 Brick, 4× 1×2 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Build the quiver from 1×1 bricks", piecesUsed: "3× 1×1 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add arrow shafts with 1×4 plates", piecesUsed: "2× 1×4 Plate"),
                ],
                imageSystemName: "scope",
                funFact: "English longbows could shoot arrows over 300 yards at the Battle of Agincourt."
            ),

            LegoProject(
                name: "Catapult Siege Engine",
                description: "A working-style medieval catapult with a swing arm and bucket.",
                difficulty: .hard,
                category: .weapon,
                estimatedTime: "35 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 8, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: true),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the base frame on the 4×8 plate", piecesUsed: "1× 4×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build uprights with 2×4 bricks on each side", piecesUsed: "4× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add the Technic beam as the swing arm through the uprights", piecesUsed: "1× Technic 1×8"),
                    BuildStep(stepNumber: 4, instruction: "Build the bucket from 2×2 bricks and plates", piecesUsed: "4× 2×2 Brick, 2× 2×2 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Add wheels for mobility", piecesUsed: "4× Wheel"),
                ],
                imageSystemName: "burst.fill",
                funFact: "Real trebuchets could hurl 300-pound projectiles over 300 meters!"
            ),

            LegoProject(
                name: "Laser Blaster",
                description: "A futuristic sci-fi blaster with a scope and energy cell.",
                difficulty: .easy,
                category: .weapon,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 1, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Stack 1×4 bricks for the barrel", piecesUsed: "2× 1×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add 1×2 bricks for the grip", piecesUsed: "2× 1×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Place the transparent tile as the scope lens", piecesUsed: "1× 1×2 Tile"),
                    BuildStep(stepNumber: 4, instruction: "Add slope at the back for the stock", piecesUsed: "1× 1×2 Slope"),
                ],
                imageSystemName: "bolt.fill",
                funFact: "The first laser was built in 1960 using a synthetic ruby crystal."
            ),

            LegoProject(
                name: "Battle Axe",
                description: "A double-headed battle axe worthy of a dwarven warrior.",
                difficulty: .beginner,
                category: .weapon,
                estimatedTime: "8 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Use the 1×6 plate as the handle", piecesUsed: "1× 1×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Attach slopes on each side as the axe heads", piecesUsed: "2× 2×2 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Add a 1×2 plate at the base of the handle", piecesUsed: "1× 1×2 Plate"),
                ],
                imageSystemName: "shield.fill",
                funFact: "Viking battle axes could have heads up to 18 inches long."
            ),

            LegoProject(
                name: "Crossbow",
                description: "A medieval crossbow with stirrup and bolt groove.",
                difficulty: .medium,
                category: .weapon,
                estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Lay the 1×8 plate as the tiller (stock)", piecesUsed: "1× 1×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Attach 1×4 plates at the front forming the prod (bow)", piecesUsed: "2× 1×4 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Add slopes for the curved bow tips", piecesUsed: "2× 1×2 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Place 1×1 bricks as the trigger mechanism", piecesUsed: "2× 1×1 Brick"),
                ],
                imageSystemName: "scope",
                funFact: "Medieval crossbows could penetrate plate armor at close range."
            ),

            LegoProject(
                name: "Warhammer",
                description: "A hefty warhammer with a spiked head. Great for display.",
                difficulty: .beginner,
                category: .weapon,
                estimatedTime: "8 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Use the 1×6 plate as the shaft", piecesUsed: "1× 1×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Place the 2×2 brick at the top as the hammer head", piecesUsed: "1× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add 1×1 bricks on sides as spikes", piecesUsed: "2× 1×1 Brick"),
                ],
                imageSystemName: "hammer.fill",
                funFact: "Warhammers became popular because they could dent armor that swords couldn't cut."
            ),

            LegoProject(
                name: "Trident",
                description: "A three-pronged trident fit for Poseidon himself.",
                difficulty: .easy,
                category: .weapon,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 3, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .blue, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Use the 1×8 plate as the shaft", piecesUsed: "1× 1×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Attach three 1×4 plates at the top as prongs", piecesUsed: "3× 1×4 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Add 1×2 brick as the grip wrap", piecesUsed: "1× 1×2 Brick"),
                ],
                imageSystemName: "wand.and.stars",
                funFact: "Tridents were historically used more for fishing than for combat."
            ),

            LegoProject(
                name: "Magic Staff",
                description: "A wizard's staff with a glowing crystal on top.",
                difficulty: .easy,
                category: .weapon,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .transparent, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Use the 1×8 plate as the staff shaft", piecesUsed: "1× 1×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add slopes as the head frame", piecesUsed: "2× 1×2 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Place the transparent 1×1 brick as the crystal", piecesUsed: "1× 1×1 Brick"),
                ],
                imageSystemName: "wand.and.stars",
                funFact: "The word 'wizard' comes from the Middle English 'wysard' meaning 'wise man'."
            ),

            LegoProject(
                name: "Siege Tower",
                description: "A tall siege tower with a drop bridge and ladder.",
                difficulty: .expert,
                category: .weapon,
                estimatedTime: "45 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .brown, quantity: 12, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 8, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 3, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the wheeled base from 6×6 plates", piecesUsed: "2× 6×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add wheels on each corner", piecesUsed: "4× Wheel"),
                    BuildStep(stepNumber: 3, instruction: "Build up walls with 1×6 bricks, leaving the front open", piecesUsed: "12× 1×6 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add floors at intervals using 4×6 plates", piecesUsed: "3× 4×6 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Build the drop bridge at the top with 1×4 bricks", piecesUsed: "8× 1×4 Brick"),
                ],
                imageSystemName: "building.columns.fill",
                funFact: "Medieval siege towers could be over 40 feet tall and take weeks to construct."
            ),

            LegoProject(
                name: "Shield Wall Display",
                description: "A display stand with three different shields — round, kite, and heater.",
                difficulty: .medium,
                category: .weapon,
                estimatedTime: "25 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 8, heightUnits: 1), colorPreference: .darkGray, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .red, quantity: 6, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .blue, quantity: 4, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 4, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .darkGray, quantity: 6, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the display base with the 6×8 plate", piecesUsed: "1× 6×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build three shield stands using 1×2 bricks", piecesUsed: "6× 1×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Create round shield from 2×2 plates and slopes", piecesUsed: "2× 2×2 Plate, 2× 2×2 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Create kite shield from 2×4 plates and slopes", piecesUsed: "2× 2×4 Plate, 2× 2×2 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Create heater shield from remaining plates", piecesUsed: "4× 2×2 Plate, 2× 2×4 Plate"),
                ],
                imageSystemName: "shield.fill",
                funFact: "The kite shield was developed by the Normans and was famously depicted in the Bayeux Tapestry."
            ),

            LegoProject(
                name: "Ballista",
                description: "A Roman-style bolt thrower with torsion arms.",
                difficulty: .hard,
                category: .weapon,
                estimatedTime: "30 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the frame on the 4×6 plate", piecesUsed: "1× 4×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add 1×4 brick uprights on each side", piecesUsed: "4× 1×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Mount Technic beams as the torsion arms", piecesUsed: "2× Technic 1×6"),
                    BuildStep(stepNumber: 4, instruction: "Add the bolt rail with the 1×6 plate", piecesUsed: "1× 1×6 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Add optional wheels", piecesUsed: "2× Wheel"),
                ],
                imageSystemName: "scope",
                funFact: "Roman ballistae could launch bolts with enough force to pin two soldiers together."
            ),

            LegoProject(
                name: "Cannon Fortress",
                description: "A small fortress wall with two mounted cannons.",
                difficulty: .expert,
                category: .weapon,
                estimatedTime: "50 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .gray, quantity: 8, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .darkGray, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .darkGray, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Lay the 8×8 plate as the foundation", piecesUsed: "1× 8×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build walls with 1×8 bricks, four rows high", piecesUsed: "8× 1×8 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add crenellations with slopes", piecesUsed: "4× 1×2 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Build two cannons from 2×4 and 2×2 dark gray bricks", piecesUsed: "4× 2×4 Brick, 4× 2×2 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Mount cannons on wheeled carriages", piecesUsed: "2× 2×4 Plate, 4× Wheel"),
                ],
                imageSystemName: "building.columns.fill",
                funFact: "Star forts with angled walls were designed specifically to deflect cannonballs."
            ),

            // MORE VEHICLES
            LegoProject(
                name: "Formula 1 Car",
                description: "A low-profile F1 racer with front and rear wings.",
                difficulty: .hard,
                category: .vehicle,
                estimatedTime: "30 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 1), colorPreference: .red, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the nose cone with 2×4 plates and slopes", piecesUsed: "1× 2×4 Plate, 1× 2×4 Slope"),
                    BuildStep(stepNumber: 2, instruction: "Extend the body with the 2×8 plate", piecesUsed: "1× 2×8 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Add front wing from 4×4 plate", piecesUsed: "1× 4×4 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Add rear wing from 4×4 plate and slope", piecesUsed: "1× 4×4 Plate, 1× 2×4 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Mount all four wheels", piecesUsed: "4× Wheel"),
                    BuildStep(stepNumber: 6, instruction: "Add windshield tile to cockpit", piecesUsed: "1× 1×2 Tile"),
                ],
                imageSystemName: "car.fill",
                funFact: "An F1 car generates enough downforce to drive upside-down on a ceiling at speed."
            ),

            LegoProject(
                name: "Fire Truck",
                description: "A classic red fire truck with an extending ladder.",
                difficulty: .medium,
                category: .vehicle,
                estimatedTime: "25 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 8, heightUnits: 1), colorPreference: .red, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .transparent, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the chassis on the 4×8 plate", piecesUsed: "1× 4×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add 2×4 bricks for the cab and body", piecesUsed: "4× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build the cab front with 2×2 bricks", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Create the ladder from 1×8 plates", piecesUsed: "2× 1×8 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Add lights and wheels", piecesUsed: "2× 1×1 Tile, 4× Wheel"),
                ],
                imageSystemName: "flame.fill",
                funFact: "The first motorized fire engine was built in 1903 by the Knox Automobile Company."
            ),

            LegoProject(
                name: "Jet Airplane",
                description: "A sleek passenger jet with swept wings and tail.",
                difficulty: .hard,
                category: .vehicle,
                estimatedTime: "35 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 8, heightUnits: 1), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .blue, quantity: 2, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .transparent, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the fuselage from 2×8 bricks", piecesUsed: "2× 2×8 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add wings using 4×8 plates on each side", piecesUsed: "2× 4×8 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Build the nose with 2×4 slopes", piecesUsed: "2× 2×4 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Add engines under wings with 2×4 blue bricks", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Add window tiles along the fuselage", piecesUsed: "4× 1×4 Tile"),
                ],
                imageSystemName: "airplane",
                funFact: "Commercial jets cruise at about 35,000 feet where the air temperature is -60°F."
            ),

            LegoProject(
                name: "Pirate Ship",
                description: "A swashbuckling pirate vessel with mast and sails.",
                difficulty: .expert,
                category: .vehicle,
                estimatedTime: "60 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 12, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .brown, quantity: 8, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 6, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 12, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .white, quantity: 3, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the hull base with the 6×12 plate", piecesUsed: "1× 6×12 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build the hull walls with 1×6 and 1×4 bricks", piecesUsed: "8× 1×6 Brick, 6× 1×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Shape the bow and stern with slopes", piecesUsed: "4× 2×4 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Build the mast from stacked 1×1 bricks", piecesUsed: "12× 1×1 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Add the sails using white 4×4 plates", piecesUsed: "3× 4×4 Plate"),
                ],
                imageSystemName: "sailboat.fill",
                funFact: "Blackbeard's ship, Queen Anne's Revenge, was originally a French slave ship he captured."
            ),

            LegoProject(
                name: "Tow Truck",
                description: "A sturdy tow truck with a hook and boom arm.",
                difficulty: .medium,
                category: .vehicle,
                estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .yellow, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .black, quantity: 1, flexible: false),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the chassis with the 4×6 plate", piecesUsed: "1× 4×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build the cab from 2×4 and 2×2 yellow bricks", piecesUsed: "2× 2×4 Brick, 2× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add the boom arm with Technic beam", piecesUsed: "1× Technic 1×6"),
                    BuildStep(stepNumber: 4, instruction: "Attach 1×1 brick as the hook", piecesUsed: "1× 1×1 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Mount wheels", piecesUsed: "4× Wheel"),
                ],
                imageSystemName: "truck.box.fill",
                funFact: "The first tow truck was invented in 1916 by Ernest Holmes in Chattanooga, Tennessee."
            ),

            LegoProject(
                name: "Submarine",
                description: "A yellow submarine with periscope and propeller.",
                difficulty: .medium,
                category: .vehicle,
                estimatedTime: "25 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 1, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the hull from 2×6 and 2×4 yellow bricks", piecesUsed: "2× 2×6 Brick, 2× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add slopes on each end for the bow and stern", piecesUsed: "2× 2×2 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Place the transparent tile as the viewport", piecesUsed: "1× 2×2 Tile"),
                    BuildStep(stepNumber: 4, instruction: "Build the conning tower with 1×1 gray bricks", piecesUsed: "2× 1×1 Brick"),
                ],
                imageSystemName: "water.waves",
                funFact: "The Beatles' Yellow Submarine was inspired by a children's song idea from Donovan."
            ),

            // MORE BUILDINGS
            LegoProject(
                name: "Fire Station",
                description: "A two-story fire station with opening garage doors.",
                difficulty: .hard,
                category: .building,
                estimatedTime: "40 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .red, quantity: 12, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 6, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .transparent, quantity: 4, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the foundation on 8×8 gray plate", piecesUsed: "1× 8×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build ground floor walls with 1×8 red bricks", piecesUsed: "6× 1×8 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add the second floor using 8×8 white plate", piecesUsed: "1× 8×8 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Build second story walls", piecesUsed: "6× 1×8 Brick, 6× 2×4 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Add windows", piecesUsed: "4× 1×4 Tile"),
                    BuildStep(stepNumber: 6, instruction: "Build the peaked roof with slopes", piecesUsed: "4× 2×4 Slope"),
                ],
                imageSystemName: "building.2.fill",
                funFact: "The oldest active fire station in the US is in Alexandria, Virginia, built in 1774."
            ),

            LegoProject(
                name: "Medieval Tower",
                description: "A round castle tower with battlements and arrow slits.",
                difficulty: .hard,
                category: .building,
                estimatedTime: "35 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 6, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 16, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 12, flexible: true),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 8, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the base on the 6×6 plate", piecesUsed: "1× 6×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build circular walls using 1×4 and 1×2 bricks in a square pattern", piecesUsed: "16× 1×4 Brick, 12× 1×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add floor plate every few rows", piecesUsed: "2× 4×4 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Build crenellations at the top with slopes", piecesUsed: "8× 1×2 Slope"),
                ],
                imageSystemName: "building.columns.fill",
                funFact: "The Tower of London has served as a palace, prison, zoo, and jewel house."
            ),

            LegoProject(
                name: "Log Cabin",
                description: "A rustic log cabin with chimney and front porch.",
                difficulty: .medium,
                category: .building,
                estimatedTime: "25 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 8, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .brown, quantity: 12, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 8, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the foundation on the green 6×8 plate", piecesUsed: "1× 6×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Lay brown bricks in alternating log-cabin pattern", piecesUsed: "12× 1×6 Brick, 8× 1×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build the peaked roof with slopes", piecesUsed: "4× 2×4 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Add chimney with red bricks", piecesUsed: "4× 1×2 Brick"),
                ],
                imageSystemName: "house.fill",
                funFact: "Abraham Lincoln was born in a one-room log cabin in Hodgenville, Kentucky."
            ),

            LegoProject(
                name: "Church",
                description: "A small chapel with a steeple, stained glass, and double doors.",
                difficulty: .expert,
                category: .building,
                estimatedTime: "45 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 12, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .white, quantity: 12, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 6, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 6, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 8, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Lay the 8×12 plate as the foundation", piecesUsed: "1× 8×12 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build the nave walls with white bricks", piecesUsed: "12× 1×8 Brick, 6× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add stained glass windows with transparent tiles", piecesUsed: "6× 1×2 Tile"),
                    BuildStep(stepNumber: 4, instruction: "Build the gabled roof with 2×6 slopes", piecesUsed: "4× 2×6 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Build the steeple tower from 2×2 bricks", piecesUsed: "8× 2×2 Brick"),
                    BuildStep(stepNumber: 6, instruction: "Cap the steeple with 1×2 slopes", piecesUsed: "4× 1×2 Slope"),
                ],
                imageSystemName: "building.columns.fill",
                funFact: "The oldest known church building dates to the early 200s AD in Dura-Europos, Syria."
            ),

            LegoProject(
                name: "Barn",
                description: "A classic red barn with big sliding doors and a hay loft.",
                difficulty: .medium,
                category: .building,
                estimatedTime: "25 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 6, studsLong: 8, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 8, heightUnits: 3), colorPreference: .red, quantity: 8, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the foundation on green 6×8 plate", piecesUsed: "1× 6×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build the walls with red bricks", piecesUsed: "8× 1×8 Brick, 4× 1×6 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add the hay loft floor with brown plate", piecesUsed: "1× 4×6 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Build the gambrel roof with slopes", piecesUsed: "4× 2×4 Slope"),
                ],
                imageSystemName: "house.fill",
                funFact: "Barns are traditionally red because farmers used rust-based paint, which was cheap and killed fungi."
            ),

            // MORE ANIMALS
            LegoProject(
                name: "Elephant",
                description: "A blocky elephant with trunk, tusks, and big ears.",
                difficulty: .medium,
                category: .animal,
                estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: true),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the body from the 4×6 brick", piecesUsed: "1× 4×6 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add four 2×2 bricks as legs", piecesUsed: "4× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build the head with 2×4 bricks", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add ears with 2×4 plates on each side", piecesUsed: "2× 2×4 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Build the trunk with 1×4 bricks and a slope", piecesUsed: "2× 1×4 Brick, 2× 2×2 Slope"),
                    BuildStep(stepNumber: 6, instruction: "Add white 1×1 bricks as tusks", piecesUsed: "2× 1×1 Brick"),
                ],
                imageSystemName: "tortoise.fill",
                funFact: "Elephants are the only animals that can't jump!"
            ),

            LegoProject(
                name: "Owl",
                description: "A wise owl perched on a branch with big round eyes.",
                difficulty: .easy,
                category: .animal,
                estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .yellow, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the body from 2×4 brown bricks", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add the head with 2×2 bricks", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add slopes as ear tufts", piecesUsed: "2× 2×2 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Place yellow 1×1 bricks as eyes", piecesUsed: "2× 1×1 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Add the branch perch with 1×4 plate", piecesUsed: "1× 1×4 Plate"),
                ],
                imageSystemName: "bird.fill",
                funFact: "Owls can rotate their heads up to 270 degrees."
            ),

            LegoProject(
                name: "Crocodile",
                description: "A snapping crocodile with a long body and toothy jaw.",
                difficulty: .medium,
                category: .animal,
                estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 1), colorPreference: .green, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .green, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .white, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the long body from two 2×8 plates", piecesUsed: "2× 2×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add bricks on top for body volume", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build the jaws from 1×2 bricks", piecesUsed: "4× 1×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add white teeth with 1×1 bricks", piecesUsed: "4× 1×1 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Taper the tail with slopes", piecesUsed: "2× 1×2 Slope"),
                ],
                imageSystemName: "tortoise.fill",
                funFact: "Crocodiles have the strongest bite of any living animal — over 3,700 PSI."
            ),

            LegoProject(
                name: "Parrot",
                description: "A colorful tropical parrot with spread wings.",
                difficulty: .easy,
                category: .animal,
                estimatedTime: "12 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .blue, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .yellow, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the body from red 2×2 bricks", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add green 2×2 bricks for the belly and wings", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add blue slopes as wing tips", piecesUsed: "2× 2×2 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Place yellow 1×1 as the beak", piecesUsed: "1× 1×1 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Add black 1×1 bricks as eyes", piecesUsed: "2× 1×1 Brick"),
                ],
                imageSystemName: "bird.fill",
                funFact: "Some parrots can live over 80 years, making them one of the longest-lived bird species."
            ),

            // MORE ROBOTS
            LegoProject(
                name: "Transformer Bot",
                description: "A robot that can be reconfigured into a vehicle shape.",
                difficulty: .hard,
                category: .robot,
                estimatedTime: "35 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .blue, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .blue, quantity: 6, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .blue, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .transparent, quantity: 2, flexible: true),
                    RequiredPiece(category: .wheel, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the torso from 2×4 blue bricks", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add 2×2 bricks for the legs (two each)", piecesUsed: "4× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Use Technic beams for articulated arms", piecesUsed: "4× Technic 1×4"),
                    BuildStep(stepNumber: 4, instruction: "Build the head from 2×2 bricks and slopes", piecesUsed: "2× 2×2 Brick, 4× 2×2 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Add transparent tiles as eyes", piecesUsed: "2× 1×1 Tile"),
                    BuildStep(stepNumber: 6, instruction: "Attach 2×6 plates as shoulder armor / vehicle hood", piecesUsed: "2× 2×6 Plate"),
                    BuildStep(stepNumber: 7, instruction: "Add remaining 2×4 bricks and wheels (can reconfigure to car mode)", piecesUsed: "2× 2×4 Brick, 4× Wheel"),
                ],
                imageSystemName: "cpu",
                funFact: "The original Transformers toys were licensed from two Japanese toy lines: Diaclone and Micro Change."
            ),

            LegoProject(
                name: "Walking Robot",
                description: "A bipedal robot with articulated legs and grabber claws.",
                difficulty: .medium,
                category: .robot,
                estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 4, flexible: false),
                    RequiredPiece(category: .technic, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .red, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the body from 2×4 white bricks", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Build legs from 2×2 bricks stacked", piecesUsed: "4× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add Technic beams as articulated arms", piecesUsed: "4× Technic 1×4"),
                    BuildStep(stepNumber: 4, instruction: "Add 2×4 plates as feet", piecesUsed: "2× 2×4 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Place red tiles as sensor eyes", piecesUsed: "2× 1×1 Tile"),
                ],
                imageSystemName: "cpu",
                funFact: "ASIMO by Honda was one of the first humanoid robots that could walk smoothly — debuted in 2000."
            ),

            // MORE SPACESHIPS
            LegoProject(
                name: "X-Wing Style Fighter",
                description: "A four-winged space fighter in attack position.",
                difficulty: .hard,
                category: .spaceship,
                estimatedTime: "35 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 3), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 1), colorPreference: .white, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 1, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the fuselage from 2×8 brick", piecesUsed: "1× 2×8 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add nose cone with 2×4 slopes", piecesUsed: "2× 2×4 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Attach four 2×8 plate wings in X formation", piecesUsed: "4× 2×8 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Add red 1×1 bricks as laser cannons on wing tips", piecesUsed: "4× 1×1 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Build engines from 2×4 gray bricks at rear", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 6, instruction: "Add transparent cockpit tile", piecesUsed: "1× 1×2 Tile"),
                ],
                imageSystemName: "airplane",
                funFact: "The original X-Wing model used in Star Wars was only about 3 feet long."
            ),

            LegoProject(
                name: "Lunar Lander",
                description: "An Apollo-style lunar module with landing legs and antenna.",
                difficulty: .medium,
                category: .spaceship,
                estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 4, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .transparent, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the descent stage from 4×4 plates", piecesUsed: "2× 4×4 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Add body with 2×4 and 2×2 gray bricks", piecesUsed: "2× 2×4 Brick, 2× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Attach four 1×4 plates as landing legs, angled outward", piecesUsed: "4× 1×4 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Add yellow slopes as gold foil panels", piecesUsed: "4× 2×2 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Place transparent tile on top as antenna", piecesUsed: "1× 1×1 Tile"),
                ],
                imageSystemName: "moon.fill",
                funFact: "The Apollo 11 Lunar Module had only 25 seconds of fuel remaining when it landed."
            ),

            // MORE CHARACTERS
            LegoProject(
                name: "Samurai Warrior",
                description: "A proud samurai with layered armor and a katana.",
                difficulty: .hard,
                category: .character,
                estimatedTime: "30 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 4, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 1), colorPreference: .gray, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build legs from black 2×2 bricks", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Build the torso with red 2×4 bricks", piecesUsed: "2× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add layered armor shoulders with red slopes", piecesUsed: "4× 2×2 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Build the head with red 2×2 bricks", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Add helmet crest with remaining 2×2 bricks and slopes", piecesUsed: "2× 2×2 Brick, 2× 2×4 Plate"),
                    BuildStep(stepNumber: 6, instruction: "Build the katana from 1×6 plate", piecesUsed: "1× 1×6 Plate"),
                ],
                imageSystemName: "figure.martial.arts",
                funFact: "The samurai class existed for nearly 700 years, from the 12th to 19th century."
            ),

            LegoProject(
                name: "Astronaut",
                description: "A space-suited astronaut with helmet visor and backpack.",
                difficulty: .easy,
                category: .character,
                estimatedTime: "12 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 3, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1), colorPreference: .transparent, quantity: 1, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the legs from white 2×4 brick", piecesUsed: "1× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Build the torso from white 2×4 brick", piecesUsed: "1× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build the helmet from 2×2 white bricks", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add the visor with transparent tile", piecesUsed: "1× 1×2 Tile"),
                    BuildStep(stepNumber: 5, instruction: "Add backpack from gray bricks and remaining 2×2", piecesUsed: "2× 1×2 Brick, 1× 2×2 Brick"),
                ],
                imageSystemName: "figure.wave",
                funFact: "NASA spacesuits cost approximately $12 million each to produce."
            ),

            // MORE DECORATIONS
            LegoProject(
                name: "Christmas Tree",
                description: "A festive Christmas tree with a star topper and presents underneath.",
                difficulty: .easy,
                category: .decoration,
                estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .green, quantity: 4, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .yellow, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .red, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the trunk from brown 1×2 bricks", piecesUsed: "2× 1×2 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Build the bottom tier with 2×4 green slopes", piecesUsed: "2× 2×4 Slope"),
                    BuildStep(stepNumber: 3, instruction: "Build the middle tier with remaining 2×4 slopes", piecesUsed: "2× 2×4 Slope"),
                    BuildStep(stepNumber: 4, instruction: "Build the top tier with 2×2 slopes", piecesUsed: "2× 2×2 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Add yellow star on top and red presents at base", piecesUsed: "1× 1×1 Yellow, 2× 1×1 Red"),
                ],
                imageSystemName: "gift.fill",
                funFact: "The tradition of decorating Christmas trees started in Germany in the 16th century."
            ),

            LegoProject(
                name: "Jack-o'-Lantern",
                description: "A spooky carved pumpkin for Halloween decoration.",
                difficulty: .beginner,
                category: .decoration,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 3), colorPreference: .orange, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .orange, quantity: 2, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 3, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the pumpkin body from orange bricks", piecesUsed: "1× 4×4 Brick, 2× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Leave gaps or overlay black 1×1 bricks for the face", piecesUsed: "3× 1×1 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add green slope as the stem", piecesUsed: "1× 1×2 Slope"),
                ],
                imageSystemName: "moon.fill",
                funFact: "The tradition of jack-o'-lanterns originated in Ireland using carved turnips, not pumpkins."
            ),

            // MORE NATURE
            LegoProject(
                name: "Sunflower",
                description: "A tall sunflower with layered petals and a brown center.",
                difficulty: .easy,
                category: .nature,
                estimatedTime: "12 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .green, quantity: 6, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 8, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .green, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the stem by stacking green 1×1 bricks", piecesUsed: "6× 1×1 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add green plate leaves", piecesUsed: "2× 2×4 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Place brown 2×2 plate as the flower center", piecesUsed: "1× 2×2 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Surround with yellow slopes as petals", piecesUsed: "8× 1×2 Slope"),
                ],
                imageSystemName: "leaf.fill",
                funFact: "Sunflowers can grow up to 12 feet tall and their heads track the sun across the sky."
            ),

            LegoProject(
                name: "Waterfall Scene",
                description: "A miniature cliff with a cascading waterfall and pool.",
                difficulty: .hard,
                category: .nature,
                estimatedTime: "30 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 6, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .green, quantity: 4, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .transparent, quantity: 3, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1), colorPreference: .blue, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the base on the 8×8 green plate", piecesUsed: "1× 8×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build the cliff face from gray bricks", piecesUsed: "6× 2×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add foliage with green bricks on top", piecesUsed: "4× 2×4 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Place transparent tiles cascading down for the waterfall", piecesUsed: "3× 2×4 Tile"),
                    BuildStep(stepNumber: 5, instruction: "Add the blue pool at the base", piecesUsed: "1× 4×4 Plate"),
                ],
                imageSystemName: "water.waves",
                funFact: "Angel Falls in Venezuela is the world's highest waterfall at 3,212 feet."
            ),

            // MORE GADGETS
            LegoProject(
                name: "Telescope",
                description: "A small telescope on a tripod stand for stargazing.",
                difficulty: .easy,
                category: .gadget,
                estimatedTime: "12 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .transparent, quantity: 1, flexible: true),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 3, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1), colorPreference: .black, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the tube from stacked 1×4 gray bricks", piecesUsed: "2× 1×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add eyepiece with 1×2 brick", piecesUsed: "1× 1×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Place transparent tile as the lens", piecesUsed: "1× 1×1 Tile"),
                    BuildStep(stepNumber: 4, instruction: "Build tripod legs from three 1×1 black bricks", piecesUsed: "3× 1×1 Brick"),
                    BuildStep(stepNumber: 5, instruction: "Mount on 2×2 plate base", piecesUsed: "1× 2×2 Plate"),
                ],
                imageSystemName: "scope",
                funFact: "Galileo's telescope had only 20× magnification — less than modern binoculars."
            ),

            LegoProject(
                name: "Treasure Chest",
                description: "A pirate's treasure chest with hinged lid and gold coins inside.",
                difficulty: .beginner,
                category: .gadget,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .brown, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .yellow, quantity: 4, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the base from 2×4 bricks", piecesUsed: "1× 2×4 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Add sides with 2×2 bricks", piecesUsed: "2× 2×2 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build the back wall with remaining 2×4 brick", piecesUsed: "1× 2×4 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add the lid plate and rounded slope", piecesUsed: "1× 2×4 Plate, 1× 2×4 Slope"),
                    BuildStep(stepNumber: 5, instruction: "Drop yellow tiles inside as gold coins", piecesUsed: "4× 1×1 Tile"),
                ],
                imageSystemName: "shippingbox.fill",
                funFact: "The largest real treasure ever found was the Nuestra Señora de Atocha, worth over $450 million."
            ),

            // MORE FURNITURE
            LegoProject(
                name: "Grand Piano",
                description: "A mini grand piano with keyboard and propped-up lid.",
                difficulty: .hard,
                category: .furniture,
                estimatedTime: "30 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .black, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 3), colorPreference: .black, quantity: 4, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .black, quantity: 2, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .white, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 3, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3), colorPreference: .black, quantity: 1, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build the base from 4×6 black plates", piecesUsed: "2× 4×6 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build the body walls from 1×6 black bricks", piecesUsed: "4× 1×6 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Build three legs from 1×1 black bricks stacked", piecesUsed: "3× 1×1 Brick, 2× 1×4 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Add white tile keyboard", piecesUsed: "2× 1×4 Tile"),
                    BuildStep(stepNumber: 5, instruction: "Add the propped lid with slope", piecesUsed: "1× 2×4 Slope"),
                ],
                imageSystemName: "pianokeys",
                funFact: "A grand piano has over 12,000 individual parts and about 230 strings."
            ),

            LegoProject(
                name: "Bunk Bed",
                description: "A kids' bunk bed with ladder and pillows.",
                difficulty: .easy,
                category: .furniture,
                estimatedTime: "15 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .brown, quantity: 8, flexible: false),
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1), colorPreference: .brown, quantity: 2, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1), colorPreference: .white, quantity: 2, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Build four corner posts from 1×1 bricks, two studs high each", piecesUsed: "8× 1×1 Brick"),
                    BuildStep(stepNumber: 2, instruction: "Place lower bed frame (4×6 plate)", piecesUsed: "1× 4×6 Plate"),
                    BuildStep(stepNumber: 3, instruction: "Place upper bed frame (4×6 plate)", piecesUsed: "1× 4×6 Plate"),
                    BuildStep(stepNumber: 4, instruction: "Add ladder from 1×4 plates", piecesUsed: "2× 1×4 Plate"),
                    BuildStep(stepNumber: 5, instruction: "Add white tiles as pillows", piecesUsed: "2× 2×4 Tile"),
                ],
                imageSystemName: "bed.double.fill",
                funFact: "Bunk beds became popular in the navy because of limited space on ships."
            ),

            // MORE GAMES
            LegoProject(
                name: "Chess Set (Simple)",
                description: "A simplified chess board with two types of piece — tall kings and short pawns.",
                difficulty: .expert,
                category: .game,
                estimatedTime: "60 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .black, quantity: 32, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .white, quantity: 16, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3), colorPreference: .black, quantity: 16, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place 8×8 white plate as the board", piecesUsed: "1× 8×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Lay alternating black tiles in checkerboard pattern", piecesUsed: "32× 1×1 Black Tile"),
                    BuildStep(stepNumber: 3, instruction: "Build 16 white pieces from 1×1 bricks (tall for royals, short for pawns)", piecesUsed: "16× 1×1 White Brick"),
                    BuildStep(stepNumber: 4, instruction: "Build 16 black pieces similarly", piecesUsed: "16× 1×1 Black Brick"),
                ],
                imageSystemName: "checkerboard.rectangle",
                funFact: "The number of possible chess games is greater than the number of atoms in the observable universe."
            ),

            LegoProject(
                name: "Maze Puzzle",
                description: "A flat tile-based maze that you navigate with a small ball or marble.",
                difficulty: .medium,
                category: .game,
                estimatedTime: "20 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3), colorPreference: .gray, quantity: 12, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3), colorPreference: .gray, quantity: 8, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .red, quantity: 1, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the 8×8 plate as the maze floor", piecesUsed: "1× 8×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Build outer walls with 1×4 bricks along all edges", piecesUsed: "8× 1×4 Brick"),
                    BuildStep(stepNumber: 3, instruction: "Add internal maze walls with remaining 1×4 and 1×2 bricks", piecesUsed: "4× 1×4 Brick, 8× 1×2 Brick"),
                    BuildStep(stepNumber: 4, instruction: "Mark the exit with the red tile", piecesUsed: "1× 1×1 Tile"),
                ],
                imageSystemName: "square.grid.3x3",
                funFact: "The world's largest maze is the Masone Labyrinth in Italy, covering 17 acres."
            ),

            // MORE ART
            LegoProject(
                name: "Brick Mosaic Portrait",
                description: "An 8×8 pixel art portrait using colored plates.",
                difficulty: .medium,
                category: .art,
                estimatedTime: "25 min",
                requiredPieces: [
                    RequiredPiece(category: .plate, dimensions: PieceDimensions(studsWide: 8, studsLong: 8, heightUnits: 1), colorPreference: .white, quantity: 1, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .tan, quantity: 24, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .brown, quantity: 16, flexible: true),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .black, quantity: 12, flexible: false),
                    RequiredPiece(category: .tile, dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1), colorPreference: .white, quantity: 12, flexible: true),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place the 8×8 white plate as the canvas", piecesUsed: "1× 8×8 Plate"),
                    BuildStep(stepNumber: 2, instruction: "Fill in the face area with tan tiles", piecesUsed: "24× Tan Tile"),
                    BuildStep(stepNumber: 3, instruction: "Add hair with brown tiles", piecesUsed: "16× Brown Tile"),
                    BuildStep(stepNumber: 4, instruction: "Place eyes and mouth with black tiles", piecesUsed: "12× Black Tile"),
                    BuildStep(stepNumber: 5, instruction: "Fill background with white tiles", piecesUsed: "12× White Tile"),
                ],
                imageSystemName: "paintpalette.fill",
                funFact: "LEGO Art sets can contain over 4,000 pieces for a single 48×48 stud mosaic."
            ),

            LegoProject(
                name: "Mini Rainbow",
                description: "A small freestanding rainbow arch with a cloud at each end.",
                difficulty: .beginner,
                category: .art,
                estimatedTime: "10 min",
                requiredPieces: [
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .red, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .orange, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .yellow, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .green, quantity: 1, flexible: false),
                    RequiredPiece(category: .slope, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .blue, quantity: 1, flexible: false),
                    RequiredPiece(category: .brick, dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3), colorPreference: .white, quantity: 2, flexible: false),
                ],
                instructions: [
                    BuildStep(stepNumber: 1, instruction: "Place white clouds (2×2 bricks) at each end", piecesUsed: "2× 2×2 White Brick"),
                    BuildStep(stepNumber: 2, instruction: "Arch the rainbow slopes from one cloud to the other: red, orange, yellow, green, blue", piecesUsed: "5× 2×2 Slope"),
                ],
                imageSystemName: "paintpalette.fill",
                funFact: "Rainbows are actually full circles — we only see an arc because the ground is in the way."
            ),
        ]
    }
}
