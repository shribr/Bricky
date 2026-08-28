import CoreGraphics
import Foundation
import UIKit
import Vision

/// Offline "scan a photo / live subject → brick model" adapter.
///
/// Turns a single photo into a colored `VoxelModel`:
/// 1. Isolate the subject with Vision's foreground-instance segmentation
///    (iOS 17). If segmentation is unavailable, fall back to the whole image.
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

        // 1. Isolate the subject (transparent background) when possible.
        let masked = foregroundMasked(cg) ?? cg

        // 2. Grid dimensions from the image aspect ratio, longest side = maxDim.
        let maxDim = size.maxDimension
        let aspect = Double(cg.width) / Double(cg.height)
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

    // MARK: - Vision segmentation

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

    private static func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        return context.createCGImage(ciImage, from: ciImage.extent)
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
