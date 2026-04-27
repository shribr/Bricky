import XCTest
@testable import Bricky

@MainActor
final class MinifigureIdentificationServiceTests: XCTestCase {

    private func fig(_ id: String, _ name: String, theme: String = "Test") -> Minifigure {
        Minifigure(
            id: id,
            name: name,
            theme: theme,
            year: 2024,
            partCount: 0,
            imgURL: nil,
            parts: []
        )
    }

    private func catalogFigure(
        id: String,
        name: String,
        theme: String,
        torsoColor: String,
        torsoName: String = "Torso",
        headColor: String = "Yellow",
        legColor: String = "White",
        year: Int = 2026
    ) -> Minifigure {
        Minifigure(
            id: id,
            name: name,
            theme: theme,
            year: year,
            partCount: 5,
            imgURL: "https://example.com/\(id).png",
            parts: [
                MinifigurePartRequirement(
                    slot: .torso,
                    partNumber: "973",
                    color: torsoColor,
                    displayName: torsoName
                ),
                MinifigurePartRequirement(slot: .head, partNumber: "3626c", color: headColor),
                MinifigurePartRequirement(slot: .legLeft, partNumber: "970", color: legColor),
                MinifigurePartRequirement(slot: .legRight, partNumber: "970", color: legColor),
                MinifigurePartRequirement(slot: .hips, partNumber: "970", color: legColor)
            ]
        )
    }

    private func colorBlockImage(
        blocks: [(r: UInt8, g: UInt8, b: UInt8, startY: Int, endY: Int)],
        width: Int = 80,
        height: Int = 120
    ) -> CGImage? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        for y in 0..<height {
            let block = blocks.first { y >= $0.startY && y < $0.endY }
                ?? (r: UInt8(170), g: UInt8(170), b: UInt8(170), startY: 0, endY: height)
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                pixels[offset] = block.r
                pixels[offset + 1] = block.g
                pixels[offset + 2] = block.b
                pixels[offset + 3] = 255
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return context.makeImage()
    }

