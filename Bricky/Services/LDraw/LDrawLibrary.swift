import Foundation
import SceneKit

/// Loads and caches LDraw part definitions from the bundled
/// `LDraw/` resource folder, returning ready-to-render SCNNodes.
///
/// The bundle is expected to mirror the standard LDraw library layout:
/// ```
/// LDraw/
///   parts/         <- top-level parts (e.g. 3001.dat, 2423.dat)
///     s/           <- sub-parts referenced by parts
///   p/             <- primitives (cylinders, discs, etc.)
///     48/          <- high-resolution primitives
/// ```
///
/// All lookups are case-insensitive (the LDraw library is case-sensitive
/// on disk but references are not). Files are parsed once and cached.
final class LDrawLibrary {

    static let shared = LDrawLibrary()

    /// Root URL of the bundled LDraw library, or nil if unavailable.
    private let rootURL: URL?

    /// Parsed records cache, keyed by lowercased relative path or filename.
    private var recordsCache: [String: [LDrawParser.Record]] = [:]

    /// Cache of "file not found" lookups to avoid repeated disk scans.
    private var missCache: Set<String> = []

    /// Built node cache, keyed by `partNumber#colorCode`.
    private var nodeCache: [String: SCNNode] = [:]

    /// All file paths under the LDraw root, indexed by lowercased filename
    /// for fast cross-folder lookup (parts can reference primitives in `p/`,
    /// sub-parts in `parts/s/`, etc.).
    private let pathIndex: [String: URL]

    private let queue = DispatchQueue(label: AppConfig.ldrawQueue, attributes: .concurrent)

    private init() {
        self.rootURL = LDrawLibrary.findRoot()
        self.pathIndex = LDrawLibrary.buildIndex(root: self.rootURL)
    }

    // MARK: - Public API

    /// True when LDraw resources are available in the app bundle.
    var isAvailable: Bool { rootURL != nil && !pathIndex.isEmpty }

    /// Approximate count of bundled .dat files (parts + primitives).
    var fileCount: Int { pathIndex.count }

    /// Build an SCNNode for the given LEGO part, applying the piece's color.
    /// Returns nil if the part is not in the bundled library.
    func node(forPartNumber partNumber: String, color: LegoColor) -> SCNNode? {
        guard isAvailable else { return nil }
        let colorCode = LDrawColorMap.ldrawCode(for: color)
        let cacheKey = "\(partNumber.lowercased())#\(colorCode)"

        if let cached = queue.sync(execute: { nodeCache[cacheKey] }) {
            // NOTE: `flattenedClone()` silently drops custom-built geometry
            // sources/elements, producing an empty mesh on render. Use a
            // regular `clone()` so each caller gets an independent node
            // referencing the same shared geometry.
            return cached.clone()
        }

        // Try the part number directly, plus a few common LDraw suffix variants
        let candidates = candidateFileNames(for: partNumber)
        guard let records = firstAvailableRecords(in: candidates) else {
            return nil
        }

        let builder = LDrawGeometryBuilder { [weak self] name in
            self?.records(forFile: name)
        }
        let node = builder.buildNode(records: records, inheritedColorCode: colorCode)
        if node.childNodes.isEmpty { return nil }

        queue.async(flags: .barrier) { [weak self] in
            self?.nodeCache[cacheKey] = node
        }
        return node.clone()
    }

    /// Lookup parsed records for a file referenced from another file
    /// (e.g. `stud.dat`, `4-4cyli.dat`, `s/3001s01.dat`). Returns nil if missing.
    func records(forFile fileName: String) -> [LDrawParser.Record]? {
        let key = fileName.lowercased()

        if let cached = queue.sync(execute: { recordsCache[key] }) {
            return cached
        }
        if queue.sync(execute: { missCache.contains(key) }) {
            return nil
        }

        guard let url = locate(fileName: key),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            queue.async(flags: .barrier) { [weak self] in
                self?.missCache.insert(key)
            }
            return nil
        }

        let records = LDrawParser.parse(content)
        queue.async(flags: .barrier) { [weak self] in
            self?.recordsCache[key] = records
        }
        return records
    }

    // MARK: - File lookup

    /// Generate candidate filenames for a given LEGO part number.
    /// LDraw part files are typically `<number>.dat`, sometimes with a
    /// letter suffix (e.g. `3648b.dat` for variants).
    private func candidateFileNames(for partNumber: String) -> [String] {
        let lower = partNumber.lowercased()
        var candidates = ["\(lower).dat"]
        // Strip trailing letter variants (e.g., "3648b" → also try "3648")
        if let last = lower.last, last.isLetter {
            let trimmed = String(lower.dropLast())
            candidates.append("\(trimmed).dat")
        }
        return candidates
    }

    private func firstAvailableRecords(in candidates: [String]) -> [LDrawParser.Record]? {
        for name in candidates {
            if let r = records(forFile: name), !r.isEmpty {
                return r
            }
        }
        return nil
    }

    private func locate(fileName: String) -> URL? {
        // Strip any folder prefix from the reference; we resolve via the index.
        // Normalize Windows-style backslashes (LDraw library convention) to
        // forward slashes so `lastPathComponent` works correctly.
        let normalized = fileName.replacingOccurrences(of: "\\", with: "/")
        let baseName = (normalized as NSString).lastPathComponent.lowercased()
        return pathIndex[baseName]
    }

    // MARK: - Initialization helpers

    /// Locate the bundled LDraw root folder, if present.
    private static func findRoot() -> URL? {
        let bundle = Bundle.main
        // Prefer the folder reference (added with `type: folder` in project.yml)
        if let url = bundle.url(forResource: "LDraw", withExtension: nil),
           (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return url
        }
        return nil
    }

    /// Walk the LDraw root and build a flat `filename → URL` index.
    /// The LDraw library is small enough (<100K files even fully populated)
    /// that an in-memory index is fine, and far faster than per-lookup walks.
    private static func buildIndex(root: URL?) -> [String: URL] {
        guard let root else { return [:] }
        var index: [String: URL] = [:]
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "dat" else { continue }
            let key = url.lastPathComponent.lowercased()
            // First match wins — parts/ takes priority over p/ since we
            // walk in alphabetical order, but in the rare case a primitive
            // and a part share a name the existing entry is preserved.
            if index[key] == nil {
                index[key] = url
            }
        }
        return index
    }
}
