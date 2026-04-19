import SwiftUI
import ARKit
import RealityKit

/// UIViewRepresentable wrapper for ARView — used when tracking mode is `.arWorldTracking`.
/// Provides the AR camera feed with world tracking enabled.
struct ARCameraPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session = session
        arView.renderOptions = [.disablePersonOcclusion, .disableMotionBlur, .disableDepthOfField]
        // We only need the camera feed — no virtual content rendering
        arView.environment.background = .cameraFeed()
        arView.cameraMode = .ar
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Session is managed by ARCameraManager
    }
}
