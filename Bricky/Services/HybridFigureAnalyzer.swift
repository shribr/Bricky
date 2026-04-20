import UIKit
import CoreImage
import Vision

/// Detects "hybrid" minifigures — where the scanned figure appears to be
/// composed of parts from different catalog entries (e.g. Islander torso
/// + plain yellow head, or a proper figure missing its hair/helmet, or
/// regular yellow hands where gloved white hands are expected).
///
/// Approach (fully on-device, uses only the captured image + the top
/// catalog candidate's locally-available reference image):
///
///   1. Split each image into 3 vertical bands — head (top 25%),
///      torso (middle 40%), legs (bottom 35%).
///   2. Compute the dominant non-background color per band in LAB space.
///   3. Compare band-by-band. Large deltaE (>28) means that part doesn't
///      match the reference.
///   4. Detect hand color by sampling small regions at the torso-band
///      y-level, near the outer edges. Yellow vs. gloved (white/other)
///      mismatch is called out specifically — it's one of the most
///      common hybrid signals.
///   5. A figure is flagged hybrid if AT LEAST one band matches (so we
///      have a reliable anchor to infer theme/set from) AND at least
///      one other band mismatches.
enum HybridFigureAnalyzer {

    struct Analysis {
        enum Region: String, CaseIterable {
            case head, torso, legs
            var displayName: String {
                switch self {
                case .head: return "head / hair"
                case .torso: return "torso"
                case .legs: return "legs"
                }
            }
        }
        let isLikelyHybrid: Bool
        let matchedRegions: [Region]
        let mismatchedRegions: [Region]
        /// True if captured shows plain yellow hands where the reference
        /// figure has non-yellow (gloved) hands.
        let unexpectedYellowHands: Bool
        let anchorFigure: Minifigure
        let anchorRegion: Region
        /// Short, user-facing summary shown as a banner above scan results.
        let summary: String
        /// Longer detail explaining what's off.
        let detail: String
    }

    // MARK: - Public API

    /// Analyze the captured image against the top-ranked candidate's
    /// reference image. Returns nil when no meaningful analysis is
    /// possible (missing reference, inconclusive colors).
    ///
    /// Safe to call off the main actor — no UIKit main-actor APIs are
    /// touched; UIImage inspection only reads the backing CGImage.
    nonisolated static func analyze(
        captured: UIImage,
        candidate: Minifigure,
        referenceImage: UIImage
    ) -> Analysis? {
        guard
            let capturedCG = captured.cgImage,
            let referenceCG = referenceImage.cgImage
        else { return nil }

        // Extract dominant colors for each of the 3 vertical bands.
        let capturedBands = sampleBands(cgImage: capturedCG)
        let referenceBands = sampleBands(cgImage: referenceCG)

        // Decide per-band match/mismatch using LAB deltaE.
        // Use slightly relaxed threshold (28) — captured photos have
        // lighting variance, so we don't want to flag every shadow.
        let matchThreshold: Double = 28
        var matched: [Analysis.Region] = []
        var mismatched: [Analysis.Region] = []
        for region in Analysis.Region.allCases {
            guard
                let capturedColor = capturedBands[region],
                let referenceColor = referenceBands[region]
            else { continue }
            let delta = labDistance(capturedColor, referenceColor)
            if delta <= matchThreshold {
                matched.append(region)
            } else {
                mismatched.append(region)
            }
        }

        // Hand color detection — sample at torso-band y, outer 10–18% of width.
        let handsYellow = isYellowDominant(
            cgImage: capturedCG,
            at: handSampleRects(for: capturedCG)
        )
        let refHandsYellow = isYellowDominant(
            cgImage: referenceCG,
            at: handSampleRects(for: referenceCG)
        )
        let unexpectedYellowHands =
            (handsYellow == true) && (refHandsYellow == false)

        // Need ≥1 match (anchor) AND ≥1 mismatch for a hybrid flag.
        // Yellow-hands-only discrepancy is also sufficient to flag.
        let handMismatchOnly = unexpectedYellowHands && matched.count >= 2 && mismatched.isEmpty
        guard (!matched.isEmpty && !mismatched.isEmpty) || handMismatchOnly else {
            return nil
        }

        // Torso is the most informative anchor when available (prints
        // are the most distinguishing feature of a minifigure).
        let anchorRegion: Analysis.Region =
            matched.contains(.torso) ? .torso :
            matched.first ?? .torso

        let (summary, detail) = messageFor(
            candidate: candidate,
            anchorRegion: anchorRegion,
            mismatched: mismatched,
            unexpectedYellowHands: unexpectedYellowHands
        )

        return Analysis(
            isLikelyHybrid: true,
            matchedRegions: matched,
            mismatchedRegions: mismatched,
            unexpectedYellowHands: unexpectedYellowHands,
            anchorFigure: candidate,
            anchorRegion: anchorRegion,
            summary: summary,
            detail: detail
        )
    }

