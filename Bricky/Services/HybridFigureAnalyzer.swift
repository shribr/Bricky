import UIKit
import CoreImage
import Vision

/// Detects "hybrid" minifigures — where the scanned figure appears to be
/// composed of parts from different catalog entries (e.g. an Islander
/// torso with a different figure's head, missing its hair entirely, or
/// regular yellow hands where gloved white hands are expected).
///
/// Approach (fully on-device):
///
///   1. Split each image into 4 vertical bands:
///         hair (top 0–12%) — anything ABOVE the head, i.e. hair piece,
///                            hat, helmet, headdress, feathers
///         head (12–28%)   — the face / head stud
///         torso (28–65%)  — printed torso + arms
///         legs (65–100%)  — hips and legs
///   2. Compute the dominant non-background color per band in LAB space,
///      AND the "coverage" — what % of pixels are NOT background.
///   3. For each band, compare to every supplied candidate reference. If
///      the captured band matches one candidate but the top candidate's
///      band differs, we know the part came from a different figure.
///   4. Detect "missing hair": captured hair band has very low coverage
///      (mostly background) while the top candidate's hair band has
///      high coverage (something is supposed to be there).
///   5. Detect yellow vs. gloved hands at the torso-band Y level.
///
/// Output describes each anomaly with the specific figure it appears to
/// match (e.g. "torso looks like King Kahuka, face looks like Male
/// Islander, hair piece is missing").
enum HybridFigureAnalyzer {

    // MARK: - Public types

    struct Analysis {
        enum Region: String, CaseIterable {
            case hair, head, torso, legs

            var displayName: String {
                switch self {
                case .hair:  return "hair / hat / headdress"
                case .head:  return "face"
                case .torso: return "torso"
                case .legs:  return "legs"
                }
            }
            var shortName: String {
                switch self {
                case .hair:  return "hair piece"
                case .head:  return "head"
                case .torso: return "torso"
                case .legs:  return "legs"
                }
            }
        }

        /// Description of a single region observation.
        struct RegionFinding {
            enum Kind {
                /// Captured region matches the top (anchor) candidate's region.
                case matchesAnchor
                /// Captured region matches a *different* figure than the anchor.
                case matchesOtherFigure
                /// Captured region appears empty (e.g. minifigure has no hair
                /// piece on, but the anchor figure's reference image does).
                case missing
                /// Captured region differs from the anchor and we couldn't
                /// confidently attribute it to another supplied candidate.
                case unknownMismatch
            }
            let region: Region
            /// Catalog figure whose corresponding part best matches the
            /// captured region. Nil for `.missing`.
            let matchedFigure: Minifigure?
            let kind: Kind
        }

        let isLikelyHybrid: Bool
        let anchorFigure: Minifigure
        let findings: [RegionFinding]
        /// True if captured shows plain yellow hands where the reference
        /// figure has non-yellow (gloved) hands.
        let unexpectedYellowHands: Bool
        /// Short, user-facing summary shown as a banner above scan results.
        let summary: String
        /// Longer detail explaining what's off.
        let detail: String
    }

    /// Container the caller passes in for each candidate to be considered
    /// during cross-attribution of mismatched parts.
    struct Candidate {
        let figure: Minifigure
        let referenceImage: UIImage
    }

    // MARK: - Public API

