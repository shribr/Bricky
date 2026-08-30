import SwiftUI
import UIKit

/// Drives the LEGO mosaic generation flow entirely **on-device**: turn a photo
/// into a stud-aligned mosaic, then surface the finished artifacts (thumbnail,
/// parts list, exportable LDraw/PDF).
///
/// All of Bricky is offline-first, and mosaic generation is no exception —
/// there is no backend. Work runs on a detached task via `MosaicEngine`; if
/// anything fails the view model reports an honest, actionable message and
/// never fabricates a result. Mosaic generation is a Bricky Pro feature.
@MainActor
final class MosaicGeneratorViewModel: ObservableObject {

    /// Explicit lifecycle so the view renders one honest state at a time.
    enum Phase: Equatable {
        case idle
        case submitting
        case processing(percent: Int)
        case completed
        case failed(String)
    }

    /// A downloadable artifact the user can export/share.
    enum ArtifactKind: CaseIterable {
        case ldraw
        case pdf

        var filename: String {
            switch self {
            case .ldraw: return "model.ldr"
            case .pdf: return "instructions.pdf"
            }
        }
    }

    /// A completed on-device build: artifacts already written to a temporary
    /// job directory, ready to share. No network URLs.
    struct LocalResult: Equatable {
        let jobId: String
        let directory: URL
        let brickCount: Int
        let studCount: Int

        func fileURL(for kind: ArtifactKind) -> URL {
            directory.appendingPathComponent(kind.filename)
        }
    }

    // MARK: - Published State

    @Published var sourceImage: UIImage?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var snappedGrid: MosaicJobGrid?
    @Published private(set) var result: LocalResult?
    @Published private(set) var thumbnail: UIImage?
    @Published private(set) var partsList: MosaicPartsList?
    /// Assembly for the finished mosaic, driving the interactive 3D step viewer.
    @Published private(set) var buildAssembly: AssemblyModel?
    /// User-editable caption for the finished mosaic.
    @Published var caption: String = ""
    /// User-editable longer description for the finished mosaic.
    @Published var captionDescription: String = ""
    /// Whether a caption has been generated for the current result.
    @Published private(set) var isCaptionGenerated = false

    /// User-selected target size. Defaults to the medium (48×48) preset for Pro
    /// users, and the free preset for everyone else.
    @Published var selectedPreset: MosaicGridPreset = .medium

    /// The single mosaic size available on the free tier. All larger sizes
    /// require Bricky Pro.
    static let freePreset: MosaicGridPreset = .small

    // MARK: - Dependencies

    private let isProProvider: @MainActor () -> Bool
    private var generationTask: Task<Void, Never>?
    private let history: MosaicScanHistoryStore
    private var historyId: UUID?

    init(
        isProProvider: @escaping @MainActor () -> Bool = { SubscriptionManager.shared.isPro },
        history: MosaicScanHistoryStore? = nil
    ) {
        self.isProProvider = isProProvider
        self.history = history ?? .shared
        // Free users default to (and can only use) the free preset.
        if !isProProvider() {
            self.selectedPreset = Self.freePreset
        }
    }

    // MARK: - Derived State

    var isProUser: Bool { isProProvider() }

    /// Whether the given size is available to the current user. The free preset
    /// is always available; all larger sizes require Bricky Pro.
    func isPresetUnlocked(_ preset: MosaicGridPreset) -> Bool {
        isProUser || preset == Self.freePreset
    }

    var canGenerate: Bool {
        guard sourceImage != nil else { return false }
        guard isPresetUnlocked(selectedPreset) else { return false }
        switch phase {
        case .submitting, .processing:
            return false
        default:
            return true
        }
    }

    var isBusy: Bool {
        switch phase {
        case .submitting, .processing:
            return true
        default:
            return false
        }
    }

    var progressFraction: Double {
        switch phase {
        case .submitting:
            return 0.05
        case let .processing(percent):
            return Double(percent) / 100.0
        case .completed:
            return 1.0
        default:
            return 0.0
        }
    }

    var errorMessage: String? {
        if case let .failed(message) = phase { return message }
        return nil
    }

    // MARK: - Actions

