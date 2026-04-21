import os
import SwiftUI
import UIKit

/// Drop-in replacement for `AsyncImage` that keeps decoded `UIImage`s in
/// a shared in-memory cache (`NSCache`). SwiftUI's stock `AsyncImage`
/// throws away its image when the view goes off-screen, which causes
/// every tile in a `LazyVGrid` to re-fetch from the network on each scroll.
///
/// Also participates in `URLCache.shared` on disk for cold starts, but
/// the in-memory cache is what keeps scrolling smooth.
struct MinifigureImageView: View {
    let url: URL?

    @State private var image: UIImage?
    @State private var failed = false
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if failed || url == nil {
                MissingImagePlaceholder()
            } else {
                LoadingImagePlaceholder()
            }
        }
        .onAppear { start() }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .onChange(of: url) { _, _ in
            image = nil
            failed = false
            start()
        }
    }

    private func start() {
        guard image == nil, !failed, let url else { return }
        if let cached = MinifigureImageCache.shared.image(for: url) {
            self.image = cached
            return
        }
        loadTask?.cancel()
        loadTask = Task {
            await load(url)
        }
    }

    @MainActor
    private func load(_ url: URL) async {
        // file:// URLs (user-added catalog images stored in Documents) bypass
        // URLSession's HTTP path entirely.
        if url.isFileURL {
            if let data = try? Data(contentsOf: url),
               let img = UIImage(data: data) {
                MinifigureImageCache.shared.store(img, for: url, bytes: data.count)
                self.image = img
            } else {
                self.failed = true
            }
            return
        }

        do {
            var req = URLRequest(url: url)
            req.cachePolicy = .returnCacheDataElseLoad
            req.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                MinifigureImageCache.shared.recordFailure(for: url)
                self.failed = true
                return
            }
            guard let img = UIImage(data: data) else {
                MinifigureImageCache.shared.recordFailure(for: url)
                self.failed = true
                return
            }
            MinifigureImageCache.shared.store(img, for: url, bytes: data.count)
            self.image = img
        } catch {
            if Task.isCancelled { return }
            MinifigureImageCache.shared.recordFailure(for: url)
            self.failed = true
        }
    }
}

// MARK: - Placeholders (shared)

struct LoadingImagePlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
            ProgressView()
                .controlSize(.small)
        }
    }
}

struct MissingImagePlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
            VStack(spacing: 4) {
                Image(systemName: "person.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.legoBlue.opacity(0.4))
                Text("No image")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Cache

/// Shared image cache for minifig images.
///
/// Two-tier:
/// - **Memory** (`NSCache`): bounded, fast, cleared on memory pressure.
/// - **Disk** (`Caches/MinifigImages/`): persists across app launches.
///   Every image fetched from the network is also written to disk so the
///   minifigure scanner can use it for offline identification.
final class MinifigureImageCache {
    static let shared = MinifigureImageCache()

    private let cache = NSCache<NSURL, UIImage>()
    private let diskQueue = DispatchQueue(label: "com.bricky.minifigImageCache.disk", qos: .utility)
    private let diskDirectory: URL

    /// URLs that returned non-200, threw an error, or produced non-decodable
    /// data during the current session.  Used by the "Missing Images" catalog
    /// filter so it can catch dead CDN links that still have a non-nil URL in
    /// the catalog JSON.  Thread-safe via `OSAllocatedUnfairLock`.
    private let _failedURLs = OSAllocatedUnfairLock(initialState: Set<URL>())

    func recordFailure(for url: URL) {
        _failedURLs.withLock { _ = $0.insert(url) }
    }

    func hasFailed(_ url: URL) -> Bool {
        _failedURLs.withLock { $0.contains(url) }
    }

    var failedURLCount: Int {
        _failedURLs.withLock { $0.count }
    }

    private init() {
        cache.countLimit = 500              // ~500 figures in memory
        cache.totalCostLimit = 64_000_000   // 64 MB

        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskDirectory = cachesDir.appendingPathComponent("MinifigImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Memory tier

    func image(for url: URL) -> UIImage? {
        if let mem = cache.object(forKey: url as NSURL) {
            return mem
        }
        // Promote from disk if present (sync read, fast for ~20 KB JPEGs)
        if let onDisk = readDisk(url: url) {
            cache.setObject(onDisk, forKey: url as NSURL)
            return onDisk
        }
        return nil
    }

    func store(_ image: UIImage, for url: URL, bytes: Int) {
        cache.setObject(image, forKey: url as NSURL, cost: bytes > 0 ? bytes : 1)
        // Also persist to disk asynchronously (fire-and-forget) so
        // identification can use it offline later.
        writeDisk(image: image, url: url)
    }

    /// Synchronous disk lookup. Returns nil if not on disk.
    func diskImage(for url: URL) -> UIImage? {
        readDisk(url: url)
    }

    /// Test-only: clear everything (memory + disk).
    func clear() {
        cache.removeAllObjects()
        diskQueue.sync {
            try? FileManager.default.removeItem(at: diskDirectory)
            try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        }
    }

    /// Total bytes stored on disk (for diagnostics / settings UI).
    func diskByteCount() -> Int64 {
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: diskDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for case let url as URL in enumerator {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    // MARK: - Disk implementation

    private func diskPath(for url: URL) -> URL {
        // Stable filename derived from the URL string. Hash collisions are
        // astronomically rare for a 16K catalog.
        let key = String(format: "%016x", abs(url.absoluteString.hashValue))
        return diskDirectory.appendingPathComponent("\(key).jpg")
    }

    private func readDisk(url: URL) -> UIImage? {
        let path = diskPath(for: url)
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let img = UIImage(data: data) else {
            return nil
        }
        return img
    }

    private func writeDisk(image: UIImage, url: URL) {
        let path = diskPath(for: url)
        diskQueue.async {
            // JPEG @ quality 0.8 keeps each catalog image in the 10–25 KB range.
            guard let data = image.jpegData(compressionQuality: 0.8) else { return }
            try? data.write(to: path, options: .atomic)
        }
    }
}
