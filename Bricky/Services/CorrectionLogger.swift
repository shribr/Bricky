import Foundation

/// Logs user corrections to piece identifications for future model improvement.
/// Persists correction data as JSONL (one JSON object per line) for easy batch export.
final class CorrectionLogger {
    static let shared = CorrectionLogger()

    struct Correction: Codable {
        let timestamp: Date
        let originalPartNumber: String
        let originalName: String
        let originalCategory: String
        let originalColor: String
        let originalStudsWide: Int
        let originalStudsLong: Int
        let originalConfidence: Double
        let correctedName: String
        let correctedCategory: String
        let correctedColor: String
        let correctedStudsWide: Int
        let correctedStudsLong: Int
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: AppConfig.correctionLoggerQueue)
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("corrections.jsonl")
    }

    /// Log a correction made by the user
    func logCorrection(original: LegoPiece, correctedName: String, correctedCategory: PieceCategory,
                       correctedColor: LegoColor, correctedStudsWide: Int, correctedStudsLong: Int) {
        let correction = Correction(
            timestamp: Date(),
            originalPartNumber: original.partNumber,
            originalName: original.name,
            originalCategory: original.category.rawValue,
            originalColor: original.color.rawValue,
            originalStudsWide: original.dimensions.studsWide,
            originalStudsLong: original.dimensions.studsLong,
            originalConfidence: original.confidence,
            correctedName: correctedName,
            correctedCategory: correctedCategory.rawValue,
            correctedColor: correctedColor.rawValue,
            correctedStudsWide: correctedStudsWide,
            correctedStudsLong: correctedStudsLong
        )

        queue.async { [weak self] in
            guard let self, let data = try? self.encoder.encode(correction),
                  let line = String(data: data, encoding: .utf8) else { return }

            let entry = line + "\n"
            if let entryData = entry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                        handle.seekToEndOfFile()
                        handle.write(entryData)
                        handle.closeFile()
                    }
                } else {
                    try? entryData.write(to: self.fileURL)
                }
            }
        }
    }

    /// Total number of logged corrections
    var correctionCount: Int {
        guard let data = try? String(contentsOf: fileURL, encoding: .utf8) else { return 0 }
        return data.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    }

    /// Export all corrections as a JSONL string (for training data upload)
    func exportCorrections() -> String? {
        try? String(contentsOf: fileURL, encoding: .utf8)
    }

    /// Export corrections as an array of Correction objects
    func loadCorrections() -> [Correction] {
        guard let data = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(Correction.self, from: lineData)
            }
    }

    /// Clear all logged corrections
    func clearCorrections() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