    /// Generate a mosaic from the current source image.
    func generate() {
        guard let image = sourceImage else { return }
        guard !isBusy else { return }
        // Larger sizes are gated behind Pro; never generate a locked size.
        guard isPresetUnlocked(selectedPreset) else { return }

        cancel()
        result = nil
        thumbnail = nil
        partsList = nil
        buildAssembly = nil
        snappedGrid = nil
        caption = ""
        captionDescription = ""
        isCaptionGenerated = false
        historyId = nil
        phase = .submitting

        let preset = selectedPreset
        generationTask = Task { [weak self] in
            await self?.runGeneration(image: image, preset: preset)
        }
    }

    /// Cancel an in-flight generation and return to the prior state.
    func cancel() {
        generationTask?.cancel()
        generationTask = nil
    }

    /// Reset everything back to the initial state.
    func reset() {
        cancel()
        sourceImage = nil
        result = nil
        thumbnail = nil
        partsList = nil
        buildAssembly = nil
        snappedGrid = nil
        caption = ""
        captionDescription = ""
        isCaptionGenerated = false
        historyId = nil
        phase = .idle
    }

    /// Generate an honest caption and description from the finished mosaic.
    func generateCaption() {
        guard let parts = partsList, let grid = snappedGrid, let result else { return }
        let generated = MosaicCaptionGenerator.generate(
            width: grid.width,
            height: grid.height,
            parts: parts,
            brickCount: result.brickCount
        )
        caption = generated.caption
        captionDescription = generated.description
        isCaptionGenerated = true
        persistCaption()
    }

    /// Save the current (possibly user-edited) caption and description back to
    /// the saved history entry.
    func persistCaption() {
        guard let historyId else { return }
        history.updateCaption(id: historyId, caption: caption, detail: captionDescription)
    }

    // MARK: - Flow

    private func runGeneration(image: UIImage, preset: MosaicGridPreset) async {
        let jobId = UUID().uuidString
        let studs = preset.studs

        do {
            // Heavy Vision/Core Graphics work runs off the main actor.
            let output: MosaicEngineOutput = try await Task.detached(priority: .userInitiated) {
                try MosaicEngine.shared.generate(
                    image: image,
                    width: studs,
                    height: studs
                ) { fraction in
                    Task { @MainActor [weak self] in
                        self?.applyProgress(fraction)
                    }
                }
            }.value

            if Task.isCancelled { return }

            snappedGrid = output.snappedGrid
            thumbnail = output.thumbnail
            partsList = output.parts
            // Build the 3D assembly for the step-by-step viewer.
            if let palette = try? MosaicPalette.load(output.grid.paletteId) {
                buildAssembly = MosaicAssemblyBridge.assembly(bricks: output.bricks, palette: palette)
            }

            let local = try writeArtifacts(output, jobId: jobId)
            if Task.isCancelled { return }
            result = local
            historyId = history.record(
                gridWidth: output.grid.width,
                gridHeight: output.grid.height,
                brickCount: output.brickCount,
                studCount: output.studCount,
                totalParts: output.parts.totalParts,
                parts: output.parts.parts,
                presetLabel: preset.label,
                sourceImage: image,
                thumbnail: output.thumbnail,
                ldrText: output.ldrText,
                pdfData: output.pdfData
            )
            phase = .completed
        } catch is CancellationError {
            // User cancelled — cancel() already cleared the task.
        } catch {
            if !Task.isCancelled {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func applyProgress(_ fraction: Double) {
        guard isBusy else { return }
        let percent = min(100, max(0, Int((fraction * 100).rounded())))
        phase = .processing(percent: percent)
    }

    /// Write the LDraw and PDF artifacts to a temporary per-job directory.
    private func writeArtifacts(_ output: MosaicEngineOutput, jobId: String) throws -> LocalResult {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mosaic-\(jobId)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let ldrURL = directory.appendingPathComponent(ArtifactKind.ldraw.filename)
        try Data(output.ldrText.utf8).write(to: ldrURL, options: .atomic)

        let pdfURL = directory.appendingPathComponent(ArtifactKind.pdf.filename)
        try output.pdfData.write(to: pdfURL, options: .atomic)

        return LocalResult(
            jobId: jobId,
            directory: directory,
            brickCount: output.brickCount,
            studCount: output.studCount
        )
    }
}

// MARK: - Artifact Export

extension MosaicGeneratorViewModel {

    /// Return the on-disk URL for an artifact, suitable for a share sheet.
    /// Returns `nil` (never a fake file) when there is no result or the file is
    /// missing.
    func prepareArtifactFile(kind: ArtifactKind) async -> URL? {
        guard let result else { return nil }
        let url = result.fileURL(for: kind)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
