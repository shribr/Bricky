import Foundation
import UIKit

/// Persists user-supplied scan corrections as training data for future Core ML
/// model training. Each entry pairs a captured torso image with the figure(s)
/// the user confirmed as correct matches (and optionally rejected candidates).
///
/// Data is stored in Documents/minifigureTraining/ as:
///   entries.json           — array of TrainingEntry metadata
///   images/<uuid>.jpg      — captured torso JPEG for each entry
///
/// A Python export script can read this directory to build a labeled dataset.
final class MinifigureTrainingStore: ObservableObject {
    static let shared = MinifigureTrainingStore()

    struct TrainingEntry: Identifiable, Codable {
        let id: UUID
        let date: Date
        let imageName: String                 // filename in images/
        let confirmedFigIds: [String]         // figures the user said were correct
        let rejectedFigIds: [String]          // figures the user said were wrong
        let aiCandidateName: String           // what the AI originally guessed
        let aiConfidence: Double              // original AI confidence
        var userTags: [String]                // user-supplied tags for training

        init(id: UUID, date: Date, imageName: String, confirmedFigIds: [String],
             rejectedFigIds: [String], aiCandidateName: String, aiConfidence: Double,
             userTags: [String] = []) {
            self.id = id
            self.date = date
            self.imageName = imageName
            self.confirmedFigIds = confirmedFigIds
            self.rejectedFigIds = rejectedFigIds
            self.aiCandidateName = aiCandidateName
            self.aiConfidence = aiConfidence
            self.userTags = userTags
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            date = try container.decode(Date.self, forKey: .date)
            imageName = try container.decode(String.self, forKey: .imageName)
            confirmedFigIds = try container.decode([String].self, forKey: .confirmedFigIds)
            rejectedFigIds = try container.decode([String].self, forKey: .rejectedFigIds)
            aiCandidateName = try container.decode(String.self, forKey: .aiCandidateName)
            aiConfidence = try container.decode(Double.self, forKey: .aiConfidence)
            userTags = try container.decodeIfPresent([String].self, forKey: .userTags) ?? []
        }
    }

    @Published private(set) var entries: [TrainingEntry] = []

    private let baseDir: URL
    private let imagesDir: URL
    private let entriesURL: URL

    var entryCount: Int { entries.count }

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        baseDir = docs.appendingPathComponent("minifigureTraining", isDirectory: true)
        imagesDir = baseDir.appendingPathComponent("images", isDirectory: true)
        entriesURL = baseDir.appendingPathComponent("entries.json")

        try? FileManager.default.createDirectory(at: imagesDir,
                                                  withIntermediateDirectories: true)
        loadEntries()
    }

    /// Save a new training entry: the captured image + which figures were correct.
    @discardableResult
    func record(capturedImage: UIImage,
                confirmedFigIds: [String],
                rejectedFigIds: [String] = [],
                aiCandidateName: String,
                aiConfidence: Double,
                userTags: [String] = []) -> TrainingEntry {
        let id = UUID()
        let imageName = "\(id.uuidString).jpg"
        let imageURL = imagesDir.appendingPathComponent(imageName)

        // Save JPEG at moderate quality (~200–400 KB per image)
        if let data = capturedImage.jpegData(compressionQuality: 0.85) {
            try? data.write(to: imageURL, options: .atomic)
        }

        let entry = TrainingEntry(
            id: id,
            date: Date(),
            imageName: imageName,
            confirmedFigIds: confirmedFigIds,
            rejectedFigIds: rejectedFigIds,
            aiCandidateName: aiCandidateName,
            aiConfidence: aiConfidence,
            userTags: userTags
        )
        entries.append(entry)
        saveEntries()
        return entry
    }

    /// Image for a given training entry.
    func image(for entry: TrainingEntry) -> UIImage? {
        let url = imagesDir.appendingPathComponent(entry.imageName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Total disk usage of training data in bytes.
    var diskUsageBytes: Int {
        guard let enumerator = FileManager.default.enumerator(
            at: baseDir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    var diskUsageFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(diskUsageBytes), countStyle: .file)
    }

    // MARK: - Persistence

    private func loadEntries() {
        guard let data = try? Data(contentsOf: entriesURL),
              let decoded = try? JSONDecoder().decode([TrainingEntry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: entriesURL, options: .atomic)
    }
}
