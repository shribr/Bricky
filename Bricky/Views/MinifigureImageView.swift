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
                self.failed = true
                return
            }
            guard let img = UIImage(data: data) else {
                self.failed = true
                return
            }
            MinifigureImageCache.shared.store(img, for: url, bytes: data.count)
            self.image = img
        } catch {
            if Task.isCancelled { return }
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

/// Shared in-memory cache for minifig images. Bounded so we don't blow
/// up memory on long scroll sessions.
final class MinifigureImageCache {
    static let shared = MinifigureImageCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 500              // ~500 figures in memory
        cache.totalCostLimit = 64_000_000   // 64 MB
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL, bytes: Int) {
        cache.setObject(image, forKey: url as NSURL, cost: bytes)
    }

    /// Test-only: clear everything.
    func clear() {
        cache.removeAllObjects()
    }
}
