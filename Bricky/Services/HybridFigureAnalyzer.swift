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

    /// Embedding-enhanced analysis. When the trained face encoder is
    /// available, uses it for precise per-region attribution — the face
    /// embedding can tell you *which specific figure* a swapped face
    /// belongs to, not just "the face doesn't match." Falls back to
    /// the color-only path when the encoder isn't bundled.
    ///
    /// Also adds legs attribution when the torso embedding is available,
    /// enabling full 4-region hybrid detection.
    static func analyzeWithEmbeddings(
        captured: UIImage,
        candidates: [Candidate]
    ) async -> Analysis? {
        // Start with the fast color-based analysis.
        guard let colorAnalysis = analyze(captured: captured, candidates: candidates) else {
            // No color-level mismatch detected. But if we have
            // embedding models, do a deeper check: the color pass
            // skips head/legs cross-attribution entirely, so a
            // head swap between two same-color-head figures (e.g.
            // two different white helmets) would be invisible.
            return await embeddingOnlyAnalysis(
                captured: captured,
                candidates: candidates
            )
        }

        // If no embedding services are available, return color-only.
        let faceService = FaceEmbeddingService.shared
        let torsoService = TorsoEmbeddingService.shared
        guard faceService.isAvailable || torsoService.isAvailable else {
            return colorAnalysis
        }

        guard let capturedCG = captured.cgImage else { return colorAnalysis }
        let anchorCandidate = candidates[0]

        // Enhance findings with embedding-based cross-attribution for
        // regions that the color pass marked as unknownMismatch.
        var enhanced = colorAnalysis.findings

        // For any unknownMismatch on head or torso, try embedding lookup.
        for (idx, finding) in enhanced.enumerated() {
            guard finding.kind == .unknownMismatch else { continue }

            if finding.region == .head, faceService.isAvailable {
                let headCG = cropRegion(.head, from: capturedCG)
                if let headCG,
                   let match = await attributeViaFaceEmbedding(
                       regionCG: headCG,
                       anchor: anchorCandidate.figure,
                       candidates: candidates
                   ) {
                    enhanced[idx] = Analysis.RegionFinding(
                        region: .head,
                        matchedFigure: match,
                        kind: .matchesOtherFigure
                    )
                }
            }
        }

        // If we improved any findings, rebuild the analysis.
        let matchedCount = enhanced.filter { $0.kind == .matchesAnchor }.count
        let anomalyCount = enhanced.filter { $0.kind != .matchesAnchor }.count
        guard matchedCount > 0 && anomalyCount > 0 else { return colorAnalysis }

        let (summary, detail) = messageFor(
            anchor: anchorCandidate.figure,
            findings: enhanced,
            unexpectedYellowHands: colorAnalysis.unexpectedYellowHands
        )

        return Analysis(
            isLikelyHybrid: true,
            anchorFigure: anchorCandidate.figure,
            findings: enhanced,
            unexpectedYellowHands: colorAnalysis.unexpectedYellowHands,
            summary: summary,
            detail: detail
        )
    }

    /// Embedding-only deep check for when color analysis found no
    /// mismatch. Catches same-color head/torso swaps (e.g. two
    /// different white helmets, or two black torsos with different
    /// prints).
    private static func embeddingOnlyAnalysis(
        captured: UIImage,
        candidates: [Candidate]
    ) async -> Analysis? {
        let faceService = FaceEmbeddingService.shared
        let torsoService = TorsoEmbeddingService.shared
        guard (faceService.isAvailable || torsoService.isAvailable),
              let capturedCG = captured.cgImage,
              let anchorCandidate = candidates.first else { return nil }

        var findings: [Analysis.RegionFinding] = []

        // Face embedding check: does the captured face match a
        // different figure than the anchor?
        if faceService.isAvailable, let headCG = cropRegion(.head, from: capturedCG) {
            let hits = await faceService.nearestFigures(for: headCG, topK: 8)
            let anchorId = anchorCandidate.figure.id
            // If the top hit isn't the anchor, the head likely belongs
            // to someone else.
            if let topHit = hits.first,
               topHit.cosine >= 0.60,
               topHit.figureId != anchorId {
                // Check if the anchor appears at all in top-K.
                let anchorRank = hits.firstIndex(where: { $0.figureId == anchorId })
                // If anchor is missing from top-8 or ranked much lower,
                // this is a real head mismatch, not noise.
                if anchorRank == nil || anchorRank! > 3 {
                    let matchedFig = await MinifigureCatalog.shared.figure(id: topHit.figureId)
                    findings.append(Analysis.RegionFinding(
                        region: .head,
                        matchedFigure: matchedFig,
                        kind: .matchesOtherFigure
                    ))
                    // Torso matches anchor by default in this path.
                    findings.append(Analysis.RegionFinding(
                        region: .torso,
                        matchedFigure: anchorCandidate.figure,
                        kind: .matchesAnchor
                    ))
                }
            }
        }

        // Torso embedding check for legs-swapped figures: if the torso
        // encoder is available, encode the legs band and check if it
        // matches a different figure's legs.
        // (Deferred for a future iteration — legs prints are rare enough
        // that color is usually sufficient.)

        guard !findings.isEmpty else { return nil }
        let anomalyCount = findings.filter { $0.kind != .matchesAnchor }.count
        let matchedCount = findings.filter { $0.kind == .matchesAnchor }.count
        guard matchedCount > 0, anomalyCount > 0 else { return nil }

        let (summary, detail) = messageFor(
            anchor: anchorCandidate.figure,
            findings: findings,
            unexpectedYellowHands: false
        )

        return Analysis(
            isLikelyHybrid: true,
            anchorFigure: anchorCandidate.figure,
            findings: findings,
            unexpectedYellowHands: false,
            summary: summary,
            detail: detail
        )
    }

    /// Use the face embedding index to find which candidate's face
    /// is the closest match for a captured face region.
    private static func attributeViaFaceEmbedding(
        regionCG: CGImage,
        anchor: Minifigure,
        candidates: [Candidate]
    ) async -> Minifigure? {
        let hits = await FaceEmbeddingService.shared.nearestFigures(
            for: regionCG, topK: 16
        )
        let candidateIds = Set(candidates.map(\.figure.id))
        // Find the best hit that's a different figure from the anchor
        // AND is in our candidate set (so the user can see the context).
        for hit in hits where hit.cosine >= 0.55 {
            if hit.figureId != anchor.id && candidateIds.contains(hit.figureId) {
                return candidates.first(where: { $0.figure.id == hit.figureId })?.figure
            }
        }
        // If no candidate matches, try attributing to any catalog figure.
        for hit in hits where hit.cosine >= 0.60 {
            if hit.figureId != anchor.id {
                return await MinifigureCatalog.shared.figure(id: hit.figureId)
            }
        }
        return nil
    }

    /// Crop a specific anatomical region from the full figure image.
    private static func cropRegion(
        _ region: Analysis.Region,
        from cgImage: CGImage
    ) -> CGImage? {
        let w = cgImage.width
        let h = cgImage.height
        let rect: CGRect
        switch region {
        case .hair:
            rect = CGRect(
                x: Int(Double(w) * 0.30), y: 0,
                width: Int(Double(w) * 0.40), height: Int(Double(h) * 0.12)
            )
        case .head:
            rect = CGRect(
                x: Int(Double(w) * 0.25), y: Int(Double(h) * 0.17),
                width: Int(Double(w) * 0.50), height: Int(Double(h) * 0.18)
            )
        case .torso:
            rect = CGRect(
                x: Int(Double(w) * 0.15), y: Int(Double(h) * 0.28),
                width: Int(Double(w) * 0.70), height: Int(Double(h) * 0.40)
            )
        case .legs:
            rect = CGRect(
                x: Int(Double(w) * 0.20), y: Int(Double(h) * 0.65),
                width: Int(Double(w) * 0.60), height: Int(Double(h) * 0.35)
            )
        }
        return cgImage.cropping(to: rect)
    }

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

        // Estimate the background color from the four corners of each
        // image. The fixed brightness/saturation rule that BandData
        // used to apply only catches near-white backgrounds (CDN
        // renders); on real-world phone scans where the figure sits on
        // a dark wood table, brushed aluminum, a desk pad, etc. the
        // background pixels were being misclassified as foreground.
        // That caused the analyzer to attribute background-tinted
        // "hair regions" to candidate hair pieces (e.g. a brushed-
        // aluminum laptop palm rest reading as Catwoman's grey cowl
        // because aluminum LAB happens to land near light bluish
        // grey). Sampling the actual corners and excluding anything
        // within ΔE 12 of that color fixes both directions: white
        // CDN backgrounds AND any non-white user backdrop are
        // correctly dropped, so the missing-part path can fire.
        let capturedBackground = estimateBackgroundColor(cgImage: capturedCG)
        let anchorRefBackground = estimateBackgroundColor(cgImage: anchorRefCG)

        let capturedBands = sampleBands(cgImage: capturedCG, background: capturedBackground)
        let anchorBands = sampleBands(cgImage: anchorRefCG, background: anchorRefBackground)

        // Pre-compute band data for every other candidate so we can attribute
        // mismatched regions to specific figures.
        let otherCandidates: [(figure: Minifigure, bands: [Analysis.Region: BandData])] =
            candidates.dropFirst().compactMap { c in
                guard let cg = c.referenceImage.cgImage else { return nil }
                let bg = estimateBackgroundColor(cgImage: cg)
                return (c.figure, sampleBands(cgImage: cg, background: bg))
            }

        let matchThreshold: Double = 28
        // Coverage below this means "empty" (background dominates).
        let missingCoverageThreshold: Double = 0.10
        // Coverage below this means we have insufficient evidence to
        // confidently say anything about a band — skip it entirely
        // rather than report noise from a few stray pixels.
        let insufficientEvidenceThreshold: Double = 0.20

        // Generic LEGO yellow head detection: if the captured head band
        // is dominated by LEGO yellow (#F2CD37 ≈ LAB(86, -8, 75)), it's
        // a generic head and contains zero information about WHICH
        // figure this is — every minifig in the catalog has a yellow
        // head unless it's a licensed character. Don't even try to
        // attribute the head/face to another figure.
        let capturedHeadIsGenericYellow: Bool = {
            guard let head = capturedBands[.head]?.color else { return false }
            // Yellow ≈ L:85±10, a:-15..+5, b:60..90
            return head.L > 70 && head.a > -20 && head.a < 10
                && head.b > 50
        }()

        var findings: [Analysis.RegionFinding] = []
        for region in Analysis.Region.allCases {
            guard let capturedBand = capturedBands[region] else { continue }

            // ── REGION GATING (per user's 80/10/10 weighting guideline) ──
            // Torso designs are visually unique; everything else is too
            // generic to confidently cross-attribute. Filter rules:
            //   - hair  : only ever report MISSING (bald vs. hat). Never
            //             attribute "looks like X's hair" — hair color
            //             alone is non-discriminating across the catalog.
            //   - head  : skip entirely if generic yellow LEGO head.
            //             Otherwise still don't cross-attribute (faces
            //             are generic prints — only matter if missing).
            //   - torso : full match/mismatch/cross-attribute pipeline.
            //   - legs  : never cross-attribute — solid leg colors carry
            //             no figure-specific signal. Skip entirely.
            //
            // This eliminates the "the hair piece looks like Nearly
            // Headless Nick's hair" noise that appears when the
            // captured figure is bald but a faint background tint
            // happens to match another candidate's hair color.

            if region == .legs {
                // Skip legs from hybrid reporting entirely.
                continue
            }
            if region == .head && capturedHeadIsGenericYellow {
                // Generic yellow head — no information.
                continue
            }

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

            // Insufficient-evidence guard: too few foreground pixels in
            // the captured band to draw any conclusion. Skip silently
            // rather than emit a noisy "doesn't match" finding driven
            // by a handful of off-color pixels.
            if capturedBand.coverage < insufficientEvidenceThreshold {
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

            // Cross-attribution gate (per region):
            //   - torso : allowed (printed designs are distinctive)
            //   - hair  : NOT allowed — too generic, only `missing` matters
            //   - head  : NOT allowed — generic yellow already filtered;
            //             non-yellow heads are still mostly indistinct
            // For non-torso regions we just skip without recording an
            // `unknownMismatch` so we don't pollute the user-facing
            // detail string with vague "the head doesn't match" lines.
            guard region == .torso else { continue }

            // Captured TORSO band differs from anchor. Try to attribute
            // it to another candidate by finding the figure whose
            // corresponding band is the closest LAB match.
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
        let isHybrid = (matchedCount > 0 && anomalyCount > 0) || handMismatchOnly

        if isHybrid {
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

        // Clean match — all regions consistent with the anchor figure.
        let (cleanSummary, cleanDetail) = cleanMatchMessage(
            anchor: anchorCandidate.figure,
            findings: findings
        )
        return Analysis(
            isLikelyHybrid: false,
            anchorFigure: anchorCandidate.figure,
            findings: findings,
            unexpectedYellowHands: false,
            summary: cleanSummary,
            detail: cleanDetail
        )
    }

    // MARK: - Band sampling

    private struct BandData {
        let color: LAB?
        /// 0…1 — fraction of pixels in the band that are NOT background.
        let coverage: Double
    }

    nonisolated private static func sampleBands(
        cgImage: CGImage,
        background: LAB?
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
            out[region] = bandData(cgImage: cgImage, rect: rect, background: background)
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
        rect: CGRect,
        background: LAB?
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
            // Background heuristic A (legacy): very bright + very low
            // saturation. Captures white CDN reference backgrounds.
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let brightness = (maxC + minC) / 2.0
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
            if brightness > 0.92 && saturation < 0.10 { continue }
            // Skip near-black shadows that would dilute the dominant color.
            if brightness < 0.05 { continue }
            // Background heuristic B (sampled): if we have a corner-
            // estimated background color, drop anything within ΔE 12
            // of it. This catches non-white backgrounds (wood, fabric,
            // brushed aluminum) that heuristic A misses entirely.
            let lab = rgbToLAB(r: r, g: g, b: b)
            if let bg = background, labDistance(lab, bg) < 12 { continue }
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

    /// Estimate the background color of an image by sampling small
    /// patches at all four corners and returning the LAB centroid.
    /// Returns nil if the corners disagree wildly (i.e. the image
    /// likely doesn't have a clean uniform background).
    nonisolated private static func estimateBackgroundColor(
        cgImage: CGImage
    ) -> LAB? {
        let w = cgImage.width
        let h = cgImage.height
        let patch = max(8, min(w, h) / 16)  // ~6% of the smaller side
        let rects: [CGRect] = [
            CGRect(x: 0, y: 0, width: patch, height: patch),
            CGRect(x: w - patch, y: 0, width: patch, height: patch),
            CGRect(x: 0, y: h - patch, width: patch, height: patch),
            CGRect(x: w - patch, y: h - patch, width: patch, height: patch),
        ]
        var labs: [LAB] = []
        for rect in rects {
            guard let cropped = cgImage.cropping(to: rect),
                  let pixels = rgbaPixels(for: cropped) else { continue }
            var sumL = 0.0, sumA = 0.0, sumB = 0.0, n = 0.0
            for i in stride(from: 0, to: pixels.count - 3, by: 4) {
                let r = Double(pixels[i])     / 255.0
                let g = Double(pixels[i + 1]) / 255.0
                let b = Double(pixels[i + 2]) / 255.0
                let a = Double(pixels[i + 3]) / 255.0
                guard a > 0.5 else { continue }
                let lab = rgbToLAB(r: r, g: g, b: b)
                sumL += lab.L; sumA += lab.a; sumB += lab.b; n += 1
            }
            guard n > 0 else { continue }
            labs.append(LAB(L: sumL / n, a: sumA / n, b: sumB / n))
        }
        guard !labs.isEmpty else { return nil }
        // Centroid of the corner samples.
        let centroid = LAB(
            L: labs.reduce(0) { $0 + $1.L } / Double(labs.count),
            a: labs.reduce(0) { $0 + $1.a } / Double(labs.count),
            b: labs.reduce(0) { $0 + $1.b } / Double(labs.count)
        )
        // Sanity check: if any corner is more than ΔE 25 from the
        // centroid, the corners disagree (figure probably extends to
        // the edge of the frame or the lighting is wildly uneven). In
        // that case the centroid isn't a trustworthy background
        // estimate — fall back to the legacy white-only heuristic by
        // returning nil.
        let maxDev = labs.map { labDistance($0, centroid) }.max() ?? 0
        return maxDev < 25 ? centroid : nil
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

        // Count how many distinct other figures were identified.
        let otherFigures = Set(
            findings
                .filter { $0.kind == .matchesOtherFigure }
                .compactMap { $0.matchedFigure?.id }
        )
        let mixedSuffix: String
        if otherFigures.count > 1 {
            mixedSuffix = " This figure appears to be assembled from parts of at least \(otherFigures.count + 1) different figures."
        } else {
            mixedSuffix = " This figure may be assembled from parts of multiple sets or missing an accessory."
        }

        let detail = "\(anchorPhrase) (\(anchor.theme)\(yearSuffix)). " +
            issuesSentence +
            mixedSuffix
        return (summary, detail)
    }

    /// Build summary + detail for a clean (non-hybrid) match.
    private static func cleanMatchMessage(
        anchor: Minifigure,
        findings: [Analysis.RegionFinding]
    ) -> (summary: String, detail: String) {
        let matchedRegions = findings
            .filter { $0.kind == .matchesAnchor }
            .map { $0.region.displayName }
        let yearSuffix = anchor.year > 0 ? ", \(anchor.year)" : ""
        let regionList: String
        switch matchedRegions.count {
        case 0: regionList = "overall appearance"
        case 1: regionList = matchedRegions[0]
        case 2: regionList = "\(matchedRegions[0]) and \(matchedRegions[1])"
        default:
            let head = matchedRegions.dropLast().joined(separator: ", ")
            regionList = "\(head), and \(matchedRegions.last!)"
        }
        let summary = "Consistent match — \(anchor.name)"
        let detail = "The \(regionList) all appear consistent with \(anchor.name) (\(anchor.theme)\(yearSuffix))."
        return (summary, detail)
    }

    /// Pick "a" vs "an" using a vowel-sound check on the first letter.
    /// Good enough for figure / theme names; not a full English NLP rule.
    nonisolated private static func article(for word: String) -> String {
        guard let first = word.lowercased().first else { return "a" }
        return "aeiou".contains(first) ? "an" : "a"
    }
}
