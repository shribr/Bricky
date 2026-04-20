import Foundation
import OSLog

/// In-memory cosine-nearest-neighbor index over the bundled head
/// embedding matrix produced by
/// `Tools/torso-embeddings/embed-head-catalog.py`.
///
/// File layout (under `Bricky/Resources/HeadEmbeddings/`):
///   • `head_embeddings.bin`          — Float16 matrix, row-major,
///                                       `count` rows × `dim` cols.
///                                       Each row is L2-normalized.
///   • `head_embeddings_index.json`   — `{ dim, count, dtype, ids[] }`.
///
/// Both files are OPTIONAL. Until the offline training pipeline runs
/// for the first time they won't exist in the bundle, in which case
/// `HeadEmbeddingIndex.shared.isAvailable == false` and every lookup
/// returns an empty array.
final class HeadEmbeddingIndex {

    static let shared = HeadEmbeddingIndex()

    private static let logger = Logger(
        subsystem: "com.bricky.app",
        category: "HeadEmbeddingIndex"
    )

    struct Hit: Sendable {
        let figureId: String
        let cosine: Float
    }

    let isAvailable: Bool

    private let dim: Int
    private let ids: [String]
    private let matrix: [Float]

    private init() {
        let bundle = Bundle.main
        guard let jsonURL = bundle.url(
                forResource: "head_embeddings_index",
                withExtension: "json",
                subdirectory: "HeadEmbeddings"
              ) ?? bundle.url(
                forResource: "head_embeddings_index",
                withExtension: "json"
              ),
              let binURL = bundle.url(
                forResource: "head_embeddings",
                withExtension: "bin",
                subdirectory: "HeadEmbeddings"
              ) ?? bundle.url(
                forResource: "head_embeddings",
                withExtension: "bin"
              ),
              let jsonData = try? Data(contentsOf: jsonURL),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let dim = parsed["dim"] as? Int,
              let count = parsed["count"] as? Int,
              let ids = parsed["ids"] as? [String]
        else {
            Self.logger.info("Head embedding index not bundled — feature disabled")
            self.isAvailable = false
            self.dim = 0
            self.ids = []
            self.matrix = []
            return
        }

        guard ids.count == count else {
            Self.logger.error("Head index id count mismatch: ids=\(ids.count) declared=\(count)")
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
            Self.logger.error("Failed to load head embedding matrix: \(error.localizedDescription)")
            self.isAvailable = false
            self.dim = 0
            self.ids = []
            self.matrix = []
            return
        }

        let expectedBytes = count * dim * MemoryLayout<UInt16>.size
        guard rawData.count == expectedBytes else {
            Self.logger.error("Head matrix size mismatch: bytes=\(rawData.count) expected=\(expectedBytes)")
            self.isAvailable = false
            self.dim = 0
            self.ids = []
            self.matrix = []
            return
        }

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
        Self.logger.info("Loaded head embedding index: \(count) figures × \(dim)D")
    }

    func nearestNeighbors(of query: [Float], topK: Int = 16) -> [Hit] {
        guard isAvailable, query.count == dim, topK > 0 else { return [] }

        let count = ids.count
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
