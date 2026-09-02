import Foundation
import UIKit

/// One user correction of a scanned brick: the crop image (on disk) + the
/// answer the user confirmed, and which aspects they actually changed.
struct BrickCorrection: Identifiable, Codable {
    let id: UUID
    let date: Date
    let imageName: String          // filename under images/
    let partNumber: String
    let name: String
    let category: PieceCategory
    let color: LegoColor
    let studsWide: Int
    let studsLong: Int
    let heightUnits: Int
    /// True when the user changed the shape (category/dimensions/name).
    let correctedShape: Bool
    /// True when the user changed the color.
    let correctedColor: Bool

    init(id: UUID, date: Date, imageName: String, partNumber: String, name: String,
         category: PieceCategory, color: LegoColor, studsWide: Int, studsLong: Int,
         heightUnits: Int, correctedShape: Bool, correctedColor: Bool) {
        self.id = id
        self.date = date
        self.imageName = imageName
        self.partNumber = partNumber
        self.name = name
        self.category = category
        self.color = color
        self.studsWide = studsWide
        self.studsLong = studsLong
        self.heightUnits = heightUnits
        self.correctedShape = correctedShape
        self.correctedColor = correctedColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        imageName = try container.decode(String.self, forKey: .imageName)
        partNumber = try container.decode(String.self, forKey: .partNumber)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(PieceCategory.self, forKey: .category)
        color = try container.decode(LegoColor.self, forKey: .color)
        studsWide = try container.decode(Int.self, forKey: .studsWide)
        studsLong = try container.decode(Int.self, forKey: .studsLong)
        heightUnits = try container.decode(Int.self, forKey: .heightUnits)
        correctedShape = try container.decodeIfPresent(Bool.self, forKey: .correctedShape) ?? true
        correctedColor = try container.decodeIfPresent(Bool.self, forKey: .correctedColor) ?? true
    }
}

/// Persists brick corrections (crop JPEG + metadata) so `BrickCorrectionReranker`
/// can boost future scans that look like a past correction. Mirrors
/// `MinifigureTrainingStore`. Stored under Documents/<directoryName>/:
///   corrections.json     — [BrickCorrection]
///   images/<uuid>.jpg    — the corrected brick's crop
final class BrickCorrectionStore: ObservableObject {
    static let shared = BrickCorrectionStore()

    @Published private(set) var corrections: [BrickCorrection] = []
    var count: Int { corrections.count }

    private let baseDir: URL
    private let imagesDir: URL
    private let entriesURL: URL

    /// Designated init with an injectable directory name so tests are isolated.
    init(directoryName: String = "brickCorrections") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        baseDir = docs.appendingPathComponent(directoryName, isDirectory: true)
        imagesDir = baseDir.appendingPathComponent("images", isDirectory: true)
        entriesURL = baseDir.appendingPathComponent("corrections.json")

        try? FileManager.default.createDirectory(at: imagesDir,
                                                  withIntermediateDirectories: true)
        loadEntries()
    }

    /// Record a correction: writes the crop JPEG (quality ~0.85) + appends metadata.
    @discardableResult
    func record(
        crop: UIImage,
        partNumber: String,
        name: String,
        category: PieceCategory,
        color: LegoColor,
        studsWide: Int,
        studsLong: Int,
        heightUnits: Int,
        correctedShape: Bool,
        correctedColor: Bool
    ) -> BrickCorrection {
        let id = UUID()
        let imageName = "\(id.uuidString).jpg"
        let imageURL = imagesDir.appendingPathComponent(imageName)

        if let data = crop.jpegData(compressionQuality: 0.85) {
            try? data.write(to: imageURL, options: .atomic)
        }

        let correction = BrickCorrection(
            id: id,
            date: Date(),
            imageName: imageName,
            partNumber: partNumber,
            name: name,
            category: category,
            color: color,
            studsWide: studsWide,
            studsLong: studsLong,
            heightUnits: heightUnits,
            correctedShape: correctedShape,
            correctedColor: correctedColor
        )
        corrections.append(correction)
        saveEntries()
        return correction
    }

    /// Crop image for a stored correction (nil if the file is missing).
    func image(for correction: BrickCorrection) -> UIImage? {
        let url = imagesDir.appendingPathComponent(correction.imageName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Remove all corrections + their images.
    func clear() {
        try? FileManager.default.removeItem(at: baseDir)
        corrections = []
        try? FileManager.default.createDirectory(at: imagesDir,
                                                  withIntermediateDirectories: true)
    }

    // MARK: - Persistence

    private func loadEntries() {
        guard let data = try? Data(contentsOf: entriesURL),
              let decoded = try? JSONDecoder().decode([BrickCorrection].self, from: data) else {
            return
        }
        corrections = decoded
    }

    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(corrections) else { return }
        try? data.write(to: entriesURL, options: .atomic)
    }
}
