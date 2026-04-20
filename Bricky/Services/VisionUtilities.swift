import UIKit
import Vision

/// Centralized Vision helpers used across identification services.
///
/// Previously these primitives were reimplemented in 3+ places with
/// subtly different scaling, masking past bugs where one call site
/// produced different distance scales than another. Keep all Vision
/// plumbing here so behavior changes are made in one place.
enum VisionUtilities {

    /// Generate a `VNFeaturePrintObservation` for similarity comparison.
    /// Returns nil if Vision fails to produce an observation (rare —
    /// usually only when the image is unreadable).
    static func featurePrint(for cgImage: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return request.results?.first
    }

    /// Compute the distance between two feature prints. Returns
    /// `Float.infinity` on failure so callers can treat the result as
    /// "not similar at all" without unwrapping.
    static func distance(
        _ a: VNFeaturePrintObservation,
        _ b: VNFeaturePrintObservation
    ) -> Float {
        var d: Float = 0
        do {
            try a.computeDistance(&d, to: b)
            return d
        } catch {
            return .infinity
        }
    }

    /// Crop to the most salient subject using Vision's attention-based
    /// saliency, with a small padding margin around the detected region.
    /// Returns nil if no confident salient region is found.
    static func cropToSalientSubject(
        _ cgImage: CGImage,
        marginRatio: CGFloat = 0.03
    ) -> CGImage? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        guard let observation = request.results?.first,
              let salient = observation.salientObjects?.first else {
            return nil
        }

        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let box = salient.boundingBox

        let x = max(0, box.origin.x - marginRatio) * w
        let y = max(0, (1.0 - box.origin.y - box.height) - marginRatio) * h
        let cropW = min(w - x, (box.width + 2 * marginRatio) * w)
        let cropH = min(h - y, (box.height + 2 * marginRatio) * h)

        let cropRect = CGRect(x: x, y: y, width: cropW, height: cropH)
        guard cropRect.width > 10 && cropRect.height > 10 else { return nil }
        return cgImage.cropping(to: cropRect)
    }
}
