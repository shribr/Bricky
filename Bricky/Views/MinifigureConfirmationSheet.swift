import SwiftUI
import UIKit

/// Side-by-side confirmation step shown after the model returns a candidate.
/// The user sees the photo they captured next to the catalog artwork and
/// can confirm (saves to inventory + marks scanned) or reject.
struct MinifigureConfirmationSheet: View {
    let figure: Minifigure
    let candidate: MinifigureIdentificationService.ResolvedCandidate
    let capturedImage: UIImage?
    let onConfirm: () -> Void
    let onReject: () -> Void

    @StateObject private var collectionStore = MinifigureCollectionStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showZoomCaptured = false
    @State private var showZoomCatalog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerRow
                    comparisonCard
                    detailsCard
                    actionsRow
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Confirm Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color(.systemGroupedBackground))
        .sheet(isPresented: $showZoomCatalog) {
            ZoomableImageView(url: figure.imageURL, title: figure.name)
        }
        .fullScreenCover(isPresented: $showZoomCaptured) {
            ZoomableCapturedImageView(image: capturedImage, title: "Your scan")
        }
    }

    // MARK: - Sections

    private var headerRow: some View {
        VStack(spacing: 4) {
            Text("Is this your minifigure?")
                .font(.headline)
            Text("Tap an image to enlarge.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var comparisonCard: some View {
        HStack(alignment: .top, spacing: 12) {
            comparisonTile(
                title: "Your Scan",
                content: AnyView(capturedTile),
                onTap: { showZoomCaptured = true }
            )
            comparisonTile(
                title: "Catalog",
                content: AnyView(
                    MinifigureImageView(url: figure.imageURL)
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                ),
                onTap: { showZoomCatalog = true }
            )
        }
    }

    private func comparisonTile(title: String,
                                content: AnyView,
                                onTap: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Button(action: onTap) {
                content
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .black.opacity(0.55))
                            .padding(6)
                    }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var capturedTile: some View {
        if let img = capturedImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            VStack(spacing: 6) {
                Image(systemName: "camera")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(figure.name)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                Label(figure.theme, systemImage: "tag.fill")
                if figure.year > 0 {
                    Label("\(figure.year)", systemImage: "calendar")
                }
                Label("\(Int(candidate.confidence * 100))% match",
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(confidenceColor(candidate.confidence))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !candidate.reasoning.isEmpty {
                Text(candidate.reasoning)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
    }

    private var actionsRow: some View {
        VStack(spacing: 10) {
            Button {
                onConfirm()
                dismiss()
            } label: {
                Label("Yes, add to my collection", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.legoBlue, Color.legoBlue.opacity(0.85)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button {
                onReject()
                dismiss()
            } label: {
                Label("Not this one", systemImage: "xmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
            }
        }
    }

    private func confidenceColor(_ c: Double) -> Color {
        if c >= 0.75 { return .green }
        if c >= 0.5 { return .orange }
        return .red
    }
}

/// Lightweight zoomable wrapper for the locally captured `UIImage` (no network).
private struct ZoomableCapturedImageView: View {
    let image: UIImage?
    let title: String
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    GeometryReader { geo in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = max(1.0, min(lastScale * value, 6.0))
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                        if scale <= 1.05 { reset() }
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        guard scale > 1.0 else { return }
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in lastOffset = offset }
                            )
                            .onTapGesture(count: 2) { withAnimation { reset() } }
                    }
                } else {
                    Text("No image")
                        .foregroundStyle(.white)
                }
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
    }

    private func reset() {
        scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
    }
}
