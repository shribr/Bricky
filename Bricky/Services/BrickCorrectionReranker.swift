import UIKit
import Vision

/// Applies the user's past brick corrections to new scans. When a freshly
/// detected brick's crop looks visually close (Vision feature-print distance)
/// to a brick the user previously corrected, the corrected properties — shape
/// and/or color, whichever the user actually changed — are applied and marked
/// high-confidence.
///
/// This is the brick analogue of `UserCorrectionReranker` (minifigures): a
/// nearest-neighbor classifier on top of the heuristic pipeline, so manual
/// corrections improve later scans with no Core ML retrain. It runs only on the
/// still-capture path (never per live frame) and is a no-op until the user has
/// made at least one correction.
///
/// Deliberately synchronous + nonisolated so it can run on the pipeline's
/// background queue (Vision feature prints are CPU work). The caller passes an
/// immutable `corrections` snapshot to avoid cross-thread `@Published` reads.
final class BrickCorrectionReranker {

    static let shared = BrickCorrectionReranker()

    /// Max feature-print distance for a crop to be treated as the same brick as
    /// a past correction. Conservative so one correction can't hijack every scan.
    static let maxMatchDistance: Float = 12.0

    /// Max L2 distance between a crop's feature vector and a server index entry's
    /// centroid for a global-consensus match. Device-tunable.
    static let serverMaxMatchDistance: Float = 12.0

    private let store: BrickCorrectionStore

    init(store: BrickCorrectionStore = .shared) {
        self.store = store
    }

    /// Override matched detections with the user's corrections. Returns a new
    /// detection list; unmatched detections pass through unchanged.
    func apply(
        to detections: [BrickClassificationPipeline.BrickDetection],
        in sourceImage: UIImage,
        using corrections: [BrickCorrection]
    ) -> [BrickClassificationPipeline.BrickDetection] {
        guard !corrections.isEmpty, !detections.isEmpty,
              let sourceCG = sourceImage.cgImage else { return detections }

        // Feature prints for each stored correction crop.
        var correctionPrints: [(correction: BrickCorrection, print: VNFeaturePrintObservation)] = []
        for correction in corrections {
            guard let image = store.image(for: correction),
                  let cg = image.cgImage,
                  let print = Self.featurePrint(for: cg) else { continue }
            correctionPrints.append((correction, print))
        }
        guard !correctionPrints.isEmpty else { return detections }

        let imgW = CGFloat(sourceCG.width)
        let imgH = CGFloat(sourceCG.height)

        var result: [BrickClassificationPipeline.BrickDetection] = []
        result.reserveCapacity(detections.count)

        for det in detections {
            guard let cropCG = crop(sourceCG, pixelRect: det.pixelRect, imgW: imgW, imgH: imgH),
                  let detPrint = Self.featurePrint(for: cropCG) else {
                result.append(det)
                continue
            }

            var best: (correction: BrickCorrection, distance: Float)?
            for (correction, print) in correctionPrints {
                var distance: Float = 0
                guard (try? print.computeDistance(&distance, to: detPrint)) != nil else { continue }
                if distance <= Self.maxMatchDistance, best == nil || distance < best!.distance {
                    best = (correction, distance)
                }
            }

            if let match = best {
                result.append(applyCorrection(match.correction, to: det))
            } else {
                result.append(det)
            }
        }
        return result
    }

    /// Apply the server's crowdsourced consensus index: for each detection whose
    /// crop feature vector is close to a promoted cluster centroid, adopt that
    /// cluster's promoted shape and/or color. Meant to run BEFORE the user's own
    /// local corrections, which take precedence.
    func applyServerIndex(
        to detections: [BrickClassificationPipeline.BrickDetection],
        in sourceImage: UIImage,
        using entries: [ServerCorrectionEntry]
    ) -> [BrickClassificationPipeline.BrickDetection] {
        guard !entries.isEmpty, !detections.isEmpty, let sourceCG = sourceImage.cgImage else { return detections }

        let entryVectors: [(entry: ServerCorrectionEntry, vector: [Float])] = entries.compactMap { entry in
            guard let data = Data(base64Encoded: entry.embeddingBase64) else { return nil }
            let v = Self.decodeFloat32(data)
            return v.isEmpty ? nil : (entry, v)
        }
        guard !entryVectors.isEmpty else { return detections }

        let imgW = CGFloat(sourceCG.width)
        let imgH = CGFloat(sourceCG.height)

        var result: [BrickClassificationPipeline.BrickDetection] = []
        result.reserveCapacity(detections.count)
        for det in detections {
            guard let cropCG = crop(sourceCG, pixelRect: det.pixelRect, imgW: imgW, imgH: imgH),
                  let vector = Self.featureVector(for: cropCG) else {
                result.append(det)
                continue
            }
            var best: (entry: ServerCorrectionEntry, distance: Float)?
            for (entry, ev) in entryVectors {
                guard let d = Self.l2(vector, ev) else { continue }
                if d <= Self.serverMaxMatchDistance, best == nil || d < best!.distance {
                    best = (entry, d)
                }
            }
            if let match = best {
                result.append(applyServerEntry(match.entry, to: det))
            } else {
                result.append(det)
            }
        }
        return result
    }

