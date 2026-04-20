import CoreGraphics
import Foundation

/// Compact, training-free visual signature of a torso-band crop that
/// captures *spatial* structure of color and edges, not just an
/// embedding-space response.
///
/// Why this exists
/// ───────────────
/// `VNFeaturePrintObservation` is a generic image-similarity embedding
/// trained on natural photos. On a torso-band crop it tends to score by
/// overall hue distribution and silhouette, which means a white-and-
/// orange astronaut torso scores roughly the same against a Star Wars
/// officer with a white-and-orange chest insignia as it does against
/// the actual matching figure. The pipeline then can't distinguish
/// "white shoulders + orange center stripe + chest badge" from "orange
/// torso with white side panels".
///
/// This signature adds the cheap structural information that the
/// generic embedding throws away:
///   1. **4-quadrant color** — TL, TR, BL, BR mean RGB. Captures
///      "shoulders are white, waist is orange" type layouts.
///   2. **5-slice vertical color profile** — rows 0/1/2/3/4 mean RGB.
///      Captures horizontal-stripe patterns (uniforms, jumpsuits).
///   3. **8×8 edge-density grid** — Sobel-magnitude bucketed into 64
///      cells. Captures *where* prints / zippers / badges live without
///      caring what color they are.
///
/// The signature is computed once per image (captured + each reference)
/// and compared with a fast L2-style distance. No ML, no model file,
/// no training needed — just sampled pixels.
///
/// Distance scale: roughly 0.0 (identical) → 1.0+ (very different).
struct TorsoVisualSignature: Sendable {
    /// Mean RGB per quadrant: [TL, TR, BL, BR], 4 × 3 = 12 floats.
    let quadrants: [Float]
    /// Mean RGB per horizontal slice (top→bottom): 5 × 3 = 15 floats.
    let verticalSlices: [Float]
    /// Sobel-magnitude density per 8×8 cell, normalized 0…1: 64 floats.
    let edgeGrid: [Float]

    /// L2 distance, weighted to emphasize spatial color layout (which
    /// is what disambiguates similar-palette torsos) over raw edge
    /// density (which is noisier on JPEG-compressed CDN renders).
    func distance(to other: TorsoVisualSignature) -> Float {
        let qd = Self.l2(quadrants, other.quadrants)
        let vd = Self.l2(verticalSlices, other.verticalSlices)
        let ed = Self.l2(edgeGrid, other.edgeGrid)
        // Quadrant + vertical-slice carry the most signal for figures
        // with structured prints (uniforms, jumpsuits, factional
        // emblems). Edge grid is a tie-breaker.
        return 0.45 * qd + 0.35 * vd + 0.20 * ed
    }

    private static func l2(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        var sum: Float = 0
        for i in 0..<a.count {
            let d = a[i] - b[i]
            sum += d * d
        }
        return (sum / Float(a.count)).squareRoot()
    }
}

enum TorsoVisualSignatureExtractor {

