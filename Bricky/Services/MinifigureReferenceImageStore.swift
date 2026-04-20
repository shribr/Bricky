import Foundation
import UIKit

/// Provides offline access to a curated bundled set of minifigure
/// reference images. Used by the identification pipeline so first-time
/// scans work without an internet connection.
///
/// The set is built by `Tools/build-reference-set.py` and stored in
/// `Bricky/Resources/MinifigImages/`. Each image is keyed by figure ID
/// (e.g. `fig-000123.jpg`) and an `index.json` file maps IDs to
/// filenames so the store can quickly check whether a figure is bundled.
final class MinifigureReferenceImageStore {
    static let shared = MinifigureReferenceImageStore()

    private let bundledIds: Set<String>
    private let folderURL: URL?

    private init() {
        // Locate the MinifigImages folder in the app bundle. When added
        // to project.yml as a folder reference, all files inside are
        // copied with their original layout.
        let bundle = Bundle.main
        let folder = bundle.url(forResource: "MinifigImages", withExtension: nil)
        self.folderURL = folder

        // Load the index file. If it's missing or malformed, the store
        // simply reports zero bundled figures and the identification
        // pipeline falls back to the disk URL cache.
        var ids = Set<String>()
        if let folder = folder,
           let data = try? Data(contentsOf: folder.appendingPathComponent("index.json")),
           let payload = try? JSONDecoder().decode(IndexFile.self, from: data) {
            ids = Set(payload.files.keys)
        }
        self.bundledIds = ids
    }

    /// Total number of figures with bundled reference images.
    var bundledFigureCount: Int { bundledIds.count }

    /// Whether the given figure has a bundled reference image available.
    func hasImage(for figureId: String) -> Bool {
        bundledIds.contains(figureId)
    }

    /// Load the bundled reference image for the given figure ID.
    /// Returns nil if the figure is not in the curated set.
    func image(for figureId: String) -> UIImage? {
        guard bundledIds.contains(figureId), let folder = folderURL else { return nil }
        let path = folder.appendingPathComponent("\(figureId).jpg")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Index format

    private struct IndexFile: Decodable {
        let version: Int
        let figureCount: Int
        let files: [String: String]
    }
}