    /// Analyze the captured image against the top-ranked candidate and
    /// optionally cross-reference mismatched parts against other
    /// candidates supplied by the caller. Returns nil when no meaningful
    /// hybrid signal is detected.
    ///
    /// The first element of `candidates` is treated as the **anchor** —
    /// the figure the user will see ranked #1.
    nonisolated static func analyze(
        captured: UIImage,
        candidates: [Candidate]
    ) -> Analysis? {
        guard
            let anchorCandidate = candidates.first,
            let capturedCG = captured.cgImage,
            let anchorRefCG = anchorCandidate.referenceImage.cgImage
        else { return nil }

        let capturedBands = sampleBands(cgImage: capturedCG)
        let anchorBands = sampleBands(cgImage: anchorRefCG)

        // Pre-compute band data for every other candidate so we can attribute
        // mismatched regions to specific figures.
        let otherCandidates: [(figure: Minifigure, bands: [Analysis.Region: BandData])] =
            candidates.dropFirst().compactMap { c in
                guard let cg = c.referenceImage.cgImage else { return nil }
                return (c.figure, sampleBands(cgImage: cg))
            }

        let matchThreshold: Double = 28
        // Coverage below this means "empty" (background dominates).
        let missingCoverageThreshold: Double = 0.10

        var findings: [Analysis.RegionFinding] = []
        for region in Analysis.Region.allCases {
            guard let capturedBand = capturedBands[region] else { continue }

            // Missing-part detection: captured band is mostly background,
            // but the anchor's reference band has meaningful coverage.
            // Specifically what catches "no hair piece on the figure".
            if capturedBand.coverage < missingCoverageThreshold,
               let anchorBand = anchorBands[region],
               anchorBand.coverage >= 0.30 {
                findings.append(.init(
                    region: region,
                    matchedFigure: nil,
                    kind: .missing
                ))
                continue
            }

            // Compare against the anchor.
            if let anchorBand = anchorBands[region],
               let capturedColor = capturedBand.color,
               let anchorColor = anchorBand.color {
                let delta = labDistance(capturedColor, anchorColor)
                if delta <= matchThreshold {
                    findings.append(.init(
                        region: region,
                        matchedFigure: anchorCandidate.figure,
                        kind: .matchesAnchor
                    ))
                    continue
                }
            }

            // Captured band differs from anchor. Try to attribute it to
            // another candidate by finding the figure whose corresponding
            // band is the closest LAB match to the captured band.
            if let capturedColor = capturedBand.color {
                var best: (figure: Minifigure, distance: Double)?
                for other in otherCandidates {
                    guard let otherBand = other.bands[region],
                          let otherColor = otherBand.color else { continue }
                    let d = labDistance(capturedColor, otherColor)
                    if d <= matchThreshold {
                        if best == nil || d < best!.distance {
                            best = (other.figure, d)
                        }
                    }
                }
                if let best {
                    findings.append(.init(
                        region: region,
                        matchedFigure: best.figure,
                        kind: .matchesOtherFigure
                    ))
                    continue
                }
            }

            findings.append(.init(
                region: region,
                matchedFigure: nil,
                kind: .unknownMismatch
            ))
        }

        // Hand color detection — sample at torso-band Y, outer 8–18% of width.
        let handsYellow = isYellowDominant(
            cgImage: capturedCG,
            at: handSampleRects(for: capturedCG)
        )
        let refHandsYellow = isYellowDominant(
            cgImage: anchorRefCG,
            at: handSampleRects(for: anchorRefCG)
        )
        let unexpectedYellowHands =
            (handsYellow == true) && (refHandsYellow == false)

        let matchedCount = findings.filter { $0.kind == .matchesAnchor }.count
        let anomalyCount = findings.filter { $0.kind != .matchesAnchor }.count
        let handMismatchOnly = unexpectedYellowHands && matchedCount >= 2 && anomalyCount == 0
        guard (matchedCount > 0 && anomalyCount > 0) || handMismatchOnly else {
            return nil
        }

        let (summary, detail) = messageFor(
            anchor: anchorCandidate.figure,
            findings: findings,
            unexpectedYellowHands: unexpectedYellowHands
        )

        return Analysis(
            isLikelyHybrid: true,
            anchorFigure: anchorCandidate.figure,
            findings: findings,
            unexpectedYellowHands: unexpectedYellowHands,
            summary: summary,
            detail: detail
        )
    }

    // MARK: - Band sampling

    private struct BandData {
        let color: LAB?
        /// 0…1 — fraction of pixels in the band that are NOT background.
        let coverage: Double
    }

