import Foundation
import OSLog

/// In-memory cosine-nearest-neighbor index over the bundled face
/// embedding matrix produced by
/// `Tools/torso-embeddings/embed-face-catalog.py`.
///
/// File layout (under `Bricky/Resources/FaceEmbeddings/`):
///   • `face_embeddings.bin`          — Float16 matrix, row-major,
///                                       `count` rows × `dim` cols.
///                                       Each row is L2-normalized.
///   • `face_embeddings_index.json`   — `{ dim, count, dtype, ids[] }`.
///
/// Both files are OPTIONAL. Until the offline training pipeline runs
/// for the first time they won't exist in the bundle, in which case
/// `FaceEmbeddingIndex.shared.isAvailable == false` and every lookup
/// returns an empty array.
final class FaceEmbeddingIndex {

    static let shared = FaceEmbeddingIndex()

    private static let logger = Logger(
        subsystem: "com.bricky.app",
        category: "FaceEmbeddingIndex"
    )

    struct Hit: Sendable {
        let figureId: String
        let cosine: Float
    }

    let isAvailable: Bool

    private let dim: Int
    private let ids: [String]
    private let matrix: [Float]
    private let meanVec: [Float]?

    private init() {
        let bundle = Bundle.main
        guard let jsonURL = bundle.url(
                forResource: "face_embeddings_index",
                withExtension: "json",
                subdirectory: "FaceEmbeddings"
              ) ?? bundle.url(
                forResource: "face_embeddings_index",
                withExtension: "json"
              ),
              let binURL = bundle.url(
                forResource: "face_embeddings",
                withExtension: "bin",
                subdirectory: "FaceEmbeddings"
              ) ?? bundle.url(
                forResource: "face_embeddings",
                withExtension: "bin"
              ),
              let jsonData = try? Data(contentsOf: jsonURL),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let dim = parsed["dim"] as? Int,
              let count = parsed["count"] as? Int,
              let ids = parsed["ids"] as? [String]
        else {
            Self.logger.info("Face embedding index not bundled — feature disabled")
            self.isAvailable = false
            self.dim = 0
            self.ids = []
            self.matrix = []
            self.meanVec = nil
            return
        }

        guard ids.count == count else {
            Self.logger.error("Face index id count mismatch: ids=\(ids.count) declared=\(count)")
            self.isAvailable = false
            self.dim = 0
            self.ids = []
            self.matrix = []
            self.meanVec = nil
            return
        }

        let rawData: Data
        do {
            rawData = try Data(contentsOf: binURL, options: [.mappedIfSafe])
        } catch {
            Self.logger.error("Failed to load face embedding matrix: \(error.localizedDescription)")
            self.isAvailable = false
            self.dim = 0
            self.ids = []
            self.matrix = []
            self.meanVec = nil
            return
        }

        let expectedBytes = count * dim * MemoryLayout<UInt16>.size
        guard rawData.count == expectedBytes else {
            Self.logger.error("Face matrix size mismatch: bytes=\(rawData.count) expected=\(expectedBytes)")
            self.isAvailable = false
            self.dim = 0
            self.ids = []
            self.matrix = []
            self.meanVec = nil
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

        // Load the mean vector for query centering (optional —
        // older bundles without it still work, just less accurate).
        if let meanURL = bundle.url(
                forResource: "face_embeddings_mean",
                withExtension: "bin",
                subdirectory: "FaceEmbeddings"
            ) ?? bundle.url(
                forResource: "face_embeddings_mean",
                withExtension: "bin"
            ),
           let meanData = try? Data(contentsOf: meanURL),
           meanData.count == dim * MemoryLayout<Float>.size {
            self.meanVec = meanData.withUnsafeBytes { raw in
                Array(raw.bindMemory(to: Float.self))
            }
            Self.logger.info("Loaded mean-centering vector (\(dim)D)")
        } else {
            self.meanVec = nil
        }

        Self.logger.info("Loaded face embedding index: \(count) figures × \(dim)D")
    }

    func nearestNeighbors(of rawQuery: [Float], topK: Int = 16) -> [Hit] {
        guard isAvailable, rawQuery.count == dim, topK > 0 else { return [] }

        // Mean-center the query to match the catalog's post-processing.
        let query: [Float]
        if let mv = meanVec {
            var centered = [Float](repeating: 0, count: dim)
            for d in 0..<dim { centered[d] = rawQuery[d] - mv[d] }
            var norm: Float = 0
            for d in 0..<dim { norm += centered[d] * centered[d] }
            norm = max(sqrt(norm), 1e-8)
            for d in 0..<dim { centered[d] /= norm }
            query = centered
        } else {
            query = rawQuery
        }

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
