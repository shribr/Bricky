import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import UIKit
import Vision

/// Offline "scan a photo / live subject → brick model" adapter.
///
/// Turns a single photo into a colored `VoxelModel`:
/// 1. Isolate the subject with a Vision cascade — person segmentation →
///    foreground-instance mask → attention saliency. The subject is cut out
///    onto a transparent background and cropped tightly to its bounding box, so
///    the fixed grid budget is spent on the subject rather than empty scenery.
///    If every stage fails we fall back to a centre crop (never the whole noisy
///    scene) so the result stays focused and the feature stays robust.
/// 2. Aspect-fit the masked subject into a stud grid and quantize each cell to
///    the nearest `LegoColor` (shared perceptual matcher).
/// 3. Extrude the silhouette into a chunky flat relief that lies on the table —
///    every column is ground-supported, so the result is always buildable.
///
/// This is the fully offline M1 path. Multi-photo Object Capture → true
/// volumetric reconstruction is the planned Phase-2 upgrade (see
/// `docs/SET-FORGE-PLAN.md`); it produces a richer `VoxelModel` for the same
/// engine without changing this contract.
enum PhotoVoxelizer {

    enum VoxelizeError: LocalizedError {
        case unreadableImage
        case noSubject

        var errorDescription: String? {
            switch self {
            case .unreadableImage:
                return "That image couldn't be read. Try another photo."
            case .noSubject:
                return "No clear subject was found in the photo. Try a photo with a single subject on a plain background."
            }
        }
    }

    /// Build a voxel model from a photo.
    ///
    /// - Parameters:
    ///   - image: The source photo.
    ///   - size: Target size preset (sets the grid's longest side).
    ///   - subject: Caption for naming the resulting set.
    static func voxelize(
        image: UIImage,
        size: VoxelModel.Size,
        subject: String = "Photo"
    ) throws -> VoxelModel {
        guard let cg = image.normalizedOrientation().cgImage else {
            throw VoxelizeError.unreadableImage
        }

        // 1. Isolate the subject (person / foreground / saliency, else a centre
        //    crop) so busy backgrounds don't dominate the model.
        let masked = isolatedSubject(cg)

        // 2. Grid dimensions from the *subject* aspect ratio (post-crop), longest
        //    side = maxDim, so the budget is spent on the subject, not scenery.
        let maxDim = size.maxDimension
        let aspect = Double(masked.width) / Double(masked.height)
        let gridW: Int
        let gridH: Int
        if aspect >= 1 {
            gridW = maxDim
            gridH = max(6, Int((Double(maxDim) / aspect).rounded()))
        } else {
            gridH = maxDim
            gridW = max(6, Int((Double(maxDim) * aspect).rounded()))
        }

        guard let pixels = downsampleAspectFit(masked, targetWidth: gridW, targetHeight: gridH) else {
            throw VoxelizeError.unreadableImage
        }

        // 3. Occupancy + colour grid from the masked pixels.
        var occupied = [Bool](repeating: false, count: gridW * gridH)
        var cellColors = [LegoColor](repeating: .gray, count: gridW * gridH)
        for row in 0..<gridH {
            for col in 0..<gridW {
                let offset = (row * gridW + col) * 4
                guard pixels[offset + 3] >= 40 else { continue } // background
                guard let match = LegoColor.closest(
                    r: pixels[offset], g: pixels[offset + 1], b: pixels[offset + 2],
                    excludeTransparent: true
                ) else { continue }
                let idx = row * gridW + col
                occupied[idx] = true
                cellColors[idx] = match.color
            }
        }

        // 4. Distance transform → a rounded bas-relief height map, so the subject
        //    bulges up from the table into a genuine 3D form (not a flat slab).
        //    Gravity-safe: each column is filled from y = 0, so nothing floats.
        let dist = distanceTransform(occupied, width: gridW, height: gridH)
        let maxDist = Float(dist.max() ?? 0)
        let maxRelief = max(3, maxDim / 3)

        var voxels: [Voxel] = []
        voxels.reserveCapacity(gridW * gridH * 2)
        var maxHeight = 1
        for row in 0..<gridH {
            for col in 0..<gridW {
                let idx = row * gridW + col
                guard occupied[idx] else { continue }
                let h = maxDist > 0
                    ? 1 + Int((Float(dist[idx]) / maxDist) * Float(maxRelief))
                    : 1
                let z = gridH - 1 - row
                let color = cellColors[idx]
                for y in 0..<max(1, h) {
                    voxels.append(Voxel(x: col, y: y, z: z, color: color))
                }
                maxHeight = max(maxHeight, h)
            }
        }

        guard !voxels.isEmpty else { throw VoxelizeError.noSubject }

        return VoxelModel(
            width: gridW,
            height: maxHeight,
            depth: gridH,
            voxels: voxels,
            source: .photo,
            subject: subject
        )
    }