    // MARK: - Private

    /// Produce a detection with the corrected properties applied (internal for
    /// deterministic testing without a Vision match).
    func applyCorrection(
        _ c: BrickCorrection,
        to det: BrickClassificationPipeline.BrickDetection
    ) -> BrickClassificationPipeline.BrickDetection {
        BrickClassificationPipeline.BrickDetection(
            boundingBox: det.boundingBox,
            pixelRect: det.pixelRect,
            partNumber: c.correctedShape ? c.partNumber : det.partNumber,
            name: c.correctedShape ? c.name : det.name,
            category: c.correctedShape ? c.category : det.category,
            color: c.correctedColor ? c.color : det.color,
            dimensions: c.correctedShape
                ? PieceDimensions(studsWide: c.studsWide, studsLong: c.studsLong, heightUnits: c.heightUnits)
                : det.dimensions,
            confidence: max(det.confidence, 0.9),
            shapeConfidence: c.correctedShape ? 0.97 : det.shapeConfidence,
            colorConfidence: c.correctedColor ? 0.97 : det.colorConfidence,
            colorHistogram: det.colorHistogram,
            contourPoints: det.contourPoints
        )
    }

    /// Adopt a server consensus entry's promoted shape/color onto a detection.
    /// Internal for deterministic testing. Shape label resolves via the catalog.
    func applyServerEntry(
        _ entry: ServerCorrectionEntry,
        to det: BrickClassificationPipeline.BrickDetection
    ) -> BrickClassificationPipeline.BrickDetection {
        var partNumber = det.partNumber
        var name = det.name
        var category = det.category
        var dimensions = det.dimensions
        var shapeConfidence = det.shapeConfidence
        if let shape = entry.shapeLabel, let piece = LegoPartsCatalog.shared.piece(byPartNumber: shape) {
            partNumber = piece.partNumber
            name = piece.name
            category = piece.category
            dimensions = piece.dimensions
            shapeConfidence = Float(min(0.97, max(Double(det.shapeConfidence), entry.shapeConfidence)))
        }
        var color = det.color
        var colorConfidence = det.colorConfidence
        if let colorRaw = entry.colorLabel, let matched = LegoColor(rawValue: colorRaw) {
            color = matched
            colorConfidence = Float(min(0.97, max(Double(det.colorConfidence), entry.colorConfidence)))
        }
        return BrickClassificationPipeline.BrickDetection(
            boundingBox: det.boundingBox,
            pixelRect: det.pixelRect,
            partNumber: partNumber,
            name: name,
            category: category,
            color: color,
            dimensions: dimensions,
            confidence: max(det.confidence, 0.9),
            shapeConfidence: shapeConfidence,
            colorConfidence: colorConfidence,
            colorHistogram: det.colorHistogram,
            contourPoints: det.contourPoints
        )
    }

    private func crop(_ cg: CGImage, pixelRect: CGRect, imgW: CGFloat, imgH: CGFloat) -> CGImage? {
        let clamped = pixelRect.intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))
        guard !clamped.isEmpty, clamped.width > 4, clamped.height > 4 else { return nil }
        return cg.cropping(to: clamped)
    }

    static func featurePrint(for cg: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([request])
        return request.results?.first as? VNFeaturePrintObservation
    }

    /// The crop's Vision feature print as a raw Float32 vector, for L2 matching
    /// against server centroids (which are stored/averaged the same way).
    static func featureVector(for cg: CGImage) -> [Float]? {
        guard let fp = featurePrint(for: cg) else { return nil }
        let v = decodeFloat32(fp.data)
        return v.isEmpty ? nil : v
    }

    /// Decode little-endian Float32 bytes into a vector (alignment-safe copy).
    static func decodeFloat32(_ data: Data) -> [Float] {
        guard data.count % 4 == 0, !data.isEmpty else { return [] }
        var out = [Float](repeating: 0, count: data.count / 4)
        _ = out.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return out
    }

    /// Euclidean distance between two equal-length vectors.
    static func l2(_ a: [Float], _ b: [Float]) -> Float? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var sum: Float = 0
        for i in a.indices { let d = a[i] - b[i]; sum += d * d }
        return sqrt(sum)
    }
}
