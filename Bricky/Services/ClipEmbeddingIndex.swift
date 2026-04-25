import Accelerate
import Foundation
import OSLog

/// In-memory cosine-nearest-neighbor index over the bundled CLIP
/// embedding matrix produced by `Tools/embed_clip_catalog.py`.
///
/// File layout (under `Bricky/Resources/ClipEmbeddings/`):
///   • `clip_embeddings.bin`         — Float16 matrix, row-major,
///                                      `count` rows × `dim` cols.
///                                      Each row is L2-normalized.
///   • `clip_embeddings_index.json`  — `{ dim, count, dtype, ids[] }`.
///
/// Both files are OPTIONAL. Until the embedding pipeline runs for the
/// first time they won't exist in the bundle, in which case
/// `ClipEmbeddingIndex.shared.isAvailable == false` and every lookup
/// returns an empty array.
final class ClipEmbeddingIndex {

    static let shared = ClipEmbeddingIndex()

    private static let logger = Logger(
        subsystem: "com.bricky.app",
        category: "ClipEmbeddingIndex"
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
                forResource: "clip_embeddings_index",
                withExtension: "json",
                subdirectory: "ClipEmbeddings"
              ) ?? bundle.url(
                forResource: "clip_embeddings_index",
                withExtension: "json"
              ),
              let binURL = bundle.url(
                forResource: "clip_embeddings",
                withExtension: "bin",
                subdirectory: "ClipEmbeddings"
              ) ?? bundle.url(
                forResource: "clip_embeddings",
                withExtension: "bin"
              ),
              let jsonData = try? Data(contentsOf: jsonURL),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let dim = parsed["dim"] as? Int,
              let count = parsed["count"] as? Int,
              let ids = parsed["ids"] as? [String]
        else {
            Self.logger.info("CLIP embedding index not bundled — feature disabled")
            self.isAvailable = false
            self.dim = 0
            self.ids = []
            self.matrix = []
            return
        }

        guard ids.count == count else {
            Self.logger.error("CLIP index id count mismatch: ids=\(ids.count) declared=\(count)")
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
            Self.logger.error("Failed to load CLIP embedding matrix: \(error.localizedDescription)")
            self.isAvailable = false
            self.dim = 0
            self.ids = []
            self.matrix = []
            return
        }

        let expectedBytes = count * dim * MemoryLayout<UInt16>.size
        guard rawData.count == expectedBytes else {
            Self.logger.error("CLIP matrix size mismatch: bytes=\(rawData.count) expected=\(expectedBytes)")
            self.isAvailable = false
            self.dim = 0
            self.ids = []
            self.matrix = []
            return
        }

        // Convert Float16 → Float32 once at load time using Accelerate.
        let totalElements = count * dim
        let floats: [Float] = rawData.withUnsafeBytes { raw -> [Float] in
            let halfPtr = raw.baseAddress!.assumingMemoryBound(to: UInt16.self)
            var out = [Float](repeating: 0, count: totalElements)
            var src = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: halfPtr),
                                    height: 1, width: vImagePixelCount(totalElements),
                                    rowBytes: totalElements * MemoryLayout<UInt16>.size)
            var dst = vImage_Buffer(data: &out,
                                    height: 1, width: vImagePixelCount(totalElements),
                                    rowBytes: totalElements * MemoryLayout<Float>.size)
            vImageConvert_Planar16FtoPlanarF(&src, &dst, 0)
            return out
        }

        self.isAvailable = true
        self.dim = dim
        self.ids = ids
        self.matrix = floats

        Self.logger.info("Loaded CLIP embedding index: \(count) figures × \(dim)D")
    }

    /// Top-K nearest neighbors by cosine similarity.
    /// Query MUST be L2-normalized with matching dimensionality.
    func nearestNeighbors(of query: [Float], topK: Int = 16) -> [Hit] {
        guard isAvailable, query.count == dim, topK > 0 else { return [] }

        let count = ids.count
        var best: [(Int, Float)] = []
        best.reserveCapacity(topK)

        matrix.withUnsafeBufferPointer { mptr in
            query.withUnsafeBufferPointer { qptr in
                for row in 0..<count {
                    let base = row * dim
                    var dot: Float = 0
                    // Use Accelerate for SIMD-optimized dot product.
                    vDSP_dotpr(mptr.baseAddress! + base, 1,
                               qptr.baseAddress!, 1,
                               &dot, vDSP_Length(dim))
                    if best.count < topK {
                        best.append((row, dot))
                        if best.count == topK {
                            best.sort { $0.1 > $1.1 }
                        }
                    } else if dot > best[topK - 1].1 {
                        best[topK - 1] = (row, dot)
                        // Insertion sort to maintain order.
                        var i = topK - 1
                        while i > 0 && best[i].1 > best[i - 1].1 {
                            best.swapAt(i, i - 1)
                            i -= 1
                        }
                    }
                }
            }
        }

        if best.count > topK { best = Array(best.prefix(topK)) }
        if best.count > 1 && best.first!.1 < best.last!.1 {
            best.sort { $0.1 > $1.1 }
        }

        return best.map { Hit(figureId: ids[$0.0], cosine: $0.1) }
    }
}
