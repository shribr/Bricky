import XCTest
@testable import Bricky
import UIKit

/// # Scanner Ground-Truth Harness
///
/// Runs the *real* `MinifigureIdentificationService.identify(...)` pipeline
/// against a labeled set of captured scan photos and writes a markdown
/// report with recall@1, recall@5, and per-image rank.
///
/// ## Usage
///
/// 1. Drop captured scan images (jpg / png / heic) into:
///    `BrickyTests/GroundTruth/images/`
///
/// 2. Add an entry per image to
///    `BrickyTests/GroundTruth/manifest.json`:
///    ```json
///    {
///      "entries": [
///        { "filename": "scan-001.jpg", "figure_id": "fig-012345",
///          "notes": "green ninja, returned red firefighter at 0.81" }
///      ]
///    }
///    ```
///
/// 3. Run only the harness:
///    ```sh
///    xcodebuild test \
///      -project Bricky.xcodeproj -scheme Bricky \
///      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///      -only-testing:BrickyTests/ScannerGroundTruthHarnessTests
///    ```
///
/// 4. Read the report at:
///    `BrickyTests/GroundTruth/reports/report-<timestamp>.md`
///
/// ## Notes
///
/// - The harness forces `ScanSettings.identificationMode = .offlineFirst`
///   for the duration of the run (and restores the prior value), so cloud
///   fallback is disabled and runs are reproducible.
/// - It does NOT clear `UserCorrectionReranker` history. If the simulator
///   has saved corrections, they will affect ranking. The report records
///   the active scan mode and reranker state.
/// - The harness ALWAYS passes — it is a measurement, not a regression.
///   To catch regressions later, layer a separate test on top that asserts
///   recall@1 stays above some bar.
@MainActor
final class ScannerGroundTruthHarnessTests: XCTestCase {

    // MARK: - Manifest types

    private struct Manifest: Decodable {
        let entries: [Entry]
    }

    private struct Entry: Decodable {
        let filename: String
        let figure_id: String
        let rebrickable_id: String?
        let bricklink_id: String?
        let notes: String?
    }

    // MARK: - Per-image result

    private struct ImageResult {
        let entry: Entry
        let topCandidates: [MinifigureIdentificationService.ResolvedCandidate]
        let elapsedSeconds: Double
        let error: String?
        /// Per-image CLIP retrieval diagnostic. Captures CLIP availability,
        /// the rank of the expected figure inside CLIP's top-160 (1-based,
        /// nil if missing), and a short summary of the top-3 cosines.
        /// This lets us see whether the issue is CLIP retrieval (correct
        /// figure not in top-K), ranker fusion (CLIP found it but ranker
        /// buried it), or something else entirely.
        let clipAvailable: Bool
        let clipRank: Int?
        let clipExpectedCosine: Float?
        let clipTop3Summary: String
        /// Pipeline diagnostic: where the expected figure ranks in the FULL
        /// pipeline output (not just top-10), and the confidence gap between
        /// the pipeline's top-1 and the expected figure. Reveals whether
        /// the ranker has the right answer "close" or "buried in the noise".
        let fullCandidateCount: Int
        let expectedPipelineRank: Int?
        let expectedPipelineConfidence: Double?
        let topPipelineConfidence: Double?

