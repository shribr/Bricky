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
}
