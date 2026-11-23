import Foundation
import simd

/// Drives the "Send to 3D Printer" screen: loads the model's STL bytes once,
/// lets the user pick a printer build volume (a preset or a custom size),
/// choose whether to print at original size or scale down to fit, and then
/// hands off the (possibly scaled) STL for sharing/saving into a slicer.
///
/// Hardware-agnostic by design: Bricky never talks to a printer or slicer
/// directly. It only prepares a correctly sized STL and lets the system share
/// sheet hand it to whatever slicer the user has installed.
@MainActor
final class SendToPrinterViewModel: ObservableObject {
    let title: String
    private let stlProvider: () throws -> Data

    /// Bounding size of the loaded model, in millimetres. `nil` until loaded
    /// (or if loading failed / the model is empty).
    @Published private(set) var modelSizeMM: SIMD3<Float>?
    @Published private(set) var loadError: String?

    /// `nil` selects the `.custom` bed built from the custom* fields below.
    @Published var selectedPresetName: String? = PrintBed.presets.first?.name
    @Published var customWidthMM: Double = 220
    @Published var customDepthMM: Double = 220
    @Published var customHeightMM: Double = 250

    @Published var useOriginalSize = true

    @Published private(set) var isExporting = false
    @Published var exportedURL: URL?
    @Published var exportError: String?

    private var rawSTLData: Data?

    static let presets = PrintBed.presets

    init(title: String, stlProvider: @escaping () throws -> Data) {
        self.title = title
        self.stlProvider = stlProvider
    }

    /// Loads the STL once. Safe to call repeatedly (e.g. from `.task`).
    func loadIfNeeded() {
        guard rawSTLData == nil, loadError == nil else { return }
        do {
            let data = try stlProvider()
            rawSTLData = data
            guard let size = STLBounds.size(of: data) else {
                loadError = "This model has no printable geometry."
                return
            }
            modelSizeMM = size
        } catch {
            loadError = error.localizedDescription
        }
    }

    var selectedBed: PrintBed {
        if let name = selectedPresetName, let preset = Self.presets.first(where: { $0.name == name }) {
            return preset
        }
        return PrintBed(
            name: "Custom",
            sizeMM: SIMD3(Float(customWidthMM), Float(customDepthMM), Float(customHeightMM))
        )
    }

    var isCustomBedSelected: Bool { selectedPresetName == nil }

    /// Uniform scale that would make the model fit `selectedBed`.
    var fitScale: Float {
        guard let size = modelSizeMM else { return 1 }
        return selectedBed.fitScale(for: size)
    }

    /// Whether the model already fits `selectedBed` at 100%.
    var fitsAtOriginalSize: Bool {
        guard let size = modelSizeMM else { return true }
        return selectedBed.fits(size)
    }

    /// Scale percentage for display. Floors rather than rounds to nearest —
    /// ported from ServePoint's `PrintFitAdvisor.check`, which floors for the
    /// same reason: the displayed percentage must never overstate how much
    /// the model was shrunk.
    var fitScalePercent: Int {
        Int((fitScale * 100).rounded(.down))
    }

    /// Per-axis overage in millimetres at original size (0 where it fits).
    /// `nil` once the model has loaded if its size isn't known yet.
    var overageMM: SIMD3<Float>? {
        modelSizeMM.map { selectedBed.overageMM(for: $0) }
    }

    /// The "Scale Down to Fit Bed" row only makes sense when scaling would
    /// actually change anything.
    var needsScalingOption: Bool { !fitsAtOriginalSize }

    var willFitAfterChoice: Bool {
        useOriginalSize ? fitsAtOriginalSize : true
    }

    func selectPreset(_ bed: PrintBed) {
        selectedPresetName = bed.name
        if fitsAtOriginalSize { useOriginalSize = true }
    }

    func selectCustomBed() {
        selectedPresetName = nil
        if fitsAtOriginalSize { useOriginalSize = true }
    }

    /// Scales (if needed) and writes the STL to a temporary file, ready for
    /// `ShareSheet`. Call after `loadIfNeeded()` has populated `rawSTLData`.
    func exportForSharing() {
        guard let raw = rawSTLData else { return }
        isExporting = true
        exportError = nil

        let scale = useOriginalSize ? 1 : fitScale
        let data = STLScaler.scaled(raw, by: scale)
        let safeName = title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).stl")
        do {
            try data.write(to: url, options: .atomic)
            exportedURL = url
        } catch {
            exportError = error.localizedDescription
        }
        isExporting = false
    }
}
