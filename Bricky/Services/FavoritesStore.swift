import Foundation

final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var favoritedProjectIds: Set<UUID> = []

    private let key = "favoritedProjectIds"

    private init() {
        load()
    }

    func isFavorited(_ projectId: UUID) -> Bool {
        favoritedProjectIds.contains(projectId)
    }

    func toggle(_ projectId: UUID) {
        if favoritedProjectIds.contains(projectId) {
            favoritedProjectIds.remove(projectId)
        } else {
            favoritedProjectIds.insert(projectId)
        }
        save()
    }

    private func save() {
        let strings = favoritedProjectIds.map { $0.uuidString }
        UserDefaults.standard.set(strings, forKey: key)
    }

    private func load() {
        guard let strings = UserDefaults.standard.stringArray(forKey: key) else { return }
        favoritedProjectIds = Set(strings.compactMap { UUID(uuidString: $0) })
    }
}
