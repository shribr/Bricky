import SwiftUI
import PhotosUI

/// Mosaic Studio — turn a photo into a buildable LEGO mosaic via the
/// LEGO Model Generation backend.
///
/// Flow: pick a photo → choose a size → generate. The view renders one honest
/// state at a time (idle / submitting / processing / completed / failed) driven
/// by `MosaicGeneratorViewModel.phase`. There is **no fabricated data**: if the
/// backend is unreachable the user sees a real error and a retry, not a fake
/// result.
///
/// The smallest mosaic size is free; larger sizes require Bricky Pro and surface
/// an honest paywall when a free user taps them.
struct MosaicGeneratorView: View {
    @StateObject private var viewModel = MosaicGeneratorViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageLoadError: String?
    @State private var shareItem: ShareItem?
    @State private var isPreparingShare = false
    @State private var partsSort: PartsSort = .quantity
    @State private var showPaywall = false
    @State private var showCamera = false
    @State private var didApplyPrefill = false
    @State private var show3DInstructions = false

    /// Optional photo to pre-load (e.g. "Regenerate" from a saved mosaic).
    private let prefillImage: UIImage?
    /// Optional size to pre-select alongside `prefillImage`.
    private let prefillPreset: MosaicGridPreset?

    /// Caps form-control width so inputs never stretch edge-to-edge on iPad.
    private let contentMaxWidth: CGFloat = 640

