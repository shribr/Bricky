import SwiftUI

#if canImport(RealityKit) && !targetEnvironment(simulator)
import RealityKit
#endif

/// Guided LiDAR **Object Capture** → a reconstructed `.usdz` model, handed to the
/// Set Forge voxelizer (`ForgeVisionViewModel.generateFromMesh`). RealityKit
/// Object Capture is device-only (LiDAR, iOS 17+), so the simulator and
/// unsupported devices show an honest "unavailable" state instead.
struct ObjectCaptureView: View {
    /// Called with the reconstructed model URL when capture + reconstruction finish.
    let onModel: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Whether guided Object Capture can run in this environment.
    static var isSupported: Bool {
        #if canImport(RealityKit) && !targetEnvironment(simulator)
        if #available(iOS 17.0, *) { return ObjectCaptureSession.isSupported }
        #endif
        return false
    }

    var body: some View {
        #if canImport(RealityKit) && !targetEnvironment(simulator)
        if #available(iOS 17.0, *), ObjectCaptureSession.isSupported {
            ObjectCaptureFlowView(
                onModel: { url in onModel(url); dismiss() },
                onCancel: { dismiss() }
            )
        } else {
            UnavailableCaptureView { dismiss() }
        }
        #else
        UnavailableCaptureView { dismiss() }
        #endif
    }
}

/// Shown when Object Capture isn't available (simulator, no LiDAR, or iOS < 17).
private struct UnavailableCaptureView: View {
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Object Capture Unavailable")
                    .font(.headline)
                Text("Scanning a real object into a full 3D model needs a LiDAR-equipped iPhone Pro or iPad Pro running iOS 17 or later. Try “Photograph 4 Angles” or “Record a Walk-Around” instead.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
    }
}

#if canImport(RealityKit) && !targetEnvironment(simulator)

/// The live device-only capture + reconstruction flow.
@available(iOS 17.0, *)
private struct ObjectCaptureFlowView: View {
    let onModel: (URL) -> Void
    let onCancel: () -> Void

    @State private var session = ObjectCaptureSession()
    @State private var isReconstructing = false
    @State private var progress: Double = 0
    @State private var errorText: String?

    /// Isolated working area under the app's temp directory.
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("object_capture_\(UUID().uuidString)", isDirectory: true)
    private var imagesDir: URL { root.appendingPathComponent("images", isDirectory: true) }
    private var modelURL: URL { root.appendingPathComponent("model.usdz") }

    var body: some View {
        ZStack {
            if isReconstructing {
                reconstructionOverlay
            } else {
                RealityKit.ObjectCaptureView(session: session)
                    .ignoresSafeArea()
                captureOverlay
            }
        }
        .onAppear(perform: startSession)
        .task { await observeState() }
        .alert("Capture Failed", isPresented: .constant(errorText != nil)) {
            Button("OK") { errorText = nil; onCancel() }
        } message: {
            Text(errorText ?? "")
        }
    }

    private var captureOverlay: some View {
        VStack {
            HStack {
                Button("Cancel") { session.cancel(); onCancel() }
                    .padding()
                Spacer()
            }
            Spacer()
            captureControls
                .padding(.bottom, 28)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private var captureControls: some View {
        switch session.state {
        case .ready:
            Button("Start Detecting") { _ = session.startDetecting() }
                .buttonStyle(.borderedProminent)
        case .detecting:
            Button("Start Capture") { session.startCapturing() }
                .buttonStyle(.borderedProminent)
        case .capturing:
            if session.userCompletedScanPass {
                HStack(spacing: 12) {
                    Button("Scan Another Side") { session.beginNewScanPass() }
                        .buttonStyle(.bordered)
                    Button("Finish") { session.finish() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Move slowly all the way around the object.")
                    .font(.subheadline)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        default:
            EmptyView()
        }
    }

    private var reconstructionOverlay: some View {
        VStack(spacing: 16) {
            ProgressView(value: progress) { Text("Building 3D model…") }
                .frame(maxWidth: 320)
            Text("\(Int(progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func startSession() {
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        session.start(imagesDirectory: imagesDir)
    }

    /// Drive reconstruction once the guided capture reports completion.
    private func observeState() async {
        for await state in session.stateUpdates {
            switch state {
            case .completed:
                await reconstruct()
                return
            case .failed(let error):
                errorText = error.localizedDescription
                return
            default:
                continue
            }
        }
    }

    private func reconstruct() async {
        isReconstructing = true
        do {
            let photogrammetry = try PhotogrammetrySession(input: imagesDir)
            try photogrammetry.process(requests: [.modelFile(url: modelURL, detail: .reduced)])
            for try await output in photogrammetry.outputs {
                switch output {
                case .requestProgress(_, let fraction):
                    progress = fraction
                case .processingComplete:
                    onModel(modelURL)
                    return
                case .requestError(_, let error):
                    errorText = error.localizedDescription
                    return
                default:
                    continue
                }
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#endif
