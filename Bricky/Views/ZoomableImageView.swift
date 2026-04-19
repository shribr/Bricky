import SwiftUI
import UIKit

/// Full-screen pinch-to-zoom + pan viewer for a remote image. Used by
/// minifigure detail and the scan confirmation sheet.
struct ZoomableImageView: View {
    let url: URL?
    let title: String
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var loadFailed = false
    @State private var loadTask: Task<Void, Never>?

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                content
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .onAppear { startLoad() }
        .onDisappear { loadTask?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(zoomGesture)
                    .simultaneousGesture(panGesture)
                    .onTapGesture(count: 2) { resetTransform() }
            }
        } else if loadFailed {
            VStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.6))
                Text("Image unavailable")
                    .foregroundStyle(.white.opacity(0.8))
            }
        } else {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
        }
    }

    // MARK: - Gestures

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1.0, min(lastScale * value, 6.0))
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.05 {
                    withAnimation(.spring(response: 0.3)) { resetTransform() }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.0 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func resetTransform() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }

    // MARK: - Loading

    private func startLoad() {
        guard image == nil, let url else {
            if url == nil { loadFailed = true }
            return
        }
        if let cached = MinifigureImageCache.shared.image(for: url) {
            image = cached
            return
        }
        // file:// URLs (user-added catalog images) load synchronously off the
        // local filesystem, not through URLSession's HTTP path.
        if url.isFileURL {
            if let data = try? Data(contentsOf: url),
               let img = UIImage(data: data) {
                MinifigureImageCache.shared.store(img, for: url, bytes: data.count)
                image = img
            } else {
                loadFailed = true
            }
            return
        }
        loadTask = Task {
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                let (data, _) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled, let img = UIImage(data: data) else {
                    if !Task.isCancelled { await MainActor.run { loadFailed = true } }
                    return
                }
                MinifigureImageCache.shared.store(img, for: url, bytes: data.count)
                await MainActor.run { image = img }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { loadFailed = true }
                }
            }
        }
    }
}
