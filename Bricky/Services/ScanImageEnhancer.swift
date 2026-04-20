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
    private static let enabledKey = UserDefaultsKey.scanAutoEnhanceEnabled

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
    /// the subject isn't hugging the frame. Falls back through:
    ///   1. Attention-based saliency (where the eye looks)
    ///   2. Objectness-based saliency (where distinct objects are) —
    ///      better for small subjects on busy backgrounds.
    ///   3. No crop at all — better than blind-centering an off-center
    ///      subject (which would clip the figure entirely).
    private static func autoCrop(cgImage: CGImage) -> CGImage? {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)

        // Try attention-based saliency first.
        if let salient = salientRect(for: cgImage),
           let cropped = paddedCrop(of: salient, in: cgImage, imageW: w, imageH: h) {
            return cropped
        }

        // Fall back to objectness-based saliency (better for small subjects
        // on busy backgrounds — e.g. a minifigure on a paper-covered desk).
        if let salient = objectnessRect(for: cgImage),
           let cropped = paddedCrop(of: salient, in: cgImage, imageW: w, imageH: h) {
            return cropped
        }

        // No reliable salient region found. Return the original image
        // rather than a blind centered crop — the figure may be off-center,
        // and clipping it out is worse than skipping the crop step.
        return cgImage
    }

    /// Apply 12% padding around a salient rect and return the cropped
    /// CGImage, but only if the result is meaningfully tighter than the
    /// source (otherwise the crop saves nothing).
    private static func paddedCrop(of rect: CGRect, in cgImage: CGImage, imageW w: CGFloat, imageH h: CGFloat) -> CGImage? {
        let padX = rect.width * 0.12
        let padY = rect.height * 0.12
        let padded = CGRect(
            x: max(0, rect.minX - padX),
            y: max(0, rect.minY - padY),
            width: min(w - max(0, rect.minX - padX), rect.width + padX * 2),
            height: min(h - max(0, rect.minY - padY), rect.height + padY * 2)
        )
        guard padded.width < w * 0.92 && padded.height < h * 0.92 else { return nil }
        // Sanity: salient region should be at least 5% of the image — if
        // smaller, it's noise (camera glare, sticker, etc), not a figure.
        guard (padded.width * padded.height) / (w * h) > 0.05 else { return nil }
        return cgImage.cropping(to: padded)
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

    /// Run Vision objectness-based saliency and return the LARGEST single
    /// salient object (not the union — multiple objects on a busy desk
    /// would union into the entire frame). Better than attention saliency
    /// for small minifigures on cluttered surfaces.
    private static func objectnessRect(for cgImage: CGImage) -> CGRect? {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
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

        // Pick the object with the most figure-like aspect ratio (tall &
        // narrow), tie-broken by area. Minifigures are ~2:1 portrait.
        let scored = salientObjects.map { obj -> (VNRectangleObservation, Double) in
            let box = obj.boundingBox
            let aspect = Double(box.height / max(box.width, 0.01))
            // Score peaks at aspect 2.0 (typical minifigure)
            let aspectScore = 1.0 - min(1.0, abs(aspect - 2.0) / 2.0)
            let areaScore = Double(box.width * box.height)
            return (obj, aspectScore * 0.6 + areaScore * 0.4)
        }
        guard let best = scored.max(by: { $0.1 < $1.1 })?.0 else { return nil }

        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let box = best.boundingBox
        let rect = CGRect(
            x: box.minX * w,
            y: (1 - box.minY - box.height) * h,
            width: box.width * w,
            height: box.height * h
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
