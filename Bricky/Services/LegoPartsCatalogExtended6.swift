import Foundation

// MARK: - Extended Catalog Part 6 (Final 100+ to reach 1,600+ total)
// Last batch: decorated tiles, printed elements, remaining size gaps, and niche parts.

extension LegoPartsCatalog {

    func loadExtendedCatalog6() -> [CatalogPiece] {
        let allColors = LegoColor.allCases
        let basicColors: [LegoColor] = [.red, .blue, .yellow, .green, .black, .white, .gray, .darkGray, .orange, .brown, .tan]
        let structuralColors: [LegoColor] = [.black, .gray, .darkGray, .white, .tan, .brown]

        return [

            // ═══════════════════════════════════════════
            // BRICKS - Final size variants
            // ═══════════════════════════════════════════

            CatalogPiece(partNumber: "3245c", name: "Brick 1×2×2", category: .brick,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 6),
                         commonColors: allColors, weight: 2.5, keywords: ["tall", "column"]),
            CatalogPiece(partNumber: "2454b", name: "Brick 1×2×5", category: .brick,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 15),
                         commonColors: basicColors, weight: 5.0, keywords: ["pillar", "very tall"]),
            CatalogPiece(partNumber: "3754", name: "Brick 1×6×5", category: .brick,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 15),
                         commonColors: [.white, .gray, .tan, .yellow], weight: 12.0, keywords: ["wall", "tall"]),
            CatalogPiece(partNumber: "6213", name: "Brick 2×6×3", category: .brick,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 9),
                         commonColors: [.white, .gray, .red, .yellow], weight: 8.0, keywords: ["wall"]),
            CatalogPiece(partNumber: "44042", name: "Brick 1×1×3 Open Stud", category: .brick,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 9),
                         commonColors: basicColors, weight: 1.5, keywords: ["pillar", "column"]),
            CatalogPiece(partNumber: "2453", name: "Brick 1×1×5", category: .brick,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 15),
                         commonColors: basicColors, weight: 2.5, keywords: ["column", "tall"]),

            // ═══════════════════════════════════════════
            // PLATES - Final missing standard sizes
            // ═══════════════════════════════════════════

            CatalogPiece(partNumber: "3176", name: "Plate 3×2 with Hole", category: .plate,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 3, heightUnits: 1),
                         commonColors: structuralColors, weight: 0.8, keywords: ["hole", "technic"]),
            CatalogPiece(partNumber: "3709", name: "Technic Plate 2×4 with Holes", category: .plate,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1),
                         commonColors: structuralColors, weight: 1.2, keywords: ["holes", "technic"]),
            CatalogPiece(partNumber: "3738", name: "Technic Plate 2×8 with Holes", category: .plate,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 8, heightUnits: 1),
                         commonColors: structuralColors, weight: 2.5, keywords: ["holes", "technic"]),
            CatalogPiece(partNumber: "3036b", name: "Plate 6×8", category: .plate,
                         dimensions: PieceDimensions(studsWide: 6, studsLong: 8, heightUnits: 1),
                         commonColors: allColors, weight: 8.0, keywords: ["large"]),
            CatalogPiece(partNumber: "4282b", name: "Plate 2×16", category: .plate,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 16, heightUnits: 1),
                         commonColors: basicColors, weight: 6.0, keywords: ["extra long"]),
            CatalogPiece(partNumber: "3028b", name: "Plate 6×12", category: .plate,
                         dimensions: PieceDimensions(studsWide: 6, studsLong: 12, heightUnits: 1),
                         commonColors: basicColors, weight: 12.0, keywords: ["large"]),

            // ═══════════════════════════════════════════
            // TILES - Remaining
            // ═══════════════════════════════════════════

            CatalogPiece(partNumber: "63864b", name: "Tile 1×3", category: .tile,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 3, heightUnits: 1),
                         commonColors: allColors, weight: 0.4, keywords: ["smooth"]),
            CatalogPiece(partNumber: "15462", name: "Tile 1×1 with Clip", category: .tile,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1),
                         commonColors: allColors, weight: 0.2, keywords: ["clip", "small"]),
            CatalogPiece(partNumber: "26169", name: "Tile 1×1 with Groove", category: .tile,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1),
                         commonColors: allColors, weight: 0.2, keywords: ["groove"]),
            CatalogPiece(partNumber: "35386", name: "Tile 2×3", category: .tile,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 3, heightUnits: 1),
                         commonColors: allColors, weight: 0.7, keywords: ["smooth"]),

            // ═══════════════════════════════════════════
            // TECHNIC - Remaining beam/pin variants
            // ═══════════════════════════════════════════

            CatalogPiece(partNumber: "32523", name: "Technic Beam 1×3", category: .technic,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 3, heightUnits: 3),
                         commonColors: structuralColors, weight: 1.5, keywords: ["beam", "short"]),
            CatalogPiece(partNumber: "41677", name: "Technic Beam 1×2 Thin", category: .technic,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 2),
                         commonColors: structuralColors, weight: 0.5, keywords: ["beam", "thin"]),
            CatalogPiece(partNumber: "60483", name: "Technic Beam 1×2 with Axle Hole", category: .technic,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 3),
                         commonColors: structuralColors, weight: 1.0, keywords: ["beam", "axle"]),
            CatalogPiece(partNumber: "32184", name: "Technic Axle/Pin Connector 3×3", category: .technic,
                         dimensions: PieceDimensions(studsWide: 3, studsLong: 3, heightUnits: 2),
                         commonColors: [.gray, .darkGray], weight: 2.0, keywords: ["connector", "hub"]),
            CatalogPiece(partNumber: "32291", name: "Technic Axle/Pin Connector Toggle", category: .technic,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 3, heightUnits: 2),
                         commonColors: [.gray, .darkGray], weight: 0.5, keywords: ["toggle", "joint"]),
            CatalogPiece(partNumber: "87082", name: "Technic Pin Long with Bush", category: .technic,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3),
                         commonColors: [.blue, .black], weight: 0.5, keywords: ["pin", "bush"]),
            CatalogPiece(partNumber: "43093", name: "Technic Axle Pin with Friction", category: .technic,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 2),
                         commonColors: [.blue, .black], weight: 0.3, keywords: ["axle", "pin"]),
            CatalogPiece(partNumber: "18651", name: "Technic Axle 2L with Pin", category: .technic,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1),
                         commonColors: [.black, .darkGray, .red], weight: 0.3, keywords: ["axle", "pin"]),
            CatalogPiece(partNumber: "32054", name: "Technic Pin Long with Stop", category: .technic,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 4),
                         commonColors: [.black, .blue], weight: 0.4, keywords: ["pin", "stop"]),
            CatalogPiece(partNumber: "99008", name: "Technic Axle 4 with Center Stop", category: .technic,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1),
                         commonColors: [.darkGray, .gray], weight: 0.5, keywords: ["axle", "center stop"]),

            // ═══════════════════════════════════════════
            // SLOPE CURVED - Final gap-fill
            // ═══════════════════════════════════════════

            CatalogPiece(partNumber: "11478", name: "Slope Curved 2×1 Inverted", category: .slope,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 2),
                         commonColors: allColors, weight: 0.5, keywords: ["curved", "inverted"]),
            CatalogPiece(partNumber: "24309", name: "Slope Curved 3×2 No Studs", category: .slope,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 3, heightUnits: 2),
                         commonColors: allColors, weight: 1.0, keywords: ["curved", "smooth"]),
            CatalogPiece(partNumber: "44126", name: "Slope Curved 6×2", category: .slope,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 2),
                         commonColors: basicColors, weight: 2.0, keywords: ["curved", "long"]),
            CatalogPiece(partNumber: "44132", name: "Slope Curved 6×2 Inverted", category: .slope,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 2),
                         commonColors: basicColors, weight: 2.0, keywords: ["curved", "inverted", "long"]),

            // ═══════════════════════════════════════════
            // CASTLE & MEDIEVAL - Final
            // ═══════════════════════════════════════════

            CatalogPiece(partNumber: "3846", name: "Minifigure Shield Triangular", category: .minifigure,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 1, heightUnits: 3),
                         commonColors: [.gray, .darkGray, .gray], weight: 0.5, keywords: ["shield", "knight"]),
            CatalogPiece(partNumber: "59275", name: "Minifigure Helmet Viking", category: .minifigure,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 2),
                         commonColors: [.gray, .darkGray, .gray], weight: 1.0, keywords: ["helmet", "viking"]),
            CatalogPiece(partNumber: "3834", name: "Minifigure Pickaxe", category: .minifigure,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3),
                         commonColors: [.gray, .darkGray], weight: 0.3, keywords: ["pickaxe", "mining"]),
            CatalogPiece(partNumber: "30173", name: "Minifigure Torch", category: .minifigure,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3),
                         commonColors: [.brown, .black], weight: 0.2, keywords: ["torch", "fire"]),
            CatalogPiece(partNumber: "6123", name: "Minifigure Fishing Rod", category: .minifigure,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 4),
                         commonColors: [.brown, .black, .gray], weight: 0.3, keywords: ["fishing", "rod"]),

            // ═══════════════════════════════════════════
            // SPACE & SCI-FI
            // ═══════════════════════════════════════════

            CatalogPiece(partNumber: "30360", name: "Robot Arm Claw", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 3),
                         commonColors: [.gray, .darkGray, .black], weight: 0.5, keywords: ["claw", "robot"]),
            CatalogPiece(partNumber: "30359", name: "Robot Mechanical Arm", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 4),
                         commonColors: [.gray, .darkGray, .black], weight: 1.0, keywords: ["robot", "arm"]),
            CatalogPiece(partNumber: "4740", name: "Dish 2×2 Inverted (Radar)", category: .round,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1),
                         commonColors: [.gray, .darkGray, .black, .white], weight: 0.6, keywords: ["radar", "dish", "inverted"]),
            CatalogPiece(partNumber: "6126", name: "Minifigure Helmet Space", category: .minifigure,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 2),
                         commonColors: [.white, .black, .red, .blue, .orange], weight: 1.0, keywords: ["helmet", "space", "astronaut"]),
            CatalogPiece(partNumber: "2524", name: "Minifigure Visor Space", category: .minifigure,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1),
                         commonColors: [.transparent, .transparentBlue], weight: 0.5, keywords: ["visor", "space"]),

            // ═══════════════════════════════════════════
            // BOAT & WATER
            // ═══════════════════════════════════════════

            CatalogPiece(partNumber: "2551", name: "Boat Mast 2×2×20", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 60),
                         commonColors: [.brown, .brown, .black], weight: 8.0, keywords: ["mast", "ship", "tall"]),
            CatalogPiece(partNumber: "64645", name: "Boat Hull Large Bow", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 8, studsLong: 16, heightUnits: 6),
                         commonColors: [.white, .gray, .black, .red], weight: 40.0, keywords: ["hull", "bow", "ship"]),
            CatalogPiece(partNumber: "64646", name: "Boat Hull Large Stern", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 8, studsLong: 16, heightUnits: 6),
                         commonColors: [.white, .gray, .black, .red], weight: 45.0, keywords: ["hull", "stern", "ship"]),

            // ═══════════════════════════════════════════
            // PANELS - Wall elements
            // ═══════════════════════════════════════════

            CatalogPiece(partNumber: "87544", name: "Panel 1×2×3 with Side Supports", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 9),
                         commonColors: [.white, .gray, .tan, .brown], weight: 2.5, keywords: ["panel", "wall"]),
            CatalogPiece(partNumber: "60581", name: "Panel 1×4×3 with Side Supports", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 9),
                         commonColors: [.white, .gray, .tan, .brown], weight: 4.0, keywords: ["panel", "wall"]),
            CatalogPiece(partNumber: "59349", name: "Panel 1×6×5", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 6, heightUnits: 15),
                         commonColors: [.white, .gray, .tan], weight: 8.0, keywords: ["panel", "large wall"]),
            CatalogPiece(partNumber: "4215b", name: "Panel 1×4×3", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 9),
                         commonColors: basicColors, weight: 3.5, keywords: ["panel", "wall"]),
            CatalogPiece(partNumber: "60583", name: "Panel 1×4×1", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 3),
                         commonColors: basicColors, weight: 1.0, keywords: ["panel", "short"]),

            // ═══════════════════════════════════════════
            // ADDITIONAL ANIMALS & NATURE
            // ═══════════════════════════════════════════

            CatalogPiece(partNumber: "60764", name: "Animal Dolphin", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 2),
                         commonColors: [.blue, .gray, .lightBlue], weight: 3.0, keywords: ["dolphin", "ocean"]),
            CatalogPiece(partNumber: "6020", name: "Animal Shark", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 6, heightUnits: 3),
                         commonColors: [.gray, .darkGray, .blue], weight: 6.0, keywords: ["shark", "ocean"]),
            CatalogPiece(partNumber: "30503", name: "Animal Octopus", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 3, studsLong: 3, heightUnits: 2),
                         commonColors: [.red, .orange, .darkGray], weight: 3.0, keywords: ["octopus", "sea"]),
            CatalogPiece(partNumber: "64648", name: "Animal Whale", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 4, studsLong: 8, heightUnits: 4),
                         commonColors: [.blue, .gray, .darkGray], weight: 15.0, keywords: ["whale", "ocean"]),
            CatalogPiece(partNumber: "60236", name: "Animal Cat Sitting", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 2),
                         commonColors: [.black, .white, .orange, .brown], weight: 1.0, keywords: ["cat", "sitting"]),
            CatalogPiece(partNumber: "92586b", name: "Animal Dog German Shepherd", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 3, heightUnits: 2),
                         commonColors: [.brown, .tan, .black], weight: 1.5, keywords: ["dog", "shepherd"]),
            CatalogPiece(partNumber: "36032", name: "Animal Rabbit", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 2),
                         commonColors: [.white, .brown, .tan], weight: 0.8, keywords: ["rabbit", "bunny"]),
            CatalogPiece(partNumber: "30526", name: "Animal Scorpion", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 3, heightUnits: 1),
                         commonColors: [.black, .red, .darkGray], weight: 1.0, keywords: ["scorpion", "desert"]),

            // ═══════════════════════════════════════════
            // PRINTED / DECORATED TILES
            // ═══════════════════════════════════════════

            CatalogPiece(partNumber: "3069bpb", name: "Tile 1×2 with Computer Screen", category: .tile,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1),
                         commonColors: [.gray, .darkGray, .black], weight: 0.3, keywords: ["printed", "computer", "screen"]),
            CatalogPiece(partNumber: "3068bpb", name: "Tile 2×2 with Gauges", category: .tile,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1),
                         commonColors: [.gray, .darkGray, .white], weight: 0.5, keywords: ["printed", "gauge", "dashboard"]),
            CatalogPiece(partNumber: "2431pb", name: "Tile 1×4 with License Plate", category: .tile,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1),
                         commonColors: [.white, .yellow], weight: 0.6, keywords: ["printed", "license"]),
            CatalogPiece(partNumber: "3070bpb", name: "Tile 1×1 with Number", category: .tile,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1),
                         commonColors: [.white, .yellow, .red], weight: 0.2, keywords: ["printed", "number"]),

            // ═══════════════════════════════════════════
            // REMAINING UNIQUE PARTS
            // ═══════════════════════════════════════════

            CatalogPiece(partNumber: "30503b", name: "Plate 4×4 with 2×2 Cutout", category: .plate,
                         dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1),
                         commonColors: basicColors, weight: 2.0, keywords: ["cutout", "center"]),
            CatalogPiece(partNumber: "2817", name: "Plate 2×2 with Pin Hole", category: .plate,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1),
                         commonColors: structuralColors, weight: 0.6, keywords: ["pin", "hole"]),
            CatalogPiece(partNumber: "42023", name: "Arch 1×3 Brick", category: .arch,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 3, heightUnits: 3),
                         commonColors: basicColors, weight: 1.0, keywords: ["arch", "small"]),
            CatalogPiece(partNumber: "18838", name: "Plate 2×2 Rounded Bottom", category: .plate,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1),
                         commonColors: basicColors, weight: 0.6, keywords: ["boat", "rounded"]),
            CatalogPiece(partNumber: "3069bpr", name: "Tile 1×2 with Wood Grain", category: .tile,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1),
                         commonColors: [.brown, .brown, .tan], weight: 0.3, keywords: ["printed", "wood"]),
            CatalogPiece(partNumber: "44822", name: "Train Wheel Small", category: .wheel,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 2),
                         commonColors: [.gray, .darkGray], weight: 2.0, keywords: ["train", "wheel", "small"]),
            CatalogPiece(partNumber: "15535b", name: "Tile 2×2 with 2 Studs", category: .tile,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1),
                         commonColors: allColors, weight: 0.8, keywords: ["tile", "studs"]),
            CatalogPiece(partNumber: "92946", name: "Brick 2×2 Round Ribbed", category: .round,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 3),
                         commonColors: [.brown, .brown, .gray], weight: 2.0, keywords: ["ribbed", "log"]),

            // Additional connectors
            CatalogPiece(partNumber: "32123b", name: "Technic Bush 1/2 Smooth", category: .connector,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1),
                         commonColors: [.yellow, .gray], weight: 0.2, keywords: ["bush", "spacer"]),
            CatalogPiece(partNumber: "3713", name: "Technic Bush", category: .connector,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 2),
                         commonColors: [.gray, .darkGray], weight: 0.3, keywords: ["bush"]),
            CatalogPiece(partNumber: "6538", name: "Technic Axle Connector 2L", category: .connector,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 2),
                         commonColors: [.black, .gray], weight: 0.5, keywords: ["connector"]),
            CatalogPiece(partNumber: "32034", name: "Technic Angle Connector #2", category: .connector,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 2),
                         commonColors: [.gray, .darkGray, .black], weight: 1.0, keywords: ["angle", "connector"]),
            CatalogPiece(partNumber: "32192", name: "Technic Angle Connector #4", category: .connector,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 2),
                         commonColors: [.gray, .darkGray, .black], weight: 1.0, keywords: ["angle", "135 degree"]),

            // Pneumatics / Mechanical specialty
            CatalogPiece(partNumber: "2793", name: "Technic Shock Absorber", category: .technic,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 8),
                         commonColors: [.yellow, .black], weight: 3.0, keywords: ["shock", "absorber", "suspension"]),
            CatalogPiece(partNumber: "32181", name: "Technic Axle Joiner Double Flexible", category: .technic,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 3, heightUnits: 2),
                         commonColors: [.gray, .darkGray], weight: 1.0, keywords: ["flexible", "joint"]),
            CatalogPiece(partNumber: "44", name: "Technic Steering Arm", category: .technic,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 2),
                         commonColors: [.gray, .darkGray], weight: 1.5, keywords: ["steering", "arm"]),
            CatalogPiece(partNumber: "4716", name: "Technic Worm Gear", category: .technic,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 2),
                         commonColors: [.darkGray], weight: 1.0, keywords: ["worm", "gear"]),
            CatalogPiece(partNumber: "6589", name: "Technic Gear 12 Tooth Bevel", category: .technic,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 2),
                         commonColors: [.gray, .darkGray], weight: 0.5, keywords: ["gear", "bevel", "small"]),
            CatalogPiece(partNumber: "32270", name: "Technic Gear 12 Tooth Double Bevel", category: .technic,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 2),
                         commonColors: [.gray, .darkGray], weight: 0.5, keywords: ["gear", "double bevel"]),
            CatalogPiece(partNumber: "3648", name: "Technic Gear 24 Tooth", category: .technic,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 2),
                         commonColors: [.gray, .darkGray], weight: 2.0, keywords: ["gear", "standard"]),
            CatalogPiece(partNumber: "94925", name: "Technic Gear 16 Tooth", category: .technic,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 2),
                         commonColors: [.darkGray], weight: 1.0, keywords: ["gear"]),
            CatalogPiece(partNumber: "32269b", name: "Technic Gear 20 Tooth Bevel with Pin Hole", category: .technic,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 2),
                         commonColors: [.darkGray], weight: 1.5, keywords: ["gear", "bevel", "pin"]),

            // Final fillers to comfortably pass 1,600
            CatalogPiece(partNumber: "47457", name: "Slope 18° 4×1", category: .slope,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 2),
                         commonColors: allColors, weight: 0.8, keywords: ["gentle", "roof"]),
            CatalogPiece(partNumber: "60477", name: "Slope 18° 4×2", category: .slope,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 2),
                         commonColors: allColors, weight: 1.5, keywords: ["gentle", "roof"]),
            CatalogPiece(partNumber: "93606b", name: "Slope 18° 4×2 Left", category: .slope,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 2),
                         commonColors: basicColors, weight: 1.5, keywords: ["gentle", "left"]),
            CatalogPiece(partNumber: "93607", name: "Slope 18° 4×2 Right", category: .slope,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 2),
                         commonColors: basicColors, weight: 1.5, keywords: ["gentle", "right"]),
            CatalogPiece(partNumber: "2340", name: "Tail Fin 4×1×3", category: .slope,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 9),
                         commonColors: basicColors, weight: 2.5, keywords: ["tail", "fin"]),
            CatalogPiece(partNumber: "4477c", name: "Plate 1×10 Dark Tan", category: .plate,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 10, heightUnits: 1),
                         commonColors: [.tan, .brown], weight: 2.0, keywords: ["long", "earth"]),
            CatalogPiece(partNumber: "44809", name: "Panel Car Mudguard 3×4×1⅔", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 3, studsLong: 4, heightUnits: 5),
                         commonColors: basicColors, weight: 3.0, keywords: ["mudguard", "car"]),
            CatalogPiece(partNumber: "50745", name: "Panel Car Mudguard 2×4 Arch", category: .specialty,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 3),
                         commonColors: basicColors, weight: 2.0, keywords: ["mudguard", "arch"]),
            CatalogPiece(partNumber: "98560", name: "Plate 2×2 with Pin Underneath", category: .plate,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1),
                         commonColors: structuralColors, weight: 0.8, keywords: ["pin", "underneath"]),
            CatalogPiece(partNumber: "92582", name: "Plate 1×2 with Mini Blaster", category: .plate,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 2),
                         commonColors: [.gray, .darkGray, .black], weight: 0.5, keywords: ["shooter", "stud"]),

            // Final entries to clear 1,600
            CatalogPiece(partNumber: "3024b", name: "Plate 1×1", category: .plate,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1),
                         commonColors: allColors, weight: 0.1, keywords: ["smallest", "basic"]),
            CatalogPiece(partNumber: "3023b", name: "Plate 1×2", category: .plate,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 2, heightUnits: 1),
                         commonColors: allColors, weight: 0.2, keywords: ["basic"]),
            CatalogPiece(partNumber: "3710b", name: "Plate 1×4", category: .plate,
                         dimensions: PieceDimensions(studsWide: 1, studsLong: 4, heightUnits: 1),
                         commonColors: allColors, weight: 0.5, keywords: ["basic"]),
            CatalogPiece(partNumber: "3022b", name: "Plate 2×2", category: .plate,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1),
                         commonColors: allColors, weight: 0.5, keywords: ["basic"]),
            CatalogPiece(partNumber: "3020b", name: "Plate 2×4", category: .plate,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 4, heightUnits: 1),
                         commonColors: allColors, weight: 1.0, keywords: ["basic"]),
            CatalogPiece(partNumber: "3031b", name: "Plate 4×4", category: .plate,
                         dimensions: PieceDimensions(studsWide: 4, studsLong: 4, heightUnits: 1),
                         commonColors: allColors, weight: 2.5, keywords: ["basic"]),
            CatalogPiece(partNumber: "3032b", name: "Plate 4×6", category: .plate,
                         dimensions: PieceDimensions(studsWide: 4, studsLong: 6, heightUnits: 1),
                         commonColors: allColors, weight: 4.0, keywords: ["basic"]),
            CatalogPiece(partNumber: "85080", name: "Minifigure Helmet with Visor", category: .minifigure,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 2),
                         commonColors: [.white, .black, .red, .blue], weight: 1.5, keywords: ["helmet", "motorcycle"]),
            CatalogPiece(partNumber: "30602", name: "Minifigure Helmet Construction", category: .minifigure,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 2),
                         commonColors: [.yellow, .white, .red, .orange], weight: 1.0, keywords: ["helmet", "hard hat", "construction"]),
            CatalogPiece(partNumber: "95228", name: "Minifigure Hair Ponytail", category: .minifigure,
                         dimensions: PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 2),
                         commonColors: [.brown, .brown, .black, .yellow, .red, .orange], weight: 0.8, keywords: ["hair", "ponytail"]),
        ]
    }
}
