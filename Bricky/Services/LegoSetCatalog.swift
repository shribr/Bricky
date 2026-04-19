import Foundation

/// Catalog of popular LEGO sets with their piece lists.
/// Each set includes part numbers and colors for inventory cross-referencing.
final class LegoSetCatalog {
    static let shared = LegoSetCatalog()

    private(set) var sets: [LegoSet] = []
    private var setIndex: [String: LegoSet] = [:]
    private var themeIndex: [String: [LegoSet]] = [:]

    private init() {
        loadSets()
        buildIndices()
    }

    func set(byNumber number: String) -> LegoSet? {
        setIndex[number]
    }

    func sets(byTheme theme: String) -> [LegoSet] {
        themeIndex[theme] ?? []
    }

    var allThemes: [String] {
        themeIndex.keys.sorted()
    }

    func search(_ query: String) -> [LegoSet] {
        let lower = query.lowercased()
        return sets.filter {
            $0.name.lowercased().contains(lower) ||
            $0.setNumber.contains(lower) ||
            $0.theme.lowercased().contains(lower)
        }
    }

    // MARK: - Build Index

    private func buildIndices() {
        setIndex = Dictionary(uniqueKeysWithValues: sets.map { ($0.setNumber, $0) })
        themeIndex = Dictionary(grouping: sets, by: { $0.theme })
    }

    // MARK: - Set Data