        /// 1-based rank of the correct figure in topCandidates, or nil if missing.
        ///
        /// Match priority (first hit wins per candidate, scanning candidates
        /// in confidence order):
        /// 1. Direct id match against any of the manifest's known ids:
        ///    `rebrickable_id`, `bricklink_id`, or the legacy `figure_id`.
        ///    The catalog primarily uses Rebrickable `fig-NNNNNN`, but if
        ///    a candidate's id ever surfaces a BrickLink token we still
        ///    catch it.
        /// 2. Substring id match in either direction (handles ids that
        ///    embed each other, e.g. `sw0001a`).
        /// 3. Name match: when `notes` is non-empty we treat it as the
        ///    expected figure name and accept any candidate whose
        ///    `figure?.name` contains every significant token from it.
        ///    Lets the harness produce accurate recall when none of the
        ///    manifest ids exist in the local catalog.
        var rank: Int? {
            // Collect every id the manifest claims for this image and
            // dedupe. Empty / whitespace-only entries are dropped. We
            // also resolve the BrickLink id through the catalog's static
            // `bricklinkToRebrickable` table so a candidate emitted as
            // `fig-NNNNNN` still matches a manifest row that only has a
            // BrickLink id.
            var expectedIds: [String] = [
                entry.figure_id,
                entry.rebrickable_id ?? "",
                entry.bricklink_id ?? ""
            ]
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

            if let bl = entry.bricklink_id?.trimmingCharacters(in: .whitespaces),
               !bl.isEmpty,
               let mapped = MinifigureCatalog.rebrickableId(forBricklinkId: bl) {
                expectedIds.append(mapped.lowercased())
            }

            // Dedupe preserving order.
            expectedIds = expectedIds.reduce(into: [String]()) { acc, id in
                if !acc.contains(id) { acc.append(id) }
            }

            let nameTokens = Self.significantTokens(from: entry.notes ?? "")

            for (idx, c) in topCandidates.enumerated() {
                let candidateId = (c.figure?.id ?? "").lowercased()
                // Use figure.name (the actual catalog name) — modelName
                // on ResolvedCandidate is the source tag (e.g. "cloud",
                // "local+cloud"), not the figure description.
                let candidateName = (c.figure?.name ?? "").lowercased()

                // 1 + 2: try every known id (Rebrickable, BrickLink,
                // legacy figure_id) against the candidate id.
                if !candidateId.isEmpty {
                    for expected in expectedIds {
                        if candidateId == expected { return idx + 1 }
                        if candidateId.contains(expected) || expected.contains(candidateId) {
                            return idx + 1
                        }
                    }
                }

                // 3: name fallback.
                if !nameTokens.isEmpty,
                   nameTokens.allSatisfy({ candidateName.contains($0) }) {
                    return idx + 1
                }
            }
            return nil
        }

        /// Lowercased word tokens >= 3 chars from a free-form description,
        /// stripped of punctuation. Keeps the matcher tight enough that
        /// "Forestman" matches "Forestman, Quiver, Thin Moustache" but
        /// "Imperial Soldier" doesn't accidentally match unrelated rows.
        private static func significantTokens(from text: String) -> [String] {
            let allowed = CharacterSet.alphanumerics
            return text
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .map { $0.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined() }
                .filter { $0.count >= 3 }
        }
    }

    // MARK: - Expected-figure lookup helpers

    /// Returns the 1-based index of the manifest's expected figure inside
    /// the full pipeline candidate list, using the same id+name matching
    /// rules as `ImageResult.rank`. Lets us see if the expected fig is
    /// "buried at rank 47" vs missing entirely.
    private static func pipelineRank(
        of entry: Entry,
        in candidates: [MinifigureIdentificationService.ResolvedCandidate]
    ) -> Int? {
        Self.matchIndex(entry: entry, candidates: candidates).map { $0 + 1 }
    }

    private static func expectedConfidence(
        of entry: Entry,
        in candidates: [MinifigureIdentificationService.ResolvedCandidate]
    ) -> Double? {
        Self.matchIndex(entry: entry, candidates: candidates).map { candidates[$0].confidence }
    }

    private static func matchIndex(
        entry: Entry,
        candidates: [MinifigureIdentificationService.ResolvedCandidate]
    ) -> Int? {
        var expectedIds: [String] = [
            entry.figure_id,
            entry.rebrickable_id ?? "",
            entry.bricklink_id ?? ""
        ]
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        .filter { !$0.isEmpty }
        if let bl = entry.bricklink_id?.trimmingCharacters(in: .whitespaces),
           !bl.isEmpty,
           let mapped = MinifigureCatalog.rebrickableId(forBricklinkId: bl) {
            expectedIds.append(mapped.lowercased())
        }
        expectedIds = expectedIds.reduce(into: [String]()) { acc, id in
            if !acc.contains(id) { acc.append(id) }
        }
        let nameTokensAllowed = CharacterSet.alphanumerics
        let nameTokens = (entry.notes ?? "")
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.unicodeScalars.filter { nameTokensAllowed.contains($0) }.map(String.init).joined() }
            .filter { $0.count >= 3 }