    /// Sample the image at 32×32, then derive quadrants / vertical
    /// slices / 8×8 edge grid. 32×32 is large enough to preserve
    /// horizontal stripe patterns but small enough to compute in
    /// well under a millisecond per image.
    static func signature(for cgImage: CGImage) -> TorsoVisualSignature? {
        let size = 32
        let bytesPerPixel = 4
        let bytesPerRow = size * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: size * size * bytesPerPixel)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        // Precompute a luminance grid for the edge pass.
        var lum = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let off = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = Float(pixels[off]) / 255.0
                let g = Float(pixels[off + 1]) / 255.0
                let b = Float(pixels[off + 2]) / 255.0
                // Rec. 601 luma — close enough for edge detection.
                lum[y * size + x] = 0.299 * r + 0.587 * g + 0.114 * b
            }
        }

        // ── 4-quadrant mean RGB ─────────────────────────────────────
        // TL, TR, BL, BR. Each quadrant covers half the image in each
        // dimension.
        let half = size / 2
        var quadrants = [Float](repeating: 0, count: 12)
        var quadCounts = [Int](repeating: 0, count: 4)
        for y in 0..<size {
            for x in 0..<size {
                let q = (y < half ? 0 : 2) + (x < half ? 0 : 1)
                let off = (y * bytesPerRow) + (x * bytesPerPixel)
                quadrants[q * 3 + 0] += Float(pixels[off]) / 255.0
                quadrants[q * 3 + 1] += Float(pixels[off + 1]) / 255.0
                quadrants[q * 3 + 2] += Float(pixels[off + 2]) / 255.0
                quadCounts[q] += 1
            }
        }
        for q in 0..<4 {
            let c = Float(max(quadCounts[q], 1))
            quadrants[q * 3 + 0] /= c
            quadrants[q * 3 + 1] /= c
            quadrants[q * 3 + 2] /= c
        }

        // ── 5-slice vertical color profile ──────────────────────────
        // Five equal horizontal bands top→bottom. Captures stripes
        // and "shoulders vs waist" color separation.
        let sliceHeight = max(size / 5, 1)
        var verticalSlices = [Float](repeating: 0, count: 15)
        var sliceCounts = [Int](repeating: 0, count: 5)
        for y in 0..<size {
            let s = min(y / sliceHeight, 4)
            for x in 0..<size {
                let off = (y * bytesPerRow) + (x * bytesPerPixel)
                verticalSlices[s * 3 + 0] += Float(pixels[off]) / 255.0
                verticalSlices[s * 3 + 1] += Float(pixels[off + 1]) / 255.0
                verticalSlices[s * 3 + 2] += Float(pixels[off + 2]) / 255.0
                sliceCounts[s] += 1
            }
        }
        for s in 0..<5 {
            let c = Float(max(sliceCounts[s], 1))
            verticalSlices[s * 3 + 0] /= c
            verticalSlices[s * 3 + 1] /= c
            verticalSlices[s * 3 + 2] /= c
        }

        // ── 8×8 edge-density grid via Sobel magnitude ───────────────
        var edgeGrid = [Float](repeating: 0, count: 64)
        var edgeCounts = [Int](repeating: 0, count: 64)
        let cell = size / 8  // = 4
        var maxMag: Float = 0
        // Sobel only on interior pixels (skip 1-pixel border).
        for y in 1..<(size - 1) {
            for x in 1..<(size - 1) {
                let gx =
                    -lum[(y - 1) * size + (x - 1)] + lum[(y - 1) * size + (x + 1)]
                    - 2 * lum[y * size + (x - 1)] + 2 * lum[y * size + (x + 1)]
                    - lum[(y + 1) * size + (x - 1)] + lum[(y + 1) * size + (x + 1)]
                let gy =
                    -lum[(y - 1) * size + (x - 1)]
                    - 2 * lum[(y - 1) * size + x]
                    - lum[(y - 1) * size + (x + 1)]
                    + lum[(y + 1) * size + (x - 1)]
                    + 2 * lum[(y + 1) * size + x]
                    + lum[(y + 1) * size + (x + 1)]
                let mag = (gx * gx + gy * gy).squareRoot()
                let cellIdx = min(y / cell, 7) * 8 + min(x / cell, 7)
                edgeGrid[cellIdx] += mag
                edgeCounts[cellIdx] += 1
                if mag > maxMag { maxMag = mag }
            }
        }
        // Mean per cell, then normalize the whole grid to [0, 1] so
        // overall image contrast doesn't swamp the comparison.
        for i in 0..<64 {
            edgeGrid[i] /= Float(max(edgeCounts[i], 1))
        }
        if maxMag > 0 {
            let cellMax = edgeGrid.max() ?? 1
            if cellMax > 0 {
                for i in 0..<64 {
                    edgeGrid[i] /= cellMax
                }
            }
        }

        return TorsoVisualSignature(
            quadrants: quadrants,
            verticalSlices: verticalSlices,
            edgeGrid: edgeGrid
        )
    }
}