    private func loadSets() {
        sets = [
            // MARK: City
            LegoSet(id: "60431", setNumber: "60431", name: "Space Explorer Rover", theme: "City", year: 2024, pieceCount: 311, pieces: [
                .init(partNumber: "3003", color: "Gray", quantity: 8),
                .init(partNumber: "3004", color: "Gray", quantity: 6),
                .init(partNumber: "3010", color: "Gray", quantity: 4),
                .init(partNumber: "3022", color: "Gray", quantity: 6),
                .init(partNumber: "3020", color: "Gray", quantity: 4),
                .init(partNumber: "3024", color: "Black", quantity: 12),
                .init(partNumber: "3040", color: "Gray", quantity: 4),
                .init(partNumber: "6541", color: "Gray", quantity: 2),
                .init(partNumber: "4286", color: "Dark Gray", quantity: 4),
            ]),
            LegoSet(id: "60398", setNumber: "60398", name: "Family House and Electric Car", theme: "City", year: 2024, pieceCount: 462, pieces: [
                .init(partNumber: "3001", color: "White", quantity: 10),
                .init(partNumber: "3002", color: "White", quantity: 8),
                .init(partNumber: "3003", color: "White", quantity: 6),
                .init(partNumber: "3010", color: "Tan", quantity: 8),
                .init(partNumber: "3020", color: "Green", quantity: 6),
                .init(partNumber: "3022", color: "Green", quantity: 4),
                .init(partNumber: "3039", color: "Red", quantity: 4),
                .init(partNumber: "3660", color: "Red", quantity: 2),
                .init(partNumber: "4286", color: "Gray", quantity: 6),
            ]),
            LegoSet(id: "60426", setNumber: "60426", name: "Jungle Explorer Off-Road Truck", theme: "City", year: 2024, pieceCount: 252, pieces: [
                .init(partNumber: "3003", color: "Dark Green", quantity: 6),
                .init(partNumber: "3004", color: "Dark Green", quantity: 4),
                .init(partNumber: "3010", color: "Black", quantity: 4),
                .init(partNumber: "3022", color: "Black", quantity: 6),
                .init(partNumber: "3024", color: "Black", quantity: 8),
                .init(partNumber: "6541", color: "Black", quantity: 4),
            ]),

            // MARK: Technic
            LegoSet(id: "42183", setNumber: "42183", name: "Bugatti Bolide", theme: "Technic", year: 2024, pieceCount: 905, pieces: [
                .init(partNumber: "3003", color: "Blue", quantity: 12),
                .init(partNumber: "3004", color: "Blue", quantity: 8),
                .init(partNumber: "3010", color: "Black", quantity: 10),
                .init(partNumber: "3024", color: "Black", quantity: 20),
                .init(partNumber: "3022", color: "Black", quantity: 8),
                .init(partNumber: "3040", color: "Blue", quantity: 6),
                .init(partNumber: "3660", color: "Blue", quantity: 4),
            ]),
            LegoSet(id: "42151", setNumber: "42151", name: "Bugatti Bolide Agile Blue", theme: "Technic", year: 2023, pieceCount: 905, pieces: [
                .init(partNumber: "3003", color: "Blue", quantity: 14),
                .init(partNumber: "3004", color: "Blue", quantity: 10),
                .init(partNumber: "3010", color: "Black", quantity: 8),
                .init(partNumber: "3024", color: "Black", quantity: 16),
                .init(partNumber: "3039", color: "Blue", quantity: 6),
            ]),
            LegoSet(id: "42196", setNumber: "42196", name: "Lamborghini Huracán Tecnica", theme: "Technic", year: 2024, pieceCount: 806, pieces: [
                .init(partNumber: "3003", color: "Orange", quantity: 10),
                .init(partNumber: "3004", color: "Orange", quantity: 8),
                .init(partNumber: "3010", color: "Black", quantity: 6),
                .init(partNumber: "3024", color: "Black", quantity: 14),
                .init(partNumber: "3040", color: "Orange", quantity: 4),
            ]),

            // MARK: Creator Expert / Icons
            LegoSet(id: "10497", setNumber: "10497", name: "Galaxy Explorer", theme: "Icons", year: 2022, pieceCount: 1254, pieces: [
                .init(partNumber: "3001", color: "Gray", quantity: 12),
                .init(partNumber: "3002", color: "Gray", quantity: 10),
                .init(partNumber: "3003", color: "Gray", quantity: 16),
                .init(partNumber: "3004", color: "Gray", quantity: 8),
                .init(partNumber: "3010", color: "Blue", quantity: 10),
                .init(partNumber: "3020", color: "Gray", quantity: 8),
                .init(partNumber: "3022", color: "Gray", quantity: 6),
                .init(partNumber: "3024", color: "Gray", quantity: 20),
                .init(partNumber: "3039", color: "Gray", quantity: 4),
                .init(partNumber: "3040", color: "Blue", quantity: 6),
            ]),
            LegoSet(id: "10281", setNumber: "10281", name: "Bonsai Tree", theme: "Icons", year: 2021, pieceCount: 878, pieces: [
                .init(partNumber: "3024", color: "Brown", quantity: 12),
                .init(partNumber: "3003", color: "Brown", quantity: 6),
                .init(partNumber: "3004", color: "Brown", quantity: 4),
                .init(partNumber: "3022", color: "Green", quantity: 8),
                .init(partNumber: "3020", color: "Green", quantity: 6),
                .init(partNumber: "3024", color: "Pink", quantity: 16),
            ]),
            LegoSet(id: "10311", setNumber: "10311", name: "Orchid", theme: "Icons", year: 2022, pieceCount: 608, pieces: [
                .init(partNumber: "3024", color: "White", quantity: 14),
                .init(partNumber: "3003", color: "Dark Green", quantity: 6),
                .init(partNumber: "3004", color: "Dark Green", quantity: 4),
                .init(partNumber: "3020", color: "Dark Green", quantity: 4),
                .init(partNumber: "3022", color: "White", quantity: 8),
            ]),
            LegoSet(id: "10297", setNumber: "10297", name: "Boutique Hotel", theme: "Icons", year: 2022, pieceCount: 3066, pieces: [
                .init(partNumber: "3001", color: "Tan", quantity: 16),
                .init(partNumber: "3002", color: "Tan", quantity: 12),
                .init(partNumber: "3003", color: "Tan", quantity: 20),
                .init(partNumber: "3004", color: "Tan", quantity: 14),
                .init(partNumber: "3010", color: "Dark Red", quantity: 10),
                .init(partNumber: "3020", color: "Tan", quantity: 10),
                .init(partNumber: "3022", color: "Tan", quantity: 8),
                .init(partNumber: "3024", color: "Dark Red", quantity: 20),
                .init(partNumber: "3039", color: "Tan", quantity: 6),
            ]),

            // MARK: Star Wars
            LegoSet(id: "75192", setNumber: "75192", name: "Millennium Falcon", theme: "Star Wars", year: 2017, pieceCount: 7541, pieces: [
                .init(partNumber: "3003", color: "Gray", quantity: 30),
                .init(partNumber: "3004", color: "Gray", quantity: 24),
                .init(partNumber: "3010", color: "Gray", quantity: 18),
                .init(partNumber: "3020", color: "Gray", quantity: 16),
                .init(partNumber: "3022", color: "Gray", quantity: 12),
                .init(partNumber: "3024", color: "Gray", quantity: 40),
                .init(partNumber: "3001", color: "Gray", quantity: 14),
                .init(partNumber: "3002", color: "Gray", quantity: 10),
                .init(partNumber: "3039", color: "Gray", quantity: 8),
                .init(partNumber: "3040", color: "Gray", quantity: 6),
            ]),
            LegoSet(id: "75375", setNumber: "75375", name: "Millennium Falcon", theme: "Star Wars", year: 2024, pieceCount: 921, pieces: [
                .init(partNumber: "3003", color: "Gray", quantity: 12),
                .init(partNumber: "3004", color: "Gray", quantity: 8),
                .init(partNumber: "3010", color: "Gray", quantity: 6),
                .init(partNumber: "3022", color: "Gray", quantity: 8),
                .init(partNumber: "3024", color: "Gray", quantity: 16),
                .init(partNumber: "3040", color: "Gray", quantity: 4),
            ]),
            LegoSet(id: "75367", setNumber: "75367", name: "Venator-Class Republic Attack Cruiser", theme: "Star Wars", year: 2023, pieceCount: 5374, pieces: [
                .init(partNumber: "3003", color: "Red", quantity: 18),
                .init(partNumber: "3004", color: "Red", quantity: 14),
                .init(partNumber: "3010", color: "Gray", quantity: 16),
                .init(partNumber: "3020", color: "Gray", quantity: 12),
                .init(partNumber: "3024", color: "Gray", quantity: 30),
                .init(partNumber: "3039", color: "Red", quantity: 8),
                .init(partNumber: "3040", color: "Gray", quantity: 6),
            ]),

            // MARK: Harry Potter
            LegoSet(id: "76419", setNumber: "76419", name: "Hogwarts Castle and Grounds", theme: "Harry Potter", year: 2023, pieceCount: 2660, pieces: [
                .init(partNumber: "3001", color: "Tan", quantity: 14),
                .init(partNumber: "3003", color: "Tan", quantity: 18),
                .init(partNumber: "3004", color: "Tan", quantity: 12),
                .init(partNumber: "3010", color: "Dark Gray", quantity: 10),
                .init(partNumber: "3020", color: "Dark Gray", quantity: 8),
                .init(partNumber: "3024", color: "Tan", quantity: 22),
                .init(partNumber: "3039", color: "Dark Gray", quantity: 6),
                .init(partNumber: "3040", color: "Dark Gray", quantity: 4),
            ]),
            LegoSet(id: "76435", setNumber: "76435", name: "Hogwarts Castle: The Great Hall", theme: "Harry Potter", year: 2024, pieceCount: 1732, pieces: [
                .init(partNumber: "3003", color: "Tan", quantity: 12),
                .init(partNumber: "3004", color: "Tan", quantity: 8),
                .init(partNumber: "3010", color: "Dark Gray", quantity: 8),
                .init(partNumber: "3022", color: "Tan", quantity: 6),
                .init(partNumber: "3024", color: "Tan", quantity: 16),
            ]),

            // MARK: Architecture
            LegoSet(id: "21054", setNumber: "21054", name: "The White House", theme: "Architecture", year: 2020, pieceCount: 1483, pieces: [
                .init(partNumber: "3003", color: "White", quantity: 16),
                .init(partNumber: "3004", color: "White", quantity: 12),
                .init(partNumber: "3010", color: "White", quantity: 10),
                .init(partNumber: "3020", color: "White", quantity: 8),
                .init(partNumber: "3022", color: "White", quantity: 6),
                .init(partNumber: "3024", color: "White", quantity: 20),
                .init(partNumber: "3039", color: "White", quantity: 4),
            ]),
            LegoSet(id: "21060", setNumber: "21060", name: "Himeji Castle", theme: "Architecture", year: 2023, pieceCount: 2125, pieces: [
                .init(partNumber: "3003", color: "White", quantity: 14),
                .init(partNumber: "3004", color: "White", quantity: 10),
                .init(partNumber: "3010", color: "White", quantity: 8),
                .init(partNumber: "3020", color: "White", quantity: 6),
                .init(partNumber: "3024", color: "White", quantity: 18),
                .init(partNumber: "3039", color: "White", quantity: 4),
                .init(partNumber: "3040", color: "Gray", quantity: 4),
            ]),

            // MARK: Friends
            LegoSet(id: "42620", setNumber: "42620", name: "Olly and Paisley's Family Houses", theme: "Friends", year: 2024, pieceCount: 1126, pieces: [
                .init(partNumber: "3001", color: "White", quantity: 8),
                .init(partNumber: "3003", color: "White", quantity: 10),
                .init(partNumber: "3004", color: "Lime", quantity: 6),
                .init(partNumber: "3010", color: "Orange", quantity: 6),
                .init(partNumber: "3020", color: "Green", quantity: 4),
                .init(partNumber: "3024", color: "White", quantity: 14),
            ]),
            LegoSet(id: "42604", setNumber: "42604", name: "Heartlake City Shopping Mall", theme: "Friends", year: 2024, pieceCount: 1032, pieces: [
                .init(partNumber: "3003", color: "Pink", quantity: 8),
                .init(partNumber: "3004", color: "White", quantity: 8),
                .init(partNumber: "3010", color: "White", quantity: 6),
                .init(partNumber: "3022", color: "Pink", quantity: 4),
                .init(partNumber: "3024", color: "White", quantity: 12),
            ]),

            // MARK: Creator 3-in-1
            LegoSet(id: "31208", setNumber: "31208", name: "Hokusai — The Great Wave", theme: "Art", year: 2023, pieceCount: 1810, pieces: [
                .init(partNumber: "3024", color: "Blue", quantity: 24),
                .init(partNumber: "3024", color: "White", quantity: 18),
                .init(partNumber: "3024", color: "Dark Blue", quantity: 16),
                .init(partNumber: "3024", color: "Tan", quantity: 10),
            ]),
            LegoSet(id: "31209", setNumber: "31209", name: "The Amazing Spider-Man", theme: "Art", year: 2023, pieceCount: 2099, pieces: [
                .init(partNumber: "3024", color: "Red", quantity: 22),
                .init(partNumber: "3024", color: "Blue", quantity: 18),
                .init(partNumber: "3024", color: "Black", quantity: 14),
                .init(partNumber: "3024", color: "White", quantity: 10),
            ]),

            // MARK: Ideas
            LegoSet(id: "21348", setNumber: "21348", name: "Dungeons & Dragons: Red Dragon's Tale", theme: "Ideas", year: 2024, pieceCount: 3745, pieces: [
                .init(partNumber: "3001", color: "Tan", quantity: 12),
                .init(partNumber: "3003", color: "Tan", quantity: 16),
                .init(partNumber: "3004", color: "Dark Gray", quantity: 10),
                .init(partNumber: "3010", color: "Dark Gray", quantity: 8),
                .init(partNumber: "3020", color: "Green", quantity: 8),
                .init(partNumber: "3024", color: "Tan", quantity: 20),
                .init(partNumber: "3039", color: "Dark Gray", quantity: 4),
                .init(partNumber: "3040", color: "Brown", quantity: 6),
            ]),

            // MARK: Speed Champions
            LegoSet(id: "76916", setNumber: "76916", name: "Porsche 963", theme: "Speed Champions", year: 2023, pieceCount: 280, pieces: [
                .init(partNumber: "3003", color: "White", quantity: 6),
                .init(partNumber: "3004", color: "White", quantity: 4),
                .init(partNumber: "3024", color: "Black", quantity: 8),
                .init(partNumber: "3022", color: "White", quantity: 4),
            ]),
            LegoSet(id: "76924", setNumber: "76924", name: "Mercedes-AMG GT3 & AMG SL 63", theme: "Speed Champions", year: 2024, pieceCount: 792, pieces: [
                .init(partNumber: "3003", color: "Gray", quantity: 8),
                .init(partNumber: "3004", color: "Gray", quantity: 6),
                .init(partNumber: "3010", color: "Black", quantity: 4),
                .init(partNumber: "3024", color: "Black", quantity: 12),
                .init(partNumber: "3040", color: "Gray", quantity: 4),
            ]),

            // MARK: Ninjago
            LegoSet(id: "71815", setNumber: "71815", name: "Kai's Source Dragon Battle", theme: "Ninjago", year: 2024, pieceCount: 1099, pieces: [
                .init(partNumber: "3003", color: "Red", quantity: 10),
                .init(partNumber: "3004", color: "Red", quantity: 8),
                .init(partNumber: "3010", color: "Black", quantity: 6),
                .init(partNumber: "3024", color: "Red", quantity: 14),
                .init(partNumber: "3039", color: "Red", quantity: 4),
                .init(partNumber: "3040", color: "Red", quantity: 4),
            ]),

            // MARK: Marvel
            LegoSet(id: "76269", setNumber: "76269", name: "Avengers Tower", theme: "Marvel", year: 2024, pieceCount: 5201, pieces: [
                .init(partNumber: "3001", color: "Gray", quantity: 14),
                .init(partNumber: "3003", color: "Gray", quantity: 18),
                .init(partNumber: "3004", color: "Gray", quantity: 12),
                .init(partNumber: "3010", color: "Blue", quantity: 10),
                .init(partNumber: "3020", color: "Gray", quantity: 10),
                .init(partNumber: "3022", color: "Gray", quantity: 8),
                .init(partNumber: "3024", color: "Gray", quantity: 24),
                .init(partNumber: "3039", color: "Gray", quantity: 6),
            ]),

            // MARK: Disney
            LegoSet(id: "43222", setNumber: "43222", name: "Disney Castle", theme: "Disney", year: 2023, pieceCount: 4837, pieces: [
                .init(partNumber: "3001", color: "Tan", quantity: 14),
                .init(partNumber: "3003", color: "Tan", quantity: 20),
                .init(partNumber: "3004", color: "Tan", quantity: 16),
                .init(partNumber: "3010", color: "Blue", quantity: 12),
                .init(partNumber: "3020", color: "Tan", quantity: 8),
                .init(partNumber: "3024", color: "Tan", quantity: 26),
                .init(partNumber: "3039", color: "Blue", quantity: 6),
                .init(partNumber: "3040", color: "Blue", quantity: 4),
            ]),

            // MARK: Super Mario
            LegoSet(id: "71438", setNumber: "71438", name: "Peach's Castle Expansion Set", theme: "Super Mario", year: 2024, pieceCount: 1216, pieces: [
                .init(partNumber: "3003", color: "Pink", quantity: 10),
                .init(partNumber: "3004", color: "White", quantity: 8),
                .init(partNumber: "3010", color: "Tan", quantity: 6),
                .init(partNumber: "3022", color: "Pink", quantity: 4),
                .init(partNumber: "3024", color: "Pink", quantity: 14),
            ]),

            // MARK: Minecraft
            LegoSet(id: "21256", setNumber: "21256", name: "The Frog House", theme: "Minecraft", year: 2024, pieceCount: 400, pieces: [
                .init(partNumber: "3003", color: "Green", quantity: 8),
                .init(partNumber: "3004", color: "Green", quantity: 6),
                .init(partNumber: "3010", color: "Brown", quantity: 4),
                .init(partNumber: "3024", color: "Green", quantity: 10),
            ]),
        ]
    }
}