    nonisolated private static func sampleBands(
        cgImage: CGImage
    ) -> [Analysis.Region: BandData] {
        let w = cgImage.width
        let h = cgImage.height

        // Vertical slices for the four anatomical regions.
        // Hair is the very top — narrower X range to ignore corner background.
        // Head is the face stud just below.
        let regions: [(Analysis.Region, CGRect)] = [
            (.hair,  CGRect(x: Int(Double(w) * 0.30),
                            y: 0,
                            width: Int(Double(w) * 0.40),
                            height: Int(Double(h) * 0.12))),
            (.head,  CGRect(x: Int(Double(w) * 0.32),
                            y: Int(Double(h) * 0.12),
                            width: Int(Double(w) * 0.36),
                            height: Int(Double(h) * 0.16))),
            (.torso, CGRect(x: Int(Double(w) * 0.22),
                            y: Int(Double(h) * 0.28),
                            width: Int(Double(w) * 0.56),
                            height: Int(Double(h) * 0.37))),
            (.legs,  CGRect(x: Int(Double(w) * 0.26),
                            y: Int(Double(h) * 0.65),
                            width: Int(Double(w) * 0.48),
                            height: Int(Double(h) * 0.33)))
        ]

        var out: [Analysis.Region: BandData] = [:]
        for (region, rect) in regions {
            out[region] = bandData(cgImage: cgImage, rect: rect)
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
        let leftX = Int(Double(w) * 0.10)
        let rightX = Int(Double(w) * 0.82)
        return [
            CGRect(x: leftX, y: y, width: sampleW, height: sampleH),
            CGRect(x: rightX, y: y, width: sampleW, height: sampleH)
        ]
    }

    // MARK: - Color math

    private struct LAB { let L, a, b: Double }

    /// Dominant LAB color (foreground only) AND coverage ratio for a rect.
    nonisolated private static func bandData(
        cgImage: CGImage,
        rect: CGRect
    ) -> BandData {
        guard let cropped = cgImage.cropping(to: rect),
              let pixels = rgbaPixels(for: cropped) else {
            return BandData(color: nil, coverage: 0)
        }

        var sumL = 0.0, sumA = 0.0, sumB = 0.0, fgCount = 0.0, total = 0.0
        for i in stride(from: 0, to: pixels.count - 3, by: 4 * 4) {
            let r = Double(pixels[i])     / 255.0
            let g = Double(pixels[i + 1]) / 255.0
            let b = Double(pixels[i + 2]) / 255.0
            let a = Double(pixels[i + 3]) / 255.0
            guard a > 0.5 else { continue }
            total += 1
            // Background heuristic: very bright + very low saturation.
            // Captures both white reference-image background and most
            // light user-photo backgrounds.
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let brightness = (maxC + minC) / 2.0
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
            if brightness > 0.92 && saturation < 0.10 { continue }
            // Skip near-black shadows that would dilute the dominant color.
            if brightness < 0.05 { continue }
            let lab = rgbToLAB(r: r, g: g, b: b)
            sumL += lab.L; sumA += lab.a; sumB += lab.b
            fgCount += 1
        }
        guard total > 0 else { return BandData(color: nil, coverage: 0) }
        let coverage = fgCount / total
        guard fgCount > 8 else { return BandData(color: nil, coverage: coverage) }
        return BandData(
            color: LAB(L: sumL / fgCount, a: sumA / fgCount, b: sumB / fgCount),
            coverage: coverage
        )
    }

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

    nonisolated private static func labDistance(_ a: LAB, _ b: LAB) -> Double {
        let dL = a.L - b.L
        let da = a.a - b.a
        let db = a.b - b.b
        return sqrt(dL * dL + da * da + db * db)
    }

    nonisolated private static func rgbToLAB(r: Double, g: Double, b: Double) -> LAB {
        func lin(_ c: Double) -> Double {
            c > 0.04045 ? pow((c + 0.055) / 1.055, 2.4) : c / 12.92
        }
        let R = lin(r), G = lin(g), B = lin(b)
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
        anchor: Minifigure,
        findings: [Analysis.RegionFinding],
        unexpectedYellowHands: Bool
    ) -> (summary: String, detail: String) {
        // Use the iconic prefix of the figure name when available.
        // Catalog names typically follow "<Iconic> - <Variant>, <Detail>"
        // (e.g. "Islander - King Kahuka, Feathers" → "Islander").
        // This is much more recognizable to the user than the broad theme
        // ("Pirates"), which can be ambiguous when many sub-themes exist.
        let iconicWord: String? = {
            let trimmed = anchor.name.trimmingCharacters(in: .whitespaces)
            // Split on " - " or " — " or comma — take the first chunk.
            let separators: [Character] = ["-", "—", ","]
            if let idx = trimmed.firstIndex(where: { separators.contains($0) }) {
                let head = trimmed[..<idx].trimmingCharacters(in: .whitespaces)
                if !head.isEmpty && head.lowercased() != anchor.theme.lowercased() {
                    return head
                }
            }
            return nil
        }()

        let figureLabel: String = {
            if let iconic = iconicWord {
                return "\(article(for: iconic)) \(iconic) figure"
            }
            if !anchor.theme.isEmpty {
                return "\(article(for: anchor.theme)) \(anchor.theme) figure"
            }
            return "the \(anchor.name) figure"
        }()
        let summary = "Possible hybrid — looks like \(figureLabel)"

        // Build per-region phrases, calling out the specific figure when
        // we attributed a part to a different candidate.
        var phrases: [String] = []
        for finding in findings {
            switch finding.kind {
            case .matchesAnchor:
                continue
            case .missing:
                let verb: String
                switch finding.region {
                case .hair:  verb = "appears to be missing (no hair, hat, or headdress detected)"
                case .head:  verb = "appears to be missing"
                case .torso: verb = "appears to be missing"
                case .legs:  verb = "appears to be missing"
                }
                phrases.append("the \(finding.region.shortName) \(verb)")
            case .matchesOtherFigure:
                if let other = finding.matchedFigure {
                    phrases.append(
                        "the \(finding.region.shortName) looks like it's from \(other.name)"
                    )
                } else {
                    phrases.append("the \(finding.region.shortName) doesn't match")
                }
            case .unknownMismatch:
                phrases.append("the \(finding.region.shortName) doesn't match")
            }
        }
        if unexpectedYellowHands {
            phrases.append("the hands are plain yellow instead of gloved")
        }

        // Identify the strongest matched part as the anchoring evidence.
        let matchedRegions = findings
            .filter { $0.kind == .matchesAnchor }
            .map { $0.region }
        let anchorPhrase: String = {
            if matchedRegions.contains(.torso) {
                return "The torso matches \(anchor.name)"
            }
            if let first = matchedRegions.first {
                return "The \(first.shortName) matches \(anchor.name)"
            }
            return "It resembles \(anchor.name)"
        }()
        let yearSuffix = anchor.year > 0 ? ", \(anchor.year)" : ""

        let issuesSentence: String = {
            switch phrases.count {
            case 0: return ""
            case 1: return "But \(phrases[0])."
            case 2: return "But \(phrases[0]), and \(phrases[1])."
            default:
                let head = phrases.dropLast().joined(separator: ", ")
                return "But \(head), and \(phrases.last!)."
            }
        }()

        let detail = "\(anchorPhrase) (\(anchor.theme)\(yearSuffix)). " +
            issuesSentence +
            " This figure may be assembled from parts of multiple sets " +
            "or missing an accessory."
        return (summary, detail)
    }

    /// Pick "a" vs "an" using a vowel-sound check on the first letter.
    /// Good enough for figure / theme names; not a full English NLP rule.
    nonisolated private static func article(for word: String) -> String {
        guard let first = word.lowercased().first else { return "a" }
        return "aeiou".contains(first) ? "an" : "a"
    }
}
