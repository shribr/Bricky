import SwiftUI

/// ViewModel for the piece catalog/inventory view
@MainActor
final class PieceCatalogViewModel: ObservableObject {
    @Published var pieces: [LegoPiece] = []
    @Published var searchText = ""
    @Published var selectedCategory: PieceCategory?
    @Published var selectedColor: LegoColor?
    @Published var sortOrder: SortOrder = .quantity
    @Published var useNaturalLanguage = true

    private let nlSearch = NaturalLanguageSearchService.shared

    enum SortOrder: String, CaseIterable {
        case quantity = "Quantity"
        case name = "Name"
        case category = "Category"
        case color = "Color"
    }

    var filteredPieces: [LegoPiece] {
        var result = pieces

        if !searchText.isEmpty {
            if useNaturalLanguage {
                result = nlSearch.search(result, query: searchText)
            } else {
                let search = searchText.lowercased()
                result = result.filter {
                    $0.name.lowercased().contains(search) ||
                    $0.partNumber.lowercased().contains(search) ||
                    $0.color.rawValue.lowercased().contains(search) ||
                    $0.category.rawValue.lowercased().contains(search)
                }
            }
        }

        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        if let color = selectedColor {
            result = result.filter { $0.color == color }
        }

        switch sortOrder {
        case .quantity: result.sort { $0.quantity > $1.quantity }
        case .name: result.sort { $0.name < $1.name }
        case .category: result.sort { $0.category.rawValue < $1.category.rawValue }
        case .color: result.sort { $0.color.rawValue < $1.color.rawValue }
        }

        return result
    }

    var totalPieceCount: Int {
        pieces.reduce(0) { $0 + $1.quantity }
    }

    var uniquePieceCount: Int {
        pieces.count
    }

    var categoryCounts: [(category: PieceCategory, count: Int)] {
        let grouped = Dictionary(grouping: pieces) { $0.category }
        return grouped.map { (category: $0.key, count: $0.value.reduce(0) { $0 + $1.quantity }) }
            .sorted { $0.count > $1.count }
    }

    var colorCounts: [(color: LegoColor, count: Int)] {
        let grouped = Dictionary(grouping: pieces) { $0.color }
        return grouped.map { (color: $0.key, count: $0.value.reduce(0) { $0 + $1.quantity }) }
            .sorted { $0.count > $1.count }
    }

    func updatePieces(from session: ScanSession) {
        pieces = session.pieces
    }

    func adjustQuantity(for piece: LegoPiece, by amount: Int) {
        if let index = pieces.firstIndex(where: { $0.id == piece.id }) {
            let newQty = max(0, pieces[index].quantity + amount)
            if newQty == 0 {
                pieces.remove(at: index)
            } else {
                pieces[index].quantity = newQty
            }
        }
    }

    func removePiece(_ piece: LegoPiece) {
        pieces.removeAll { $0.id == piece.id }
    }
}
