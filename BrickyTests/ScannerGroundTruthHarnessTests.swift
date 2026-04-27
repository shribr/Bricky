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
        let notes: String?
    }

    // MARK: - Per-image result

    private struct ImageResult {
        let entry: Entry
        let topCandidates: [MinifigureIdentificationService.ResolvedCandidate]
        let elapsedSeconds: Double
        let error: String?

        /// 1-based rank of the correct figure in topCandidates, or nil if missing.
        var rank: Int? {
            for (idx, c) in topCandidates.enumerated() {
                if c.figure?.id == entry.figure_id { return idx + 1 }
            }
            return nil
        }
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
                    error: "Could not load image at \(imageURL.path)"
                ))
                continue
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
                    error: nil
                ))
            } catch {
                let elapsed = Date().timeIntervalSince(start)
                results.append(ImageResult(
                    entry: entry,
                    topCandidates: [],
                    elapsedSeconds: elapsed,
                    error: String(describing: error)
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
        lines.append("| # | filename | expected | rank | top-1 (conf) | top-2 (conf) | top-3 (conf) | elapsed |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
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
            lines.append("| \(idx + 1) | `\(r.entry.filename)` | `\(r.entry.figure_id)` | " +
                         "\(rank) | \(cells[0]) | \(cells[1]) | \(cells[2]) | " +
                         "\(String(format: "%.2fs", r.elapsedSeconds)) |")
        }
        lines.append("")

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
                lines.append("- `\(r.entry.filename)` → expected `\(r.entry.figure_id)`, \(rankStr)")
                if let notes = r.entry.notes, !notes.isEmpty {
                    lines.append("  - \(notes)")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