    private func insetFigureImage(width: Int = 120, height: Int = 160) -> CGImage? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                var color = (r: UInt8(154), g: UInt8(154), b: UInt8(150))
                if (38..<82).contains(x), (20..<135).contains(y) {
                    if y < 48 { color = (r: 246, g: 205, b: 55) }
                    else if y < 88 { color = (r: 40, g: 160, b: 52) }
                    else if y < 112 { color = (r: 190, g: 24, b: 16) }
                    else { color = (r: 238, g: 236, b: 226) }
                }
                pixels[offset] = color.r
                pixels[offset + 1] = color.g
                pixels[offset + 2] = color.b
                pixels[offset + 3] = 255
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return context.makeImage()
    }

    // MARK: - Fuzzy score

    func testFuzzyScoreIdenticalStringsIsOne() {
        XCTAssertEqual(
            MinifigureIdentificationService.fuzzyScore("spaceman", "spaceman"),
            1.0,
            accuracy: 0.001
        )
    }

    func testFuzzyScoreOneEmptyIsZero() {
        XCTAssertEqual(
            MinifigureIdentificationService.fuzzyScore("anakin", ""),
            0.0
        )
        XCTAssertEqual(
            MinifigureIdentificationService.fuzzyScore("", "anakin"),
            0.0
        )
    }

    func testFuzzyScoreSimilarStringsAreClose() {
        // "spaceman" vs "spacemen" — one-char swap.
        let score = MinifigureIdentificationService.fuzzyScore("spaceman", "spacemen")
        XCTAssertGreaterThan(score, 0.8)
    }

    func testFuzzyScoreDifferentStringsAreFarApart() {
        let score = MinifigureIdentificationService.fuzzyScore("spaceman", "wizard")
        XCTAssertLessThan(score, 0.5)
    }

    // MARK: - Evidence scanner core

    func testEvidenceCoreVetoesNonRedClipHitWhenScanIsStrongRed() {
        let greyLady = catalogFigure(
            id: "fig-grey-lady",
            name: "The Grey Lady",
            theme: "Harry Potter",
            torsoColor: "Light Blue",
            headColor: "White",
            legColor: "Gray"
        )
        let redSpaceman = catalogFigure(
            id: "fig-red-space",
            name: "Classic Spaceman, Red",
            theme: "Classic Space",
            torsoColor: "Red",
            torsoName: "Torso with Classic Space Logo",
            legColor: "White",
            year: 1979
        )

        let evidence = MinifigureIdentificationService.ScanColorEvidence(
            weights: [.red: 0.36, .white: 0.52, .yellow: 0.12],
            dominantColors: [.white, .red, .yellow]
        )
        let ranked = MinifigureIdentificationService.shared.rankWithEvidenceCore(
            allFigures: [greyLady, redSpaceman],
            evidence: evidence,
            clipHits: [
                ClipEmbeddingIndex.Hit(figureId: greyLady.id, cosine: 0.79),
                ClipEmbeddingIndex.Hit(figureId: redSpaceman.id, cosine: 0.70)
            ]
        )

        XCTAssertEqual(ranked.first?.figure?.id, redSpaceman.id)
        XCTAssertFalse(ranked.contains { $0.figure?.id == greyLady.id })
    }

    func testEvidenceCoreCapsConfidenceWhenClipAndColorDisagree() {
        let blackPilot = catalogFigure(
            id: "fig-black-pilot",
            name: "Pilot, Black Suit, Helmet",
            theme: "City",
            torsoColor: "Black",
            headColor: "Yellow",
            legColor: "Black"
        )
        let evidence = MinifigureIdentificationService.ScanColorEvidence(
            weights: [.red: 0.40, .white: 0.45, .yellow: 0.15],
            dominantColors: [.white, .red, .yellow]
        )
        let ranked = MinifigureIdentificationService.shared.rankWithEvidenceCore(
            allFigures: [blackPilot],
            evidence: evidence,
            clipHits: [ClipEmbeddingIndex.Hit(figureId: blackPilot.id, cosine: 0.82)]
        )

        XCTAssertTrue(ranked.isEmpty)
    }

    func testEvidenceCorePrefersRedWhiteClassicSpaceVariantWhenWhiteIsVisible() {
        let allRed = catalogFigure(
            id: "fig-all-red-space",
            name: "Classic Spaceman, Red with Airtanks (New Moulds)",
            theme: "Icons",
            torsoColor: "Red",
            torsoName: "Torso with Classic Space Logo",
            legColor: "Red",
            year: 2022
        )
        let redWhite = catalogFigure(
            id: "fig-red-white-space",
            name: "Classic Spaceman, Red with Airtanks and White Legs",
            theme: "Collectible Minifigures",
            torsoColor: "Red",
            torsoName: "Torso with Classic Space Logo",
            legColor: "White",
            year: 2008
        )
        let evidence = MinifigureIdentificationService.ScanColorEvidence(
            weights: [.darkRed: 0.44, .red: 0.34, .white: 0.14, .yellow: 0.06],
            dominantColors: [.darkRed, .red, .white, .yellow]
        )
        let ranked = MinifigureIdentificationService.shared.rankWithEvidenceCore(
            allFigures: [allRed, redWhite],
            evidence: evidence,
            clipHits: [
                ClipEmbeddingIndex.Hit(figureId: allRed.id, cosine: 0.80),
                ClipEmbeddingIndex.Hit(figureId: redWhite.id, cosine: 0.78)
            ]
        )

        XCTAssertEqual(ranked.first?.figure?.id, redWhite.id)
    }

    func testColorEvidenceRecognizesWarmOffWhitePixels() throws {
        let image = try XCTUnwrap(colorBlockImage(blocks: [
            (r: 242, g: 205, b: 55, startY: 0, endY: 30),
            (r: 210, g: 204, b: 190, startY: 30, endY: 70),
            (r: 190, g: 24, b: 16, startY: 70, endY: 120)
        ]))
        let evidence = MinifigureIdentificationService.shared.extractScanColorEvidence(from: image)

        XCTAssertGreaterThanOrEqual(evidence.whiteWeight, 0.08)
        XCTAssertTrue(evidence.hasStrongRed)
    }

    func testColorEvidenceIgnoresGrayBackgroundAroundColoredFigure() throws {
        let image = try XCTUnwrap(insetFigureImage())
        let evidence = MinifigureIdentificationService.shared.extractScanColorEvidence(from: image)

        XCTAssertGreaterThan(evidence.weights[.green] ?? 0, 0.10)
        XCTAssertTrue(evidence.hasStrongRed)
        XCTAssertGreaterThanOrEqual(evidence.whiteWeight, 0.08)
        XCTAssertFalse(evidence.dominantColors.prefix(3).contains(.gray))
        XCTAssertFalse(evidence.dominantColors.prefix(3).contains(.darkGray))
    }

    func testEvidenceCoreKeepsWideCandidatePoolForVisualRefinement() {
        let figures = (0..<180).map { index in
            catalogFigure(
                id: String(format: "fig-wide-%03d", index),
                name: "Wide Pool Candidate \(index)",
                theme: "Crowded Palette",
                torsoColor: index.isMultiple(of: 2) ? "Green" : "Red",
                legColor: index.isMultiple(of: 3) ? "Black" : "White",
                year: 2000 + index
            )
        }
        let evidence = MinifigureIdentificationService.ScanColorEvidence(
            weights: [.green: 0.27, .red: 0.25, .white: 0.22, .yellow: 0.14, .black: 0.12],
            dominantColors: [.green, .red, .white, .yellow, .black]
        )
        let clipHits = figures.prefix(170).enumerated().map { index, figure in
            ClipEmbeddingIndex.Hit(figureId: figure.id, cosine: Float(0.84 - Double(index) * 0.0007))
        }

        let ranked = MinifigureIdentificationService.shared.rankWithEvidenceCore(
            allFigures: figures,
            evidence: evidence,
            clipHits: clipHits
        )

        XCTAssertEqual(ranked.count, 160)
    }

    func testEvidenceCoreEliminatesCandidatesMissingDominantGreen() {
        let greenFigure = catalogFigure(
            id: "fig-green-subject",
            name: "Green Subject",
            theme: "Ninjago",
            torsoColor: "Green",
            legColor: "Green"
        )
        let redFigure = catalogFigure(
            id: "fig-red-distractor",
            name: "Red Distractor",
            theme: "City",
            torsoColor: "Red",
            legColor: "Red"
        )
        let whiteFigure = catalogFigure(
            id: "fig-white-distractor",
            name: "White Distractor",
            theme: "Speed Champions",
            torsoColor: "White",
            legColor: "White"
        )
        let evidence = MinifigureIdentificationService.ScanColorEvidence(
            weights: [.green: 0.46, .yellow: 0.18, .red: 0.12, .white: 0.10, .black: 0.08],
            dominantColors: [.green, .yellow, .red, .white, .black]
        )

        let ranked = MinifigureIdentificationService.shared.rankWithEvidenceCore(
            allFigures: [redFigure, whiteFigure, greenFigure],
            evidence: evidence,
            clipHits: [
                ClipEmbeddingIndex.Hit(figureId: redFigure.id, cosine: 0.86),
                ClipEmbeddingIndex.Hit(figureId: whiteFigure.id, cosine: 0.84),
                ClipEmbeddingIndex.Hit(figureId: greenFigure.id, cosine: 0.70)
            ]
        )

        XCTAssertEqual(ranked.map { $0.figure?.id }, [greenFigure.id])
    }

    // MARK: - Hat color tiebreaker (Forestman fig-006867 vs fig-006868)

    /// Build a Forestman-style figure with explicit hat color. Both
    /// variants share the same green torso/legs and yellow head — the
    /// only catalog difference between fig-006867 and fig-006868 is the
    /// hat color (Brown vs. Green) and plume color.
    private func forestmanFigure(id: String, hatColor: String) -> Minifigure {
        Minifigure(
            id: id,
            name: "Forestman Archer (\(hatColor) Hat)",
            theme: "Castle",
            year: 1989,
            partCount: 6,
            imgURL: "https://example.com/\(id).png",
            parts: [
                MinifigurePartRequirement(slot: .head, partNumber: "3626a", color: "Yellow"),
                MinifigurePartRequirement(slot: .hairOrHeadgear, partNumber: "4506", color: hatColor),
                MinifigurePartRequirement(
                    slot: .torso,
                    partNumber: "973c31h01pr0046",
                    color: "Green",
                    displayName: "Torso Forestman Tie Shirt and Purse Print"
                ),
                MinifigurePartRequirement(slot: .legLeft, partNumber: "970c31", color: "Green"),
                MinifigurePartRequirement(slot: .legRight, partNumber: "970c31", color: "Green"),
                MinifigurePartRequirement(slot: .hips, partNumber: "970c31", color: "Green")
            ]
        )
    }

    func testHatColorEvidencePromotesGreenHatForestmanOverBrownHatTwin() {
        let brownHat = forestmanFigure(id: "fig-006867", hatColor: "Brown")
        let greenHat = forestmanFigure(id: "fig-006868", hatColor: "Green")

        // Identical torso/legs colors → generic color agreement is tied.
        let evidence = MinifigureIdentificationService.ScanColorEvidence(
            weights: [.green: 0.42, .yellow: 0.18, .black: 0.10],
            dominantColors: [.green, .yellow, .black]
        )

        // CLIP slightly favors the brown-hat variant (mirrors the live
        // misranking where Icons/Castle Forestman variants tied very
        // closely on CLIP cosine).
        let clipHits = [
            ClipEmbeddingIndex.Hit(figureId: brownHat.id, cosine: 0.78),
            ClipEmbeddingIndex.Hit(figureId: greenHat.id, cosine: 0.76)
        ]
        let hat = MinifigureIdentificationService.HatColorEvidence(
            color: .green, coverage: 0.45
        )

        let ranked = MinifigureIdentificationService.shared.rankWithEvidenceCore(
            allFigures: [brownHat, greenHat],
            evidence: evidence,
            clipHits: clipHits,
            hatEvidence: hat
        )

        XCTAssertEqual(ranked.first?.figure?.id, greenHat.id,
            "Captured green hat must promote fig-006868 above fig-006867 (brown hat)")
        let brownConfidence = ranked.first(where: { $0.figure?.id == brownHat.id })?.confidence ?? 1
        XCTAssertLessThanOrEqual(brownConfidence, 0.55,
            "Brown-hat candidate must have its confidence capped when captured hat is clearly green")
    }

    func testHatColorEvidenceSkippedWhenCoverageLow() {
        let brownHat = forestmanFigure(id: "fig-006867", hatColor: "Brown")
        let greenHat = forestmanFigure(id: "fig-006868", hatColor: "Green")
        let evidence = MinifigureIdentificationService.ScanColorEvidence(
            weights: [.green: 0.42, .yellow: 0.18],
            dominantColors: [.green, .yellow]
        )
        let clipHits = [
            ClipEmbeddingIndex.Hit(figureId: brownHat.id, cosine: 0.82),
            ClipEmbeddingIndex.Hit(figureId: greenHat.id, cosine: 0.74)
        ]
        // Low-coverage hat evidence (bald scan / occluded) must NOT
        // override CLIP — fall back to CLIP top-1.
        let hat = MinifigureIdentificationService.HatColorEvidence(
            color: .green, coverage: 0.05
        )

        let ranked = MinifigureIdentificationService.shared.rankWithEvidenceCore(
            allFigures: [brownHat, greenHat],
            evidence: evidence,
            clipHits: clipHits,
            hatEvidence: hat
        )

        XCTAssertEqual(ranked.first?.figure?.id, brownHat.id)
    }

    func testHatColorEvidenceIgnoresNonChromaticCapturedHat() {
        let blackHelmetFig = forestmanFigure(id: "fig-aa", hatColor: "Black")
        let greenHatFig = forestmanFigure(id: "fig-bb", hatColor: "Green")
        let evidence = MinifigureIdentificationService.ScanColorEvidence(
            weights: [.green: 0.40, .yellow: 0.20],
            dominantColors: [.green, .yellow]
        )
        let clipHits = [
            ClipEmbeddingIndex.Hit(figureId: blackHelmetFig.id, cosine: 0.82),
            ClipEmbeddingIndex.Hit(figureId: greenHatFig.id, cosine: 0.74)
        ]
        // Captured "yellow" hat (e.g. yellow head bleeding into hair
        // band) is non-chromatic for our purposes → no penalty/boost.
        let hat = MinifigureIdentificationService.HatColorEvidence(
            color: .yellow, coverage: 0.40
        )

        let ranked = MinifigureIdentificationService.shared.rankWithEvidenceCore(
            allFigures: [blackHelmetFig, greenHatFig],
            evidence: evidence,
            clipHits: clipHits,
            hatEvidence: hat
        )

        XCTAssertEqual(ranked.first?.figure?.id, blackHelmetFig.id)
    }
}
