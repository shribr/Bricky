import SwiftUI
import UIKit

/// Abstraction over the cloud part recognizer so the view model is testable
/// without hitting the network.
protocol PartIdentifying: Sendable {
    func identifyPart(image: UIImage, maxResults: Int) async throws -> [BrickognizeService.MatchedPart]
}

extension BrickognizeService: PartIdentifying {}

/// Drives the **Scan One Brick** flow: photograph a single centered brick, send
/// it to the cloud part recognizer, and let the user confirm a ranked candidate
/// into an inventory. This is the accurate per-brick path (vs. the heuristic
/// pile scanner) — one part per capture, matching what the recognizer is good at.
@MainActor
final class ScanBrickViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case identifying
        case results
        case empty          // recognizer returned nothing
        case cloudDisabled  // user has cloud recognition turned off
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var candidates: [BrickognizeService.MatchedPart] = []
    @Published var capturedImage: UIImage?

    /// The color last confirmed by the user, persisted so the picker defaults to
    /// it on the next brick (people often add several bricks of one color).
    @Published private(set) var lastUsedColor: LegoColor

    private let identifier: PartIdentifying
    private let isCloudEnabled: () -> Bool
    private let defaults: UserDefaults

    init(
        identifier: PartIdentifying = BrickognizeService.shared,
        isCloudEnabled: @escaping () -> Bool = { ScanSettings.shared.cloudFallbackEnabled },
        defaults: UserDefaults = .standard
    ) {
        self.identifier = identifier
        self.isCloudEnabled = isCloudEnabled
        self.defaults = defaults
        let stored = defaults.string(forKey: UserDefaultsKey.lastScannedBrickColor)
        self.lastUsedColor = stored.flatMap { LegoColor(fromString: $0) } ?? .red
    }

    /// Identify a captured single-brick photo. Honest states: `.cloudDisabled`
    /// when the user opted out, `.empty` when nothing came back, `.failed` on error.
    func identify(image: UIImage) async {
        capturedImage = image
        guard isCloudEnabled() else {
            phase = .cloudDisabled
            return
        }
        phase = .identifying
        candidates = []
        do {
            let results = try await identifier.identifyPart(image: image, maxResults: 5)
            candidates = results
            phase = results.isEmpty ? .empty : .results
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Build an inventory piece from a chosen candidate + a user-picked color.
    /// Color is NEVER inferred from the recognizer (the parts API doesn't return
    /// a reliable color), so the caller must supply it — no fabrication.
    func inventoryPiece(
        for candidate: BrickognizeService.MatchedPart,
        color: LegoColor,
        quantity: Int = 1
    ) -> InventoryStore.InventoryPiece {
        InventoryStore.InventoryPiece(
            partNumber: candidate.matchedPartNumber ?? candidate.prediction.brickLinkID,
            name: candidate.matchedName ?? candidate.prediction.name,
            category: candidate.matchedCategory ?? .brick,
            color: color,
            quantity: max(1, quantity),
            dimensions: candidate.matchedDimensions
                ?? PieceDimensions(studsWide: 2, studsLong: 2, heightUnits: 1)
        )
    }

    /// Confirm a candidate into the given inventory with a user-chosen color.
    func confirm(
        _ candidate: BrickognizeService.MatchedPart,
        color: LegoColor,
        quantity: Int = 1,
        into inventoryId: UUID,
        store: InventoryStore = .shared
    ) {
        store.addPiece(inventoryPiece(for: candidate, color: color, quantity: quantity), to: inventoryId)
        rememberColor(color)
    }

    /// Persist the last-confirmed color so the next brick defaults to it.
    private func rememberColor(_ color: LegoColor) {
        lastUsedColor = color
        defaults.set(color.rawValue, forKey: UserDefaultsKey.lastScannedBrickColor)
    }

    func reset() {
        phase = .idle
        candidates = []
        capturedImage = nil
    }
}