    /// Two-pass chamfer distance transform: distance from each occupied cell to
    /// the nearest background cell. Higher in the interior → taller relief.
    private static func distanceTransform(_ occ: [Bool], width: Int, height: Int) -> [Int] {
        let inf = width + height
        var d = [Int](repeating: 0, count: width * height)
        for i in 0..<occ.count { d[i] = occ[i] ? inf : 0 }
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                guard occ[i] else { continue }
                if x > 0 { d[i] = min(d[i], d[i - 1] + 1) }
                if y > 0 { d[i] = min(d[i], d[i - width] + 1) }
            }
        }
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: width - 1, through: 0, by: -1) {
                let i = y * width + x
                guard occ[i] else { continue }
                if x < width - 1 { d[i] = min(d[i], d[i + 1] + 1) }
                if y < height - 1 { d[i] = min(d[i], d[i + width] + 1) }
            }
        }
        return d
    }

    // MARK: - Vision subject isolation cascade

    /// Minimum fraction of the image the person mask must cover before we trust
    /// it (guards against tiny spurious masks in a busy scene).
    private static let minPersonCoverage = 0.02

    /// Isolate the photo's subject onto a transparent, tightly-cropped canvas.
    ///
    /// Cascade (first success wins):
    /// 1. `VNGeneratePersonSegmentationRequest` (accurate) — people/faces, the
    ///    common "scan me" case. Mask applied as alpha, cropped to the subject.
    /// 2. `VNGenerateForegroundInstanceMaskRequest` — general foreground objects.
    /// 3. `VNGenerateAttentionBasedSaliencyImageRequest` — crop the original to
    ///    the salient region (no transparency) so we at least focus attention.
    /// 4. Fallback → a centre crop, so edge/background clutter never dominates
    ///    even when Vision finds no explicit subject (also keeps the feature
    ///    robust where Vision is unavailable).
    private static func isolatedSubject(_ cg: CGImage) -> CGImage {
        if let person = personSegmentedSubject(cg) { return person }
        if let foreground = foregroundMasked(cg) { return foreground }
        if let salient = saliencyCropped(cg) { return salient }
        return centerCropped(cg)
    }

    /// Keep the central `fraction` of each axis — a safe fallback biased to where
    /// subjects usually sit, dropping the busy edges of a scene.
    static func centerCropped(_ cg: CGImage, fraction: CGFloat = 0.7) -> CGImage {
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let cw = max(1, (w * fraction).rounded()), ch = max(1, (h * fraction).rounded())
        let rect = CGRect(x: ((w - cw) / 2).rounded(), y: ((h - ch) / 2).rounded(), width: cw, height: ch)
        return cg.cropping(to: rect) ?? cg
    }

    /// Person/face segmentation → subject composited on a transparent background
    /// and cropped to its alpha bounding box. `nil` if unavailable, empty, or the
    /// mask covers too little of the frame to be a real subject.
    private static func personSegmentedSubject(_ cg: CGImage) -> CGImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            guard let mask = request.results?.first?.pixelBuffer else { return nil }

            let source = CIImage(cgImage: cg)
            var maskImage = CIImage(cvPixelBuffer: mask)
            // Person mask is at model resolution; scale it up to the photo.
            let sx = source.extent.width / maskImage.extent.width
            let sy = source.extent.height / maskImage.extent.height
            maskImage = maskImage.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

            let clear = CIImage(color: .clear).cropped(to: source.extent)
            guard let blend = CIFilter(
                name: "CIBlendWithMask",
                parameters: [
                    kCIInputImageKey: source,
                    kCIInputBackgroundImageKey: clear,
                    kCIInputMaskImageKey: maskImage
                ]
            )?.outputImage else { return nil }

            let context = CIContext(options: nil)
            guard let composited = context.createCGImage(blend, from: source.extent),
                  let rgba = rgbaBytes(from: composited) else { return nil }

            guard let bounds = alphaBounds(
                rgba: rgba.bytes, width: rgba.width, height: rgba.height
            ), bounds.coverage >= minPersonCoverage else { return nil }

            return composited.cropping(to: bounds.rect)
        } catch {
            return nil
        }
    }

    /// Returns the subject cut out onto a transparent background, or `nil` if
    /// segmentation isn't available or finds nothing.
    private static func foregroundMasked(_ cg: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            guard let result = request.results?.first,
                  !result.allInstances.isEmpty else { return nil }
            let buffer = try result.generateMaskedImage(
                ofInstances: result.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            return cgImage(from: buffer)
        } catch {
            return nil
        }
    }

    /// Attention-based saliency → crop the *original* image to the most salient
    /// region (opaque, no transparency). `nil` if nothing salient is found.
    private static func saliencyCropped(_ cg: CGImage) -> CGImage? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first as? VNSaliencyImageObservation
            else { return nil }
            // Prefer the highest-confidence salient object; fall back to the
            // observation's overall salient bounding box.
            let normalized = observation.salientObjects?
                .max(by: { $0.confidence < $1.confidence })?
                .boundingBox
            guard let box = normalized else { return nil }
            let rect = pixelRect(
                fromNormalized: box, imageWidth: cg.width, imageHeight: cg.height
            )
            guard rect.width >= 1, rect.height >= 1 else { return nil }
            return cg.cropping(to: rect.integral)
        } catch {
            return nil
        }
    }

    private static func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        return context.createCGImage(ciImage, from: ciImage.extent)
    }

    /// Read an RGBA byte buffer (premultiplied-last, top-left origin) from a
    /// `CGImage` so alpha coverage can be measured with `alphaBounds`.
    private static func rgbaBytes(from cg: CGImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? (data, width, height) : nil
    }

    // MARK: - Pure crop geometry (unit-testable)

    /// Bounding box (top-left origin, pixel coordinates) of the non-transparent
    /// pixels in an RGBA (premultiplied-last) buffer, plus the fraction of pixels
    /// above `alphaThreshold`. `nil` when nothing clears the threshold.
    ///
    /// Pure function — no Vision/CoreImage — so it is deterministic in tests.
    static func alphaBounds(
        rgba: [UInt8],
        width: Int,
        height: Int,
        alphaThreshold: UInt8 = 1
    ) -> (rect: CGRect, coverage: Double)? {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        var covered = 0
        for y in 0..<height {
            let rowBase = y * width * 4
            for x in 0..<width {
                let alpha = rgba[rowBase + x * 4 + 3]
                guard alpha >= alphaThreshold else { continue }
                covered += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let rect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
        return (rect, Double(covered) / Double(width * height))
    }

    /// Convert a Vision normalized rect (bottom-left origin, 0…1) into a pixel
    /// rect in `CGImage` space (top-left origin). Pure — unit-testable.
    static func pixelRect(
        fromNormalized rect: CGRect,
        imageWidth: Int,
        imageHeight: Int
    ) -> CGRect {
        let w = CGFloat(imageWidth)
        let h = CGFloat(imageHeight)
        let x = rect.minX * w
        let width = rect.width * w
        let height = rect.height * h
        // Vision's Y grows upward from the bottom; flip to top-left origin.
        let y = (1 - rect.maxY) * h
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Downsampling

    /// Aspect-fit `cg` into a `targetWidth × targetHeight` RGBA buffer on a
    /// transparent canvas (so occupancy comes from alpha). One cell per stud,
    /// high-quality interpolation.
    private static func downsampleAspectFit(
        _ cg: CGImage,
        targetWidth: Int,
        targetHeight: Int
    ) -> [UInt8]? {
        guard targetWidth > 0, targetHeight > 0 else { return nil }
        let bytesPerRow = targetWidth * 4
        var data = [UInt8](repeating: 0, count: targetHeight * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        let created = data.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }

            ctx.clear(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            ctx.interpolationQuality = .high

            // Fit while preserving aspect ratio, centered.
            let scale = min(
                Double(targetWidth) / Double(cg.width),
                Double(targetHeight) / Double(cg.height)
            )
            let drawW = Double(cg.width) * scale
            let drawH = Double(cg.height) * scale
            let originX = (Double(targetWidth) - drawW) / 2.0
            let originY = (Double(targetHeight) - drawH) / 2.0
            ctx.draw(cg, in: CGRect(x: originX, y: originY, width: drawW, height: drawH))
            return true
        }
        return created ? data : nil
    }
}
