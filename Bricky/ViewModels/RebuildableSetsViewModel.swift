import SwiftUI

/// Abstraction over the set bill-of-materials source so the view model is
/// testable without the network.
protocol SetBOMProviding: Sendable {
    func fetchParts(for setNumber: String) async throws -> [LegoSet.SetPiece]
}

extension RebrickableSetService: SetBOMProviding {}

/// Tier A of the pile→sets vision (no ML): for each set the user owns, compute
/// how much of it they can rebuild from their scanned inventory and what's
/// missing. Pure data + `SetCompletionEngine` — the accurate, no-model half.
@MainActor
final class RebuildableSetsViewModel: ObservableObject {

    struct Row: Identifiable {
        let id: String            // set number
        let setNumber: String
        let name: String
        let completion: SetCompletionEngine.Completion
    }

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case notConfigured   // no Rebrickable proxy/key available
        case empty           // no owned sets to evaluate
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var rows: [Row] = []

    /// Owned sets that can be fully built from the current inventory.
    var fullyBuildableCount: Int { rows.filter { $0.completion.isComplete }.count }
    /// Owned sets successfully evaluated (parts fetched).
    var evaluatedSetCount: Int { rows.count }

    private let bomProvider: SetBOMProviding
    private let isConfigured: Bool
    private let setName: (String) -> String

    init(
        bomProvider: SetBOMProviding = RebrickableSetService(),
        isConfigured: Bool = RebrickableSetService().isConfigured,
        setName: @escaping (String) -> String = { number in
            LegoSetCatalog.shared.set(byNumber: number)?.name ?? "Set \(number)"
        }
    ) {
        self.bomProvider = bomProvider
        self.isConfigured = isConfigured
        self.setName = setName
    }

    /// Evaluate every owned set against the owned inventory, ranked most-buildable
    /// first. `ownedSetNumbers` come from `SetCollectionStore`; `ownedCounts` is a
    /// part+color→qty map (see `ownedCounts(from:)`).
    func load(ownedSetNumbers: [String], ownedCounts: [String: Int]) async {
        guard isConfigured else { phase = .notConfigured; return }
        let uniqueSets = Array(Set(ownedSetNumbers))
        guard !uniqueSets.isEmpty else { phase = .empty; rows = []; return }

        phase = .loading
        var built: [Row] = []
        var lastError: String?

        for setNumber in uniqueSets {
            do {
                let bom = try await bomProvider.fetchParts(for: setNumber)
                let completion = SetCompletionEngine.evaluate(
                    setNumber: setNumber, bom: bom, ownedCounts: ownedCounts
                )
                built.append(Row(
                    id: setNumber, setNumber: setNumber,
                    name: setName(setNumber), completion: completion
                ))
            } catch {
                lastError = error.localizedDescription
                // Skip sets we can't fetch; keep evaluating the rest.
            }
        }

        rows = built.sorted { $0.completion.coverage > $1.completion.coverage }
        if rows.isEmpty {
            phase = .failed(lastError ?? "Couldn't fetch set parts.")
        } else {
            phase = .loaded
        }
    }

    /// Aggregate all pieces across the user's inventories into a part+color→qty
    /// map keyed exactly like `SetCompletionEngine` expects.
    static func ownedCounts(from inventories: [InventoryStore.Inventory]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for inventory in inventories {
            for piece in inventory.pieces {
                counts["\(piece.partNumber)|\(piece.color)", default: 0] += max(0, piece.quantity)
            }
        }
        return counts
    }
}
