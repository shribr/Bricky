import Foundation
import UIKit

/// Persists per-`ScanSession` source images and pile boundaries to disk so
/// the "Find in Pile Photo" pushpin keeps working after the app is killed
/// and relaunched.
///
/// Layout on disk (under `Documents/scanAssets/`):
/// ```
/// Documents/scanAssets/
///   {sessionId}/
///     {captureIdx}.jpg     ← downscaled JPEG, ≤1920px long edge, q=0.8
///     boundaries.json      ← [Int: [CodableCGPoint]] (capture index → contour)
/// ```
///
/// Storage budget: ~250–500 KB per image × ~5–10 captures × 50 history
/// entries = ~125–250 MB worst case. JPEGs are loaded lazily on demand
/// (no caching beyond the call site) so memory pressure stays low.
@MainActor
final class ScanSessionAssetStore {
    static let shared = ScanSessionAssetStore()

    private let rootURL: URL
    /// Max long-edge in points used when downscaling source images for disk.
    /// 1920 keeps fine pile detail without ballooning storage.
    private let maxLongEdge: CGFloat = 1920
    /// JPEG quality used when persisting captures.
    private let jpegQuality: CGFloat = 0.8

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rootURL = docs.appendingPathComponent("scanAssets", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Persist all source images and pile boundaries from a session.
    /// Safe to call repeatedly — overwrites any existing assets for this session.
    func persist(session: ScanSession) {
        let dir = sessionDir(session.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Snapshot the dictionaries up-front to keep work off any race.
        let images = session.sourceImages
        let boundaries = session.pileBoundaries

        // Hop off the main actor so JPEG encoding doesn't stall the UI.
        Task.detached(priority: .utility) { [maxLongEdge, jpegQuality] in
            for (idx, image) in images {
                let downscaled = Self.downscale(image, maxLongEdge: maxLongEdge)
                guard let data = downscaled.jpegData(compressionQuality: jpegQuality) else { continue }
                let url = dir.appendingPathComponent("\(idx).jpg")
                try? data.write(to: url, options: .atomic)
            }

            let codable: [String: [CodablePoint]] = boundaries.reduce(into: [:]) { acc, kv in
                acc[String(kv.key)] = kv.value.map { CodablePoint(x: Double($0.x), y: Double($0.y)) }
            }
            if let json = try? JSONEncoder().encode(codable) {
                let url = dir.appendingPathComponent("boundaries.json")
                try? json.write(to: url, options: .atomic)
            }
        }
    }

    /// Load any persisted images/boundaries into the given session.
    /// Idempotent — only fills in entries that aren't already present.
    func restore(into session: ScanSession) {
        let dir = sessionDir(session.id)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }

        // Boundaries first (cheap).
        let boundariesURL = dir.appendingPathComponent("boundaries.json")
        if let data = try? Data(contentsOf: boundariesURL),
           let codable = try? JSONDecoder().decode([String: [CodablePoint]].self, from: data) {
            for (key, pts) in codable {
                guard let idx = Int(key), session.pileBoundaries[idx] == nil else { continue }
                session.pileBoundaries[idx] = pts.map { CGPoint(x: $0.x, y: $0.y) }
            }
        }

        // Images — load synchronously but cheaply (UIImage(contentsOfFile:)
        // is lazy and only decodes on first draw). Anything not on disk is
        // simply skipped.
        let fm = FileManager.default
        if let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in entries where url.pathExtension.lowercased() == "jpg" {
                let stem = url.deletingPathExtension().lastPathComponent
                guard let idx = Int(stem), session.sourceImages[idx] == nil else { continue }
                if let img = UIImage(contentsOfFile: url.path) {
                    session.sourceImages[idx] = img
                }
            }
        }
    }

    /// Delete all on-disk assets for a session. Called when its history
    /// entry is removed.
    func deleteAssets(for sessionId: UUID) {
        let dir = sessionDir(sessionId)
        try? FileManager.default.removeItem(at: dir)
    }

    /// Delete every session's assets — backs `ScanHistoryStore.clearAll`.
    func deleteAllAssets() {
        try? FileManager.default.removeItem(at: rootURL)
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    /// Total disk usage of persisted scan assets (bytes). Useful for a
    /// future "Manage Storage" settings row.
    func totalBytes() -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: rootURL,
                                              includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: - Internals

    private func sessionDir(_ id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    nonisolated private static func downscale(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxLongEdge else { return image }
        let scale = maxLongEdge / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Codable CGPoint shim. CGPoint isn't natively Codable in a
    /// keyed-by-Int map without help.
    private struct CodablePoint: Codable {
        let x: Double
        let y: Double
    }
}