    // MARK: - Band sampling

    /// Dominant LAB color per vertical band. Returns nil entry when a
    /// band is nearly entirely background (low-saturation pixels).
    nonisolated private static func sampleBands(
        cgImage: CGImage
    ) -> [Analysis.Region: LAB] {
        let w = cgImage.width
        let h = cgImage.height
        // Vertical slices: head 0–25%, torso 25–65%, legs 65–100%.
        let regions: [(Analysis.Region, CGRect)] = [
            (.head, CGRect(x: Int(Double(w) * 0.28),
                           y: 0,
                           width: Int(Double(w) * 0.44),
                           height: Int(Double(h) * 0.25))),
            (.torso, CGRect(x: Int(Double(w) * 0.22),
                            y: Int(Double(h) * 0.25),
                            width: Int(Double(w) * 0.56),
                            height: Int(Double(h) * 0.40))),
            (.legs, CGRect(x: Int(Double(w) * 0.26),
                           y: Int(Double(h) * 0.65),
                           width: Int(Double(w) * 0.48),
                           height: Int(Double(h) * 0.33)))
        ]

        var out: [Analysis.Region: LAB] = [:]
        for (region, rect) in regions {
            if let lab = dominantLAB(cgImage: cgImage, rect: rect) {
                out[region] = lab
            }
        }
        return out
    }

    /// Hand rectangles — two small squares at outer edges of the torso band.
    nonisolated private static func handSampleRects(for cgImage: CGImage) -> [CGRect] {
        let w = cgImage.width
        let h = cgImage.height
        let sampleW = Int(Double(w) * 0.08)
        let sampleH = Int(Double(h) * 0.08)
        let y = Int(Double(h) * 0.55)
        // Hands sit just outside the torso print, ~8–16% from edge.
        let leftX = Int(Double(w) * 0.10)
        let rightX = Int(Double(w) * 0.82)
        return [
            CGRect(x: leftX, y: y, width: sampleW, height: sampleH),
            CGRect(x: rightX, y: y, width: sampleW, height: sampleH)
        ]
    }

    // MARK: - Color math

    private struct LAB { let L, a, b: Double }

    nonisolated private static func dominantLAB(
        cgImage: CGImage,
        rect: CGRect
    ) -> LAB? {
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        guard let pixels = rgbaPixels(for: cropped) else { return nil }

        // Accumulate only moderately-saturated or dark pixels — pure
        // white (background) is filtered out.
        var sumL = 0.0, sumA = 0.0, sumB = 0.0, count = 0.0
        // Sample every 4th pixel for speed — plenty of points remain.
        for i in stride(from: 0, to: pixels.count - 3, by: 4 * 4) {
            let r = Double(pixels[i])     / 255.0
            let g = Double(pixels[i + 1]) / 255.0
            let b = Double(pixels[i + 2]) / 255.0
            let a = Double(pixels[i + 3]) / 255.0
            guard a > 0.5 else { continue }
            // Ignore near-white background and very bright pixels.
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let brightness = (maxC + minC) / 2.0
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
            if brightness > 0.95 && saturation < 0.08 { continue }
            let lab = rgbToLAB(r: r, g: g, b: b)
            sumL += lab.L; sumA += lab.a; sumB += lab.b
            count += 1
        }
        guard count > 10 else { return nil }
        return LAB(L: sumL / count, a: sumA / count, b: sumB / count)
    }

