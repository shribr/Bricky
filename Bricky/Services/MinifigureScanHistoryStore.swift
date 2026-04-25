import Foundation
import UIKit

/// Persists minifigure scan attempts so users can revisit past identifications.
///
/// Each entry captures:
/// - The original photo the user took
/// - The matched minifigure (if confirmed)
/// - Confidence and reasoning from the identification service
/// - Whether the user confirmed or rejected the match
///
/// Images are stored as compressed JPEGs under `Documents/minifigScanHistory/`.
@MainActor
final class MinifigureScanHistoryStore: ObservableObject {
    static let shared = MinifigureScanHistoryStore()

    struct ScanEntry: Identifiable, Codable {
        let id: UUID
        let date: Date
        let minifigureId: String?
        let minifigureName: String
        let theme: String
        let year: Int
        let confidence: Double
        let reasoning: String
        let imageURL: URL?
        let confirmed: Bool
        /// Short analysis banner title (e.g. "Low confidence match" or "Possible hybrid").
        let analysisSummary: String
        /// Longer analysis explanation (what the AI observed about each region).
        let analysisDetail: String
        /// Debug log from the identification pipeline (phases, cosines, timing).
        let debugLog: String

        /// Local file name for the captured scan image (e.g. "{id}.jpg").
        var capturedImageFilename: String { "\(id.uuidString).jpg" }

        // Backward-compatible decoding for entries saved before analysisSummary/analysisDetail existed.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            date = try c.decode(Date.self, forKey: .date)
            minifigureId = try c.decodeIfPresent(String.self, forKey: .minifigureId)
            minifigureName = try c.decode(String.self, forKey: .minifigureName)
            theme = try c.decode(String.self, forKey: .theme)
            year = try c.decode(Int.self, forKey: .year)
            confidence = try c.decode(Double.self, forKey: .confidence)
            reasoning = try c.decode(String.self, forKey: .reasoning)
            imageURL = try c.decodeIfPresent(URL.self, forKey: .imageURL)
            confirmed = try c.decode(Bool.self, forKey: .confirmed)
            analysisSummary = (try? c.decode(String.self, forKey: .analysisSummary)) ?? ""
            analysisDetail = (try? c.decode(String.self, forKey: .analysisDetail)) ?? ""
            debugLog = (try? c.decode(String.self, forKey: .debugLog)) ?? ""
        }

        init(id: UUID, date: Date, minifigureId: String?, minifigureName: String,
             theme: String, year: Int, confidence: Double, reasoning: String,
             imageURL: URL?, confirmed: Bool, analysisSummary: String = "",
             analysisDetail: String = "", debugLog: String = "") {
            self.id = id
            self.date = date
            self.minifigureId = minifigureId
            self.minifigureName = minifigureName
            self.theme = theme
            self.year = year
            self.confidence = confidence
            self.reasoning = reasoning
            self.imageURL = imageURL
            self.confirmed = confirmed
            self.analysisSummary = analysisSummary
            self.analysisDetail = analysisDetail
            self.debugLog = debugLog
        }
    }

    @Published private(set) var entries: [ScanEntry] = []

    private let maxEntries = 100
    private let jsonURL: URL
    private let imagesDir: URL
    private let jpegQuality: CGFloat = 0.75
    private let maxImageEdge: CGFloat = 1024

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        jsonURL = docs.appendingPathComponent("minifigScanHistory.json")
        imagesDir = docs.appendingPathComponent("minifigScanHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Public API

    /// Record a scan result. Call after the user confirms or rejects a candidate.
    func record(
        figure: Minifigure?,
        candidateName: String,
        confidence: Double,
        reasoning: String,
        capturedImage: UIImage?,
        confirmed: Bool,
        analysisSummary: String = "",
        analysisDetail: String = "",
        debugLog: String = ""
    ) {
        let entry = ScanEntry(
            id: UUID(),
            date: Date(),
            minifigureId: figure?.id,
            minifigureName: figure?.name ?? candidateName,
            theme: figure?.theme ?? "",
            year: figure?.year ?? 0,
            confidence: confidence,
            reasoning: reasoning,
            imageURL: figure?.imageURL,
            confirmed: confirmed,
            analysisSummary: analysisSummary,
            analysisDetail: analysisDetail,
            debugLog: debugLog
        )

        entries.insert(entry, at: 0)

        // Trim old entries
        if entries.count > maxEntries {
            let dropped = Array(entries[maxEntries...])
            entries = Array(entries.prefix(maxEntries))
            for old in dropped { deleteCapturedImage(for: old) }
        }

        save()

        // Save captured image to disk off the main thread
        if let image = capturedImage {
            let url = imageURL(for: entry)
            let maxEdge = maxImageEdge
            let quality = jpegQuality
            let downscaled = Self.downscale(image, maxEdge: maxEdge)
            Task.detached(priority: .utility) {
                if let data = downscaled.jpegData(compressionQuality: quality) {
                    try? data.write(to: url, options: .atomic)
                }
            }
        }
    }

    /// Load the captured scan image for a history entry.
    func capturedImage(for entry: ScanEntry) -> UIImage? {
        let url = imageURL(for: entry)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Delete a single entry.
    func delete(_ entry: ScanEntry) {
        entries.removeAll { $0.id == entry.id }
        deleteCapturedImage(for: entry)
        save()
    }

    /// Delete multiple entries at once.
    func delete(_ ids: Set<UUID>) {
        let toRemove = entries.filter { ids.contains($0.id) }
        for entry in toRemove { deleteCapturedImage(for: entry) }
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    /// Delete all history.
    func deleteAll() {
        for entry in entries { deleteCapturedImage(for: entry) }
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    private func imageURL(for entry: ScanEntry) -> URL {
        imagesDir.appendingPathComponent(entry.capturedImageFilename)
    }

    private func deleteCapturedImage(for entry: ScanEntry) {
        let url = imageURL(for: entry)
        try? FileManager.default.removeItem(at: url)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: jsonURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: jsonURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([ScanEntry].self, from: data)) ?? []
    }

    /// Re-read from disk. Used by pull-to-refresh.
    func reload() {
        load()
    }

    // MARK: - Image helpers

    private static func downscale(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let size = image.size
        let longestEdge = max(size.width, size.height)
        guard longestEdge > maxEdge else { return image }
        let scale = maxEdge / longestEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
