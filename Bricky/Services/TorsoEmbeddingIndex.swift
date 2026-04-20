import Foundation
import OSLog

/// In-memory cosine-nearest-neighbor index over the bundled torso
/// embedding matrix produced by
/// `Tools/torso-embeddings/embed-torso-catalog.py`.
///
/// File layout (under `Bricky/Resources/TorsoEmbeddings/`):
///   • `torso_embeddings.bin`         — Float16 matrix, row-major,
///                                       `count` rows × `dim` cols.
///                                       Each row is L2-normalized.
///   • `torso_embeddings_index.json`  — `{ dim, count, dtype, ids[] }`.
///
/// Both files are OPTIONAL. Until the offline training pipeline runs
/// for the first time they won't exist in the bundle, in which case
/// `TorsoEmbeddingIndex.shared.isAvailable == false` and every lookup
/// returns an empty array — callers should treat it as "feature
/// disabled" rather than as an error.
///
/// Memory cost when loaded: ~16 K × 512 × 2 bytes ≈ 16 MB. The
/// embeddings live as a single `Data` blob and we read them as a
/// flat `[Float]` slice on demand — no per-row heap allocation.
final class TorsoEmbeddingIndex {

    static let shared = TorsoEmbeddingIndex()

    private static let logger = Logger(
        subsystem: "com.bricky.app",
        category: "TorsoEmbeddingIndex"
    )

    /// One nearest-neighbor result.
    struct Hit: Sendable {
        /// `id` of the figure in `MinifigureCatalog` (matches what the
        /// embedding pipeline wrote to `ids[]` in the index JSON).
        let figureId: String
        /// Cosine similarity in `[-1, 1]`. Higher = more similar.
        /// Because every row is L2-normalized this is the dot product.
        let cosine: Float
    }

    /// True when both the index JSON and the .bin matrix loaded
    /// successfully. False otherwise — caller should fall back.
    let isAvailable: Bool

    private let dim: Int
    private let ids: [String]
    /// Flat buffer of `count * dim` Float32 values, converted from
    /// the on-disk Float16 once at load time. Using Float32 in memory
    /// avoids per-query conversion and lets us use Accelerate later
    /// without code changes — the size delta (16 MB → 32 MB) is still
    /// well under the iOS budget for a foreground app.
    private let matrix: [Float]

    private init() {
        // Lazy-load the artifacts. Both files must exist or we're off.
        let bundle = Bundle.main
        guard let jsonURL = bundle.url(
                forResource: "torso_embeddings_index",
                withExtension: "json",
                subdirectory: "TorsoEmbeddings"
              ) ?? bundle.url(
                forResource: "torso_embeddings_index",
                withExtension: "json"
              ),
              let binURL = bundle.url(
                forResource: "torso_embeddings",
                withExtension: "bin",
                subdirectory: "TorsoEmbeddings"
              ) ?? bundle.url(
                forResource: "torso_embeddings",
                withExtension: "bin"
              ),
              let jsonData = try? Data(contentsOf: jsonURL),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let dim = parsed["dim"] as? Int,
              let count = parsed["count"] as? Int,
              let ids = parsed["ids"] as? [String]
        else {
            Self.logger.info("Torso embedding index not bundled — feature disabled")
            self.isAvailable = false
            self.dim = 0
            self.ids = []
            self.matrix = []
            return
        }

        guard ids.count == count else {
            Self.logger.error("Torso index id count mismatch: ids=\(ids.count) declared=\(count)")
            self.isAvailable = false
            self.dim = 0
            self.ids = []
            self.matrix = []
            return
        }

        let rawData: Data
        do {
            rawData = try Data(contentsOf: binURL, options: [.mappedIfSafe])
        } catch {
            Self.logger.error("Failed to load torso embedding matrix: \(error.localizedDescription)")
            self.isAvailable = false
            self.dim = 0
            self.ids = []
            self.matrix = []
            return
        }

        let expectedBytes = count * dim * MemoryLayout<UInt16>.size
        guard rawData.count == expectedBytes else {
            Self.logger.error("Torso matrix size mismatch: bytes=\(rawData.count) expected=\(expectedBytes)")
            self.isAvailable = false
            self.dim = 0
            self.ids = []
            self.matrix = []
            return
        }

        // Convert Float16 → Float32 once. iOS 14+ has Float16 as a
        // first-class type so this is a straight pointer cast then a
        // simple copy.
        let floats: [Float] = rawData.withUnsafeBytes { raw -> [Float] in
            let half = raw.bindMemory(to: Float16.self)
            var out = [Float]()
            out.reserveCapacity(half.count)
            for v in half { out.append(Float(v)) }
            return out
        }

        self.isAvailable = true
        self.dim = dim
        self.ids = ids
        self.matrix = floats
        Self.logger.info("Loaded torso embedding index: \(count) figures × \(dim)D")
    }

    /// Top-K nearest neighbors of a query embedding, by cosine
    /// similarity. The query MUST be L2-normalized and have the same
    /// dimensionality as the index — anything else returns `[]`.
    func nearestNeighbors(of query: [Float], topK: Int = 16) -> [Hit] {
        guard isAvailable, query.count == dim, topK > 0 else { return [] }

        let count = ids.count
        // Maintain a simple bounded min-heap as a fixed-size array.
        // For our K (≤32) the linear-scan-then-keep-best approach is
        // faster and simpler than a real heap.
        var best: [(Int, Float)] = []
        best.reserveCapacity(topK)

        matrix.withUnsafeBufferPointer { mptr in
            query.withUnsafeBufferPointer { qptr in
                let m = mptr.baseAddress!
                let q = qptr.baseAddress!
                for row in 0..<count {
                    var dot: Float = 0
                    let base = row * dim
                    for d in 0..<dim {
                        dot += m[base + d] * q[d]
                    }
                    if best.count < topK {
                        best.append((row, dot))
                        if best.count == topK {
                            best.sort { $0.1 < $1.1 }
                        }
                    } else if dot > best[0].1 {
                        best[0] = (row, dot)
                        // Re-sink to keep best[0] as the smallest.
                        var i = 0
                        while i + 1 < best.count && best[i].1 > best[i + 1].1 {
                            best.swapAt(i, i + 1)
                            i += 1
                        }
                    }
                }
            }
        }

        return best
            .sorted { $0.1 > $1.1 }
            .map { Hit(figureId: ids[$0.0], cosine: $0.1) }
    }
}