        for (idx, c) in candidates.enumerated() {
            let candidateId = (c.figure?.id ?? "").lowercased()
            let candidateName = (c.figure?.name ?? "").lowercased()
            if !candidateId.isEmpty {
                for expected in expectedIds {
                    if candidateId == expected { return idx }
                    if candidateId.contains(expected) || expected.contains(candidateId) {
                        return idx
                    }
                }
            }
            if !nameTokens.isEmpty,
               nameTokens.allSatisfy({ candidateName.contains($0) }) {
                return idx
            }
        }
        return nil
    }

    // MARK: - Test entry point

    func testRunGroundTruthHarness() async throws {
        let datasetDir = Self.datasetDirectory()
        let manifestURL = datasetDir.appendingPathComponent("manifest.json")
        let imagesDir = datasetDir.appendingPathComponent("images")
        let reportsDir = datasetDir.appendingPathComponent("reports")

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            print("[Harness] No manifest at \(manifestURL.path) — skipping.")
            return
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)

        guard !manifest.entries.isEmpty else {
            print("[Harness] manifest.json has no entries — skipping. " +
                  "Add scan images to images/ and entries to manifest.json.")
            return
        }

        // Force a deterministic mode for the run.
        let originalMode = ScanSettings.shared.identificationMode
        ScanSettings.shared.identificationMode = .offlineFirst
        defer { ScanSettings.shared.identificationMode = originalMode }

        // Make sure the catalog is loaded before we start timing.
        await MinifigureCatalog.shared.load()

        var results: [ImageResult] = []
        results.reserveCapacity(manifest.entries.count)

        for entry in manifest.entries {
            let imageURL = imagesDir.appendingPathComponent(entry.filename)
            guard let image = Self.loadImage(at: imageURL) else {
                results.append(ImageResult(
                    entry: entry,
                    topCandidates: [],
                    elapsedSeconds: 0,
                    error: "Could not load image at \(imageURL.path)",
                    clipAvailable: ClipEmbeddingService.shared.isAvailable,
                    clipRank: nil,
                    clipExpectedCosine: nil,
                    clipTop3Summary: "",
                    fullCandidateCount: 0,
                    expectedPipelineRank: nil,
                    expectedPipelineConfidence: nil,
                    topPipelineConfidence: nil
                ))
                continue
            }

            // CLIP-only diagnostic: retrieve top-160 nearest figures from the
            // CLIP index and report where the expected figure lands. Done
            // BEFORE the full identify() call so its fusion/refinement
            // can't hide retrieval issues.
            let clipAvailable = ClipEmbeddingService.shared.isAvailable
            var clipRank: Int? = nil
            var clipExpectedCosine: Float? = nil
            var clipTop3Summary = ""
            if clipAvailable, let cg = image.cgImage {
                // Use the SAME crops production uses so the diagnostic
                // matches what `identifyWithEvidenceCore` actually feeds
                // to CLIP. A single-image diagnostic can otherwise show
                // misleading "rank 1" results that production never sees.
                let crops = MinifigureIdentificationService.shared.clipCandidateCrops(cgImage: cg)
                let hits = await ClipEmbeddingService.shared.nearestFigures(for: crops, topK: 160)
                let expected = (entry.rebrickable_id ?? entry.figure_id)
                    .trimmingCharacters(in: .whitespaces).lowercased()
                if !expected.isEmpty {
                    if let i = hits.firstIndex(where: { $0.figureId.lowercased() == expected }) {
                        clipRank = i + 1
                        clipExpectedCosine = hits[i].cosine
                    }
                }
                clipTop3Summary = hits.prefix(3).map {
                    "\($0.figureId)=\(String(format: "%.3f", $0.cosine))"
                }.joined(separator: ", ")
            }

            let start = Date()
            do {
                let candidates = try await MinifigureIdentificationService.shared
                    .identify(torsoImage: image)
                let elapsed = Date().timeIntervalSince(start)
                let topK = Array(candidates.prefix(10))
                results.append(ImageResult(
                    entry: entry,
                    topCandidates: topK,
                    elapsedSeconds: elapsed,
                    error: nil,
                    clipAvailable: clipAvailable,
                    clipRank: clipRank,
                    clipExpectedCosine: clipExpectedCosine,
                    clipTop3Summary: clipTop3Summary,
                    fullCandidateCount: candidates.count,
                    expectedPipelineRank: Self.pipelineRank(of: entry, in: candidates),
                    expectedPipelineConfidence: Self.expectedConfidence(of: entry, in: candidates),
                    topPipelineConfidence: candidates.first?.confidence
                ))
            } catch {
                let elapsed = Date().timeIntervalSince(start)
                results.append(ImageResult(
                    entry: entry,
                    topCandidates: [],
                    elapsedSeconds: elapsed,
                    error: String(describing: error),
                    clipAvailable: clipAvailable,
                    clipRank: clipRank,
                    clipExpectedCosine: clipExpectedCosine,
                    clipTop3Summary: clipTop3Summary,
                    fullCandidateCount: 0,
                    expectedPipelineRank: nil,
                    expectedPipelineConfidence: nil,
                    topPipelineConfidence: nil
                ))
            }
        }

        let report = Self.buildReport(
            results: results,
            modeUsed: .offlineFirst,
            originalMode: originalMode
        )
        print(report)

        // Ensure reports directory exists.
        try? FileManager.default.createDirectory(
            at: reportsDir,
            withIntermediateDirectories: true
        )

        let stamp = Self.timestamp()
        let reportURL = reportsDir.appendingPathComponent("report-\(stamp).md")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
        print("[Harness] Report written to \(reportURL.path)")
    }

    // MARK: - Helpers

    private static func datasetDirectory() -> URL {
        // #filePath resolves at compile time to the absolute path of this
        // source file on the build machine. The iOS Simulator runs on the
        // host Mac and can read from this path, which lets us keep the
        // dataset in source control without bundling it as a resource.
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile.deletingLastPathComponent()
            .appendingPathComponent("GroundTruth", isDirectory: true)
    }

    private static func loadImage(at url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    private static func buildReport(
        results: [ImageResult],
        modeUsed: ScanSettings.IdentificationMode,
        originalMode: ScanSettings.IdentificationMode
    ) -> String {
        let total = results.count
        let scored = results.filter { $0.error == nil }
        let correctAt1 = scored.filter { $0.rank == 1 }.count
        let correctAt5 = scored.filter { ($0.rank ?? Int.max) <= 5 }.count
        let foundAtAll = scored.filter { $0.rank != nil }.count
        let mrr: Double = {
            guard !scored.isEmpty else { return 0 }
            let sum = scored.reduce(0.0) { acc, r in
                guard let rank = r.rank else { return acc }
                return acc + 1.0 / Double(rank)
            }
            return sum / Double(scored.count)
        }()
        let avgElapsed: Double = {
            guard !scored.isEmpty else { return 0 }
            return scored.reduce(0.0) { $0 + $1.elapsedSeconds } / Double(scored.count)
        }()

        func pct(_ num: Int, _ den: Int) -> String {
            guard den > 0 else { return "n/a" }
            return String(format: "%.1f%%", Double(num) / Double(den) * 100)
        }

        var lines: [String] = []
        lines.append("# Scanner Ground-Truth Report")
        lines.append("")
        lines.append("- Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("- Total images: \(total)")
        lines.append("- Scored (no error): \(scored.count)")
        lines.append("- Mode forced for run: `\(modeUsed.rawValue)`")
        lines.append("- Mode restored after run: `\(originalMode.rawValue)`")
        lines.append("- Legacy scanner core flag: `Bricky.UseLegacyMinifigureScannerCore` = " +
                     "\(UserDefaults.standard.bool(forKey: "Bricky.UseLegacyMinifigureScannerCore"))")
        lines.append("")
        lines.append("## Summary")
        lines.append("")
        lines.append("| Metric | Value |")
        lines.append("| --- | --- |")
        lines.append("| recall@1 | \(correctAt1)/\(scored.count) (\(pct(correctAt1, scored.count))) |")
        lines.append("| recall@5 | \(correctAt5)/\(scored.count) (\(pct(correctAt5, scored.count))) |")
        lines.append("| found in top-10 | \(foundAtAll)/\(scored.count) (\(pct(foundAtAll, scored.count))) |")
        lines.append("| MRR (top-10) | \(String(format: "%.3f", mrr)) |")
        lines.append("| avg elapsed | \(String(format: "%.2fs", avgElapsed)) |")
        lines.append("")
        lines.append("## Per-image results")
        lines.append("")
        lines.append("| # | filename | expected (rebrickable / bricklink) | in catalog? | rank | top-1 (conf) | top-2 (conf) | top-3 (conf) | elapsed |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
        for (idx, r) in results.enumerated() {
            let rank = r.error != nil ? "ERR"
                : (r.rank.map(String.init) ?? "—")
            let cells = (0..<3).map { i -> String in
                guard i < r.topCandidates.count else { return "" }
                let c = r.topCandidates[i]
                let id = c.figure?.id ?? "?"
                let name = c.figure?.name ?? "?"
                return "\(id) “\(name)” (\(String(format: "%.2f", c.confidence)))"
            }
            let rebrickable = (r.entry.rebrickable_id ?? "").trimmingCharacters(in: .whitespaces)
            let bricklink = (r.entry.bricklink_id ?? "").trimmingCharacters(in: .whitespaces)
            let expectedDisplay = "\(rebrickable.isEmpty ? "—" : rebrickable) / \(bricklink.isEmpty ? "—" : bricklink)"
            // Cross-validate both ids against the catalog. The rebrickable id
            // is looked up directly; the bricklink id is resolved through the
            // hand-curated `bricklinkToRebrickable` table on MinifigureCatalog.
            // When BOTH resolve, we also check they point to the same entry —
            // mismatches surface as ✗ so a bad mapping shows up loudly.
            let inCatalog: String = {
                let rebFig = rebrickable.isEmpty ? nil : MinifigureCatalog.shared.figure(id: rebrickable)
                let blFig = bricklink.isEmpty ? nil : MinifigureCatalog.shared.figure(bricklinkId: bricklink)
                switch (rebFig, blFig) {
                case (nil, nil) where rebrickable.isEmpty && bricklink.isEmpty:
                    return "—"
                case (nil, nil):
                    return "✗"
                case (let r?, nil) where bricklink.isEmpty:
                    return "✓ (rebrickable)"
                case (nil, let b?) where rebrickable.isEmpty:
                    return "✓ (bricklink→\(b.id))"
                case (let r?, let b?) where r.id == b.id:
                    return "✓ (both)"
                case (let r?, let b?):
                    return "✗ mismatch (\(r.id) vs \(b.id))"
                case (_?, nil):
                    return "✓ rebrickable, BL unmapped"
                case (nil, _?):
                    return "✗ BL only (\(rebrickable) missing)"
                }
            }()
            lines.append("| \(idx + 1) | `\(r.entry.filename)` | `\(expectedDisplay)` | \(inCatalog) | " +
                         "\(rank) | \(cells[0]) | \(cells[1]) | \(cells[2]) | " +
                         "\(String(format: "%.2fs", r.elapsedSeconds)) |")
        }
        lines.append("")

        // CLIP retrieval diagnostic — isolates "embedding can't find it"
        // from "ranker buries it". For each image we already retrieved the
        // top-160 nearest figures from the CLIP index BEFORE running the
        // full identify() call. Here we report:
        //   - whether CLIP itself ranked the expected figure in top-160
        //   - that rank, and the cosine similarity of the expected figure
        //   - the actual top-3 cosines (so we can compare to top-1's score)
        let anyClip = results.contains { $0.clipAvailable }
        if anyClip {
            lines.append("## CLIP retrieval diagnostic")
            lines.append("")
            lines.append("CLIP available: \(results.first?.clipAvailable == true ? "yes" : "no")")
            lines.append("")
            lines.append("| # | filename | expected | clip rank | clip cos | clip top-3 |")
            lines.append("| --- | --- | --- | --- | --- | --- |")
            for (idx, r) in results.enumerated() {
                let expected = (r.entry.rebrickable_id ?? r.entry.figure_id)
                    .trimmingCharacters(in: .whitespaces)
                let rankStr: String
                if !r.clipAvailable { rankStr = "n/a" }
                else if let cr = r.clipRank { rankStr = String(cr) }
                else { rankStr = ">160" }
                let cosStr = r.clipExpectedCosine.map { String(format: "%.3f", $0) } ?? "—"
                lines.append("| \(idx + 1) | `\(r.entry.filename)` | `\(expected)` | " +
                             "\(rankStr) | \(cosStr) | \(r.clipTop3Summary) |")
            }
            lines.append("")

            // Pipeline-side companion table: where does the expected fig
            // actually land in the pipeline output, and what is the
            // confidence gap to the (wrong) top-1? This is the bridge
            // between "CLIP found it" and "user sees the right answer".
            lines.append("## Pipeline expected-figure landing")
            lines.append("")
            lines.append("| # | filename | expected pipeline rank | exp conf | top-1 conf | gap | total cands |")
            lines.append("| --- | --- | --- | --- | --- | --- | --- |")
            for (idx, r) in results.enumerated() {
                let expRank = r.expectedPipelineRank.map(String.init) ?? "missing"
                let expConf = r.expectedPipelineConfidence
                    .map { String(format: "%.3f", $0) } ?? "—"
                let topConf = r.topPipelineConfidence
                    .map { String(format: "%.3f", $0) } ?? "—"
                let gap: String = {
                    guard let t = r.topPipelineConfidence,
                          let e = r.expectedPipelineConfidence
                    else { return "—" }
                    return String(format: "%+.3f", e - t)
                }()
                lines.append("| \(idx + 1) | `\(r.entry.filename)` | \(expRank) | " +
                             "\(expConf) | \(topConf) | \(gap) | \(r.fullCandidateCount) |")
            }
            lines.append("")
        }

        let errored = results.filter { $0.error != nil }
        if !errored.isEmpty {
            lines.append("## Errors")
            lines.append("")
            for r in errored {
                lines.append("- `\(r.entry.filename)` → \(r.error ?? "unknown error")")
            }
            lines.append("")
        }

        let misses = results.filter { $0.error == nil && $0.rank != 1 }
        if !misses.isEmpty {
            lines.append("## Misses (rank ≠ 1) with notes")
            lines.append("")
            for r in misses {
                let rankStr = r.rank.map { "rank \($0)" } ?? "not in top-10"
                let rebrickable = (r.entry.rebrickable_id ?? "").trimmingCharacters(in: .whitespaces)
                let bricklink = (r.entry.bricklink_id ?? "").trimmingCharacters(in: .whitespaces)
                let idsDisplay = "rebrickable=`\(rebrickable.isEmpty ? "—" : rebrickable)` bricklink=`\(bricklink.isEmpty ? "—" : bricklink)`"
                lines.append("- `\(r.entry.filename)` → expected \(idsDisplay), \(rankStr)")
                if let notes = r.entry.notes, !notes.isEmpty {
                    lines.append("  - \(notes)")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