    /// True if the dominant color in any sampled rect is strongly yellow.
    /// Returns nil when sampling is inconclusive.
    nonisolated private static func isYellowDominant(
        cgImage: CGImage,
        at rects: [CGRect]
    ) -> Bool? {
        var positives = 0
        var conclusive = 0
        for rect in rects {
            guard
                let cropped = cgImage.cropping(to: rect),
                let pixels = rgbaPixels(for: cropped)
            else { continue }
            var yellowCount = 0
            var total = 0
            for i in stride(from: 0, to: pixels.count - 3, by: 4 * 4) {
                let r = Int(pixels[i])
                let g = Int(pixels[i + 1])
                let b = Int(pixels[i + 2])
                let a = Int(pixels[i + 3])
                guard a > 128 else { continue }
                total += 1
                // LEGO yellow ≈ (250, 205, 80). Require R+G high, B low.
                if r > 200 && g > 160 && b < 130 && r >= g {
                    yellowCount += 1
                }
            }
            if total > 20 {
                conclusive += 1
                if Double(yellowCount) / Double(total) > 0.25 {
                    positives += 1
                }
            }
        }
        guard conclusive > 0 else { return nil }
        return positives > 0
    }

    /// CIE76 deltaE distance between two LAB colors. Thresholds:
    /// <15 = clearly same, 15–30 = similar, >30 = visibly different.
    nonisolated private static func labDistance(_ a: LAB, _ b: LAB) -> Double {
        let dL = a.L - b.L
        let da = a.a - b.a
        let db = a.b - b.b
        return sqrt(dL * dL + da * da + db * db)
    }

    /// sRGB → LAB via D65 reference white.
    nonisolated private static func rgbToLAB(r: Double, g: Double, b: Double) -> LAB {
        // sRGB → linear RGB
        func lin(_ c: Double) -> Double {
            c > 0.04045 ? pow((c + 0.055) / 1.055, 2.4) : c / 12.92
        }
        let R = lin(r), G = lin(g), B = lin(b)
        // linear RGB → XYZ (D65)
        let X = (R * 0.4124 + G * 0.3576 + B * 0.1805) / 0.95047
        let Y = (R * 0.2126 + G * 0.7152 + B * 0.0722)
        let Z = (R * 0.0193 + G * 0.1192 + B * 0.9505) / 1.08883
        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t) + 16.0 / 116.0
        }
        let fx = f(X), fy = f(Y), fz = f(Z)
        return LAB(
            L: 116.0 * fy - 16.0,
            a: 500.0 * (fx - fy),
            b: 200.0 * (fy - fz)
        )
    }

    // MARK: - Pixel readout

    nonisolated private static func rgbaPixels(for cgImage: CGImage) -> [UInt8]? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    // MARK: - Messages

    nonisolated private static func messageFor(
        candidate: Minifigure,
        anchorRegion: Analysis.Region,
        mismatched: [Analysis.Region],
        unexpectedYellowHands: Bool
    ) -> (summary: String, detail: String) {
        let figureLabel: String = {
            if !candidate.theme.isEmpty {
                return "a \(candidate.theme) figure"
            }
            return "the \(candidate.name) figure"
        }()

        var issues: [String] = mismatched.map { $0.displayName }
        if unexpectedYellowHands {
            issues.append("hands (yellow instead of gloved)")
        }

        let issueList: String = {
            switch issues.count {
            case 0: return "one or more parts"
            case 1: return issues[0]
            case 2: return "\(issues[0]) and \(issues[1])"
            default:
                let head = issues.dropLast().joined(separator: ", ")
                return "\(head), and \(issues.last!)"
            }
        }()

        let summary = "Possible hybrid — looks like \(figureLabel)"
        let detail =
            "The \(anchorRegion.displayName) matches \(candidate.name) " +
            "(\(candidate.theme)\(candidate.year > 0 ? ", \(candidate.year)" : "")), " +
            "but the \(issueList) don't match. " +
            "This figure may be assembled from parts of multiple sets, " +
            "missing an accessory (e.g. hair/hat), or using swapped hands."
        return (summary, detail)
    }
}
