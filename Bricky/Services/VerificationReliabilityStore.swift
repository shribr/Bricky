import Foundation

/// One decile bucket of predicted confidence, with how many verified samples
/// landed in it and how many were correct.
struct ReliabilityBucket: Codable, Identifiable {
    let index: Int            // 0...9  → predicted range [index/10, (index+1)/10)
    var correct: Int
    var total: Int
    var id: Int { index }
    var lowerBound: Double { Double(index) / 10.0 }
    var upperBound: Double { Double(index + 1) / 10.0 }
    /// Midpoint predicted confidence for the bucket (calibration reference).
    var predicted: Double { (lowerBound + upperBound) / 2.0 }
    /// Observed correct rate in this bucket, or nil if empty.
    var observed: Double? { total > 0 ? Double(correct) / Double(total) : nil }
}

/// Persists the outcomes of user verifications of scanned bricks so the app can
/// show a MEASURED accuracy and a reliability curve (predicted vs observed).
/// Plain persistence store, mirroring `BrickCorrectionStore`. Stored at
/// Documents/<directoryName>/reliability.json.
final class VerificationReliabilityStore: ObservableObject {
    static let shared = VerificationReliabilityStore()

    @Published private(set) var buckets: [ReliabilityBucket]   // always 10 entries, index 0...9
    @Published private(set) var totalSamples: Int
    @Published private(set) var totalCorrect: Int

    /// Overall observed accuracy across all verified samples, or nil if none yet.
    var observedAccuracy: Double? { totalSamples > 0 ? Double(totalCorrect) / Double(totalSamples) : nil }

    private let baseDir: URL
    private let entriesURL: URL

    /// Designated init with an injectable directory name so tests are isolated.
    init(directoryName: String = "verificationReliability") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        baseDir = docs.appendingPathComponent(directoryName, isDirectory: true)
        entriesURL = baseDir.appendingPathComponent("reliability.json")

        try? FileManager.default.createDirectory(at: baseDir,
                                                  withIntermediateDirectories: true)

        let loaded = Self.emptyBuckets()
        buckets = loaded
        totalSamples = 0
        totalCorrect = 0
        load()
    }

    /// Record one verification outcome.
    func record(predictedConfidence: Double, wasCorrect: Bool) {
        let clamped = min(1.0, max(0.0, predictedConfidence))
        let idx = min(9, Int(clamped * 10))   // 1.0 → bucket 9
        buckets[idx].total += 1
        if wasCorrect { buckets[idx].correct += 1 }
        recomputeTotals()
        save()
    }

    /// Reset all samples (10 empty buckets).
    func reset() {
        buckets = Self.emptyBuckets()
        totalSamples = 0
        totalCorrect = 0
        save()
    }

    // MARK: - Persistence

    private static func emptyBuckets() -> [ReliabilityBucket] {
        (0...9).map { ReliabilityBucket(index: $0, correct: 0, total: 0) }
    }

    private func recomputeTotals() {
        totalSamples = buckets.reduce(0) { $0 + $1.total }
        totalCorrect = buckets.reduce(0) { $0 + $1.correct }
    }

    private func load() {
        guard let data = try? Data(contentsOf: entriesURL),
              let decoded = try? JSONDecoder().decode([ReliabilityBucket].self, from: data),
              decoded.count == 10 else {
            return
        }
        buckets = decoded
        recomputeTotals()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(buckets) else { return }
        try? data.write(to: entriesURL, options: .atomic)
    }
}
