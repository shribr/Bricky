import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Optional pre-processing pipeline applied to scanned minifigure photos
/// before they enter the identification service.
///
/// Steps (all best-effort, any failure falls back to the previous stage):
///   1. Auto-crop around the salient subject (Vision saliency) with a
///      small padding margin. Falls back to a centered 70% crop.
///   2. CoreImage auto-adjustments (exposure, tone, contrast, saturation,
///      red-eye). Applies enhancement only if the filter chain returns a
///      valid image; otherwise the un-enhanced crop is returned.
///   3. Output is re-baked into a UIImage with `.up` orientation so all
///      downstream consumers see a consistent bitmap.
///
/// This enhancer is intentionally conservative — it should never hurt
/// scan quality. If the captured image is already good, enhancement is
/// a no-op.
enum ScanImageEnhancer {

    /// User-facing toggle persisted in UserDefaults. Defaults to ON.
    static var isEnabled: Bool {
        get {
            // UserDefaults returns false for a missing key, so mirror
            // the default (ON) via a "has-set" sentinel.
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    private static let enabledKey = "scanAutoEnhanceEnabled"

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Apply auto-crop + enhance to a scanned image. Always returns a
    /// valid UIImage — on any failure, returns the input unchanged.
    static func enhance(_ image: UIImage) -> UIImage {
        let oriented = image.normalizedOrientation()
        guard let cg = oriented.cgImage else { return oriented }

        // 1. Auto-crop around the subject with padding.
        let croppedCG = autoCrop(cgImage: cg) ?? cg

        // 2. Auto-enhance with CoreImage.
        let ci = CIImage(cgImage: croppedCG)
        let enhanced = applyAutoAdjustments(to: ci) ?? ci

        // 3. Bake back to UIImage.
        guard let finalCG = ciContext.createCGImage(enhanced, from: enhanced.extent) else {
            return UIImage(cgImage: croppedCG)
        }
        return UIImage(cgImage: finalCG, scale: oriented.scale, orientation: .up)
    }

    /// Async variant — runs the (sometimes 100–500 ms) enhance pipeline
    /// off the main actor so the scan view's animation stays buttery.
    static func enhanceAsync(_ image: UIImage) async -> UIImage {
        await Task.detached(priority: .userInitiated) {
            enhance(image)
        }.value
    }

    // MARK: - Step 1: Auto-crop

    /// Crop around the most salient subject with a 12% padding margin so
    /// the subject isn't hugging the frame. Falls back to a centered
    /// 70% crop if saliency doesn't resolve a confident region.
    private static func autoCrop(cgImage: CGImage) -> CGImage? {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)

        if let salient = salientRect(for: cgImage) {
            // Pad the salient rect by 12% on each side, clamped to
            // image bounds. Keeps minifigure's full body in frame
            // even if saliency locked onto only the torso.
            let padX = salient.width * 0.12
            let padY = salient.height * 0.12
            let padded = CGRect(
                x: max(0, salient.minX - padX),
                y: max(0, salient.minY - padY),
                width: min(w - max(0, salient.minX - padX), salient.width + padX * 2),
                height: min(h - max(0, salient.minY - padY), salient.height + padY * 2)
            )
            // Only use saliency if it's actually narrower than a plain
            // 90% centered crop — otherwise it's not saving us anything.
            if padded.width < w * 0.90 && padded.height < h * 0.90 {
                return cgImage.cropping(to: padded)
            }
        }

        // Fallback: centered 70% × 85% crop (roughly matches the
        // viewfinder silhouette rectangle used in the scan UI).
        let cropW = w * 0.70
        let cropH = h * 0.85
        let rect = CGRect(
            x: (w - cropW) / 2,
            y: (h - cropH) / 2,
            width: cropW,
            height: cropH
        )
        return cgImage.cropping(to: rect)
    }

    /// Run Vision attention-based saliency and return the tightest
    /// bounding box in CGImage pixel coordinates (origin top-left).
    private static func salientRect(for cgImage: CGImage) -> CGRect? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard
            let observation = request.results?.first,
            let salientObjects = observation.salientObjects,
            !salientObjects.isEmpty
        else { return nil }

        // Union of all salient boxes (normalized, Vision's bottom-left origin).
        var union = salientObjects[0].boundingBox
        for i in 1..<salientObjects.count {
            union = union.union(salientObjects[i].boundingBox)
        }
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        // Flip Y to CGImage's top-left origin.
        let rect = CGRect(
            x: union.minX * w,
            y: (1 - union.minY - union.height) * h,
            width: union.width * w,
            height: union.height * h
        )
        return rect.integral
    }

    // MARK: - Step 2: Auto-enhance

    /// Apply CoreImage's built-in auto-adjustment filter chain (exposure,
    /// contrast, saturation, tone curve, temperature/tint). Cheap and
    /// conservative — it's the same pipeline Photos.app's "Enhance" uses.
    private static func applyAutoAdjustments(to image: CIImage) -> CIImage? {
        let filters = image.autoAdjustmentFilters(options: [
            .redEye: false,
            .crop: false,     // we already cropped
            .level: true,
            .enhance: true
        ])
        guard !filters.isEmpty else { return nil }
        var current = image
        for filter in filters {
            filter.setValue(current, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                current = output
            }
        }
        return current
    }
}