    init(prefillImage: UIImage? = nil, prefillPreset: MosaicGridPreset? = nil) {
        self.prefillImage = prefillImage
        self.prefillPreset = prefillPreset
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                content
            }
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L10n.mosaicTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: applyPrefillIfNeeded)
        .onChange(of: pickerItem) { _, newItem in
            Task { await loadPickedImage(newItem) }
        }
        .alert(
            L10n.mosaicErrorImageEncoding,
            isPresented: Binding(
                get: { imageLoadError != nil },
                set: { if !$0 { imageLoadError = nil } }
            )
        ) {
            Button(L10n.done, role: .cancel) {}
        } message: {
            Text(imageLoadError ?? "")
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker { image in
                viewModel.sourceImage = image
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $show3DInstructions) {
            if let assembly = viewModel.buildAssembly {
                BuildStepViewer(assembly: assembly, title: "Mosaic Instructions")
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var content: some View {
        header
        photoSection

        if viewModel.sourceImage != nil {
            sizeSection
            generateButton
        }

        switch viewModel.phase {
        case .submitting, .processing:
            progressSection
        case .failed:
            errorSection
        case .completed:
            resultSection
        case .idle:
            EmptyView()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(L10n.mosaicHeadline)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(L10n.mosaicSubheadline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Photo Picker

    private var photoSection: some View {
        let hasImage = viewModel.sourceImage != nil
        return VStack(spacing: 12) {
            if let image = viewModel.sourceImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(.separator))
                    )
            } else {
                emptyPhotoPlaceholder
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(
                        hasImage
                            ? L10n.mosaicChangePhoto
                            : L10n.mosaicChoosePhoto,
                        systemImage: "photo.on.rectangle"
                    )
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isBusy)

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label(L10n.mosaicTakePhoto, systemImage: "camera")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isBusy)
                }
            }
        }
    }

    private var emptyPhotoPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(L10n.mosaicChoosePhoto)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Size

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.mosaicMosaicSize)
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(MosaicGridPreset.allCases) { preset in
                    presetButton(preset)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func presetButton(_ preset: MosaicGridPreset) -> some View {
        let isSelected = viewModel.selectedPreset == preset
        let isUnlocked = viewModel.isPresetUnlocked(preset)
        return Button {
            if isUnlocked {
                viewModel.selectedPreset = preset
            } else {
                showPaywall = true
            }
        } label: {
            VStack(spacing: 4) {
                Text(preset.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !isUnlocked {
                    Label(L10n.mosaicProBadge, systemImage: "lock.fill")
                        .font(.caption2.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.blue : Color(.tertiarySystemFill))
            )
            .foregroundStyle(isSelected ? Color.white : (isUnlocked ? Color.primary : Color.secondary))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isBusy)
        .accessibilityLabel(isUnlocked ? preset.label : "\(preset.label), Pro")
    }

    private var generateButton: some View {
        Button {
            viewModel.generate()
        } label: {
            Text(L10n.mosaicGenerate)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .background(Color.blue)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(viewModel.canGenerate ? 1 : 0.5)
        .disabled(!viewModel.canGenerate)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 12) {
            ProgressView(value: viewModel.progressFraction)
                .progressViewStyle(.linear)
            Text(progressLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var progressLabel: String {
        switch viewModel.phase {
        case .submitting:
            return L10n.mosaicSubmitting
        case let .processing(percent):
            return "\(L10n.mosaicGenerating) \(percent)%"
        default:
            return L10n.mosaicGenerating
        }
    }

    // MARK: - Error

    private var errorSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text(viewModel.errorMessage ?? L10n.mosaicErrorServerGeneric)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                viewModel.generate()
            } label: {
                Text(L10n.mosaicTryAgain)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(!viewModel.canGenerate)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Result

    @ViewBuilder
    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.mosaicResultTitle)
                .font(.title3.weight(.bold))

            if let thumbnail = viewModel.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(.separator))
                    )
            }

            if let grid = viewModel.snappedGrid {
                Label(
                    L10n.mosaicGridSummary(grid.width, grid.height),
                    systemImage: "square.grid.3x3"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if let parts = viewModel.partsList {
                partsListView(parts)
            }

            captionSection

            if viewModel.buildAssembly != nil {
                view3DButton
            }
            artifactButtons
            startOverButton
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func partsListView(_ parts: MosaicPartsList) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.mosaicPartsList)
                    .font(.headline)
                Spacer()
                Picker("", selection: $partsSort) {
                    ForEach(PartsSort.allCases) { sort in
                        Text(sort.label).tag(sort)
                    }
                }
                .pickerStyle(.menu)
            }

            // Column header
            HStack {
                Text(L10n.mosaicColumnPart)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.mosaicColumnColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.mosaicColumnQty)
                    .frame(width: 56, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            ForEach(sortedParts(parts.parts)) { line in
                HStack {
                    Text(line.part)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(line.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(line.qty)")
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
                .font(.subheadline)
                Divider()
            }

            HStack {
                Text(L10n.mosaicTotalParts)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(parts.totalParts)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Caption & Description

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.mosaicCaptionSectionTitle)
                .font(.headline)

            if viewModel.isCaptionGenerated {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.mosaicCaptionLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(
                            L10n.mosaicCaptionLabel,
                            text: $viewModel.caption,
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: viewModel.caption) { _, _ in
                            viewModel.persistCaption()
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.mosaicDescriptionLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $viewModel.captionDescription)
                            .frame(minHeight: 96)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(.tertiarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color(.separator))
                            )
                            .onChange(of: viewModel.captionDescription) { _, _ in
                                viewModel.persistCaption()
                            }
                    }

                    Button {
                        viewModel.generateCaption()
                    } label: {
                        Label(L10n.mosaicRegenerateCaption, systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button {
                    viewModel.generateCaption()
                } label: {
                    Label(L10n.mosaicGenerateCaption, systemImage: "sparkles")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                }
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var view3DButton: some View {
        Button {
            show3DInstructions = true
        } label: {
            Label("3D Step-by-Step", systemImage: "cube.transparent")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.legoBlue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityHint("View the mosaic as interactive 3D build instructions")
    }

    private var artifactButtons: some View {
        VStack(spacing: 10) {
            artifactButton(
                title: L10n.mosaicDownloadModel,
                systemImage: "cube",
                kind: .ldraw
            )
            artifactButton(
                title: L10n.mosaicDownloadInstructions,
                systemImage: "doc.text",
                kind: .pdf
            )
        }
    }

    private func artifactButton(
        title: String,
        systemImage: String,
        kind: MosaicGeneratorViewModel.ArtifactKind
    ) -> some View {
        Button {
            Task { await shareArtifact(kind) }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if isPreparingShare {
                    ProgressView()
                }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .background(Color.blue)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .disabled(isPreparingShare)
    }

    private var startOverButton: some View {
        Button {
            pickerItem = nil
            partsSort = .quantity
            viewModel.reset()
        } label: {
            Text(L10n.mosaicStartOver)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Helpers

    private func sortedParts(_ parts: [MosaicPartLine]) -> [MosaicPartLine] {
        switch partsSort {
        case .quantity:
            return parts.sorted { $0.qty > $1.qty }
        case .part:
            return parts.sorted { $0.part < $1.part }
        case .color:
            return parts.sorted { $0.color < $1.color }
        }
    }

    /// Seed the generator with a photo/size handed in by a caller (e.g. the
    /// "Regenerate Mosaic" action on a saved mosaic). Runs once; the user can
    /// still pick a different photo or size afterward.
    @MainActor
    private func applyPrefillIfNeeded() {
        guard !didApplyPrefill else { return }
        didApplyPrefill = true
        guard let prefillImage, viewModel.sourceImage == nil else { return }
        viewModel.sourceImage = prefillImage
        if let prefillPreset, viewModel.isPresetUnlocked(prefillPreset) {
            viewModel.selectedPreset = prefillPreset
        }
    }

    private func loadPickedImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                imageLoadError = L10n.mosaicErrorImageEncoding
                return
            }
            viewModel.sourceImage = image
        } catch {
            imageLoadError = error.localizedDescription
        }
    }

    private func shareArtifact(_ kind: MosaicGeneratorViewModel.ArtifactKind) async {
        isPreparingShare = true
        defer { isPreparingShare = false }
        if let url = await viewModel.prepareArtifactFile(kind: kind) {
            shareItem = ShareItem(url: url)
        }
    }
}

// MARK: - Supporting Types

private extension MosaicGeneratorView {

    enum PartsSort: CaseIterable, Identifiable {
        case quantity
        case part
        case color

        var id: Self { self }

        var label: String {
            switch self {
            case .quantity: return L10n.mosaicColumnQty
            case .part: return L10n.mosaicColumnPart
            case .color: return L10n.mosaicColumnColor
            }
        }
    }

    struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }
}

// MARK: - Camera Picker

/// Minimal `UIImagePickerController` wrapper for capturing a mosaic source
/// photo with the camera. Mirrors the add-figure flow's picker so the mosaic
/// studio stays simple and offline-first — no AVFoundation session to manage.
#Preview {
    NavigationStack {
        MosaicGeneratorView()
    }
}
