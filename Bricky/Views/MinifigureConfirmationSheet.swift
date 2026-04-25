import SwiftUI
import UIKit

/// Side-by-side confirmation step shown after the model returns a candidate.
/// The user sees the photo they captured next to the catalog artwork and
/// can confirm (saves to inventory + marks scanned) or reject.
struct MinifigureConfirmationSheet: View {
    let figure: Minifigure
    let candidate: MinifigureIdentificationService.ResolvedCandidate
    let capturedImage: UIImage?
    var analysisDetail: HybridFigureAnalyzer.Analysis?
    /// All candidates from the scan — used to show a "Similar Figures"
    /// section so the user can pick a better match without going back.
    var allCandidates: [MinifigureIdentificationService.ResolvedCandidate] = []
    let onConfirm: () -> Void
    let onReject: () -> Void
    /// Called when the user picks an alternative from the similar list.
    var onSelectAlternative: ((MinifigureIdentificationService.ResolvedCandidate) -> Void)?

    @StateObject private var collectionStore = MinifigureCollectionStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showZoomCaptured = false
    @State private var showZoomCatalog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    analysisBanner
                    headerRow
                    catalogHeroCard
                    detailsCard
                    yourScanRow
                    similarFiguresSection
                    actionsRow
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Is this a match?")
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
            Text("Compare this catalog figure to your scan")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Tap either image to enlarge")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Hero card: the catalog figurine front-and-center at maximum size,
    /// because that's the thing the user is being asked to evaluate.
    private var catalogHeroCard: some View {
        Button { showZoomCatalog = true } label: {
            ZStack(alignment: .bottomTrailing) {
                MinifigureImageView(url: figure.imageURL)
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .padding(12)
            }
        }
        .buttonStyle(.plain)
    }

    /// Smaller "Your Scan" reference row beneath the catalog hero so the
    /// user can side-check what they captured without it competing
    /// visually with the figure they're being asked to evaluate.
    private var yourScanRow: some View {
        HStack(spacing: 12) {
            Button { showZoomCaptured = true } label: {
                capturedTile
                    .frame(width: 90, height: 110)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text("Your Scan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Tap to enlarge")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
    }

    // MARK: - Similar Figures

    /// Other candidates from the scan (excluding the currently shown one)
    /// that the user can tap to switch to a different match.
    private var similarCandidates: [MinifigureIdentificationService.ResolvedCandidate] {
        allCandidates.filter { $0.figure != nil && $0.figure?.id != figure.id }
    }

    @ViewBuilder
    private var similarFiguresSection: some View {
        if !similarCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Similar Figures")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Not the right one? Try one of these:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(similarCandidates) { alt in
                    Button {
                        onSelectAlternative?(alt)
                    } label: {
                        similarFigureRow(alt)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        }
    }

    private func similarFigureRow(_ candidate: MinifigureIdentificationService.ResolvedCandidate) -> some View {
        HStack(spacing: 12) {
            MinifigureImageView(url: candidate.figure?.imageURL)
                .frame(width: 50, height: 60)

            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.figure?.name ?? candidate.modelName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let fig = candidate.figure {
                    Text("\(fig.theme)\(fig.year > 0 ? " · \(String(fig.year))" : "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(spacing: 2) {
                if candidate.isCloudAssisted {
                    Image(systemName: "icloud.fill")
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                }
                Text("\(Int(candidate.confidence * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(confidenceColor(candidate.confidence))
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
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

    private var analysisBanner: some View {
        Group {
            if let analysis = analysisDetail {
                Button { showZoomCaptured = true } label: {
                    HStack(spacing: 12) {
                        if let img = capturedImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 70, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                                )
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(analysis.summary)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            Text(analysis.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionsRow: some View {
        VStack(spacing: 10) {
            Button {
                onConfirm()
                dismiss()
            } label: {
                Label("Yes — this is a match", systemImage: "checkmark.circle.fill")
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
                Label("No — not a match", systemImage: "xmark.circle")
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
