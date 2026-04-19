import ARKit
import UIKit
import Combine

/// ARKit-based camera manager that provides world tracking alongside frame capture.
/// Drop-in replacement for CameraManager when tracking mode is `.arWorldTracking`.
@MainActor
final class ARCameraManager: NSObject, ObservableObject {
    @Published var error: CameraError?
    @Published var isSessionRunning = false
    @Published var capturedImage: UIImage?

    /// Current AR tracking state
    @Published var trackingState: ARCamera.TrackingState = .notAvailable
    /// Whether a horizontal plane has been detected
    @Published var hasDetectedPlane = false
    /// The primary detected horizontal plane anchor (scan surface)
    @Published var scanPlaneAnchor: ARPlaneAnchor?
    /// Current camera transform in world space
    @Published var cameraTransform: simd_float4x4 = matrix_identity_float4x4
    /// LiDAR scene-reconstruction mesh anchors (LiDAR devices only).
    /// Updated each frame the mesh changes. Empty array on non-LiDAR devices.
    @Published var meshAnchors: [ARMeshAnchor] = []

    /// Latest AR scene depth data (LiDAR or compatible TrueDepth-style devices).
    /// Nil on devices without `.sceneDepth` frame semantics support.
    nonisolated(unsafe) private(set) var latestSceneDepth: ARDepthData?
    /// Latest camera intrinsics + image resolution (for depth → world unprojection).
    nonisolated(unsafe) private(set) var latestCameraIntrinsics: simd_float3x3 = matrix_identity_float3x3
    nonisolated(unsafe) private(set) var latestImageResolution: CGSize = .zero

    let session = ARSession()
    private let delegateQueue = DispatchQueue(label: AppConfig.keychainPrefix + ".ar.delegate")

    /// Callback for each captured frame (CVPixelBuffer from ARFrame)
    var onFrameCaptured: ((CVPixelBuffer) -> Void)?

    /// Callback for each AR frame (includes camera transform + anchors)
    var onARFrameUpdated: ((ARFrame) -> Void)?

    // MARK: - Capability Flags

    /// Whether this device has LiDAR (supports scene reconstruction mesh).
    static var supportsLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    /// Whether this device exposes per-pixel scene depth.
    nonisolated static var supportsSceneDepth: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    enum CameraError: LocalizedError {
        case cameraUnavailable
        case arNotSupported
        case permissionDenied
        case trackingLost

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable: return "Camera is not available on this device."
            case .arNotSupported: return "ARKit world tracking is not supported on this device."
            case .permissionDenied: return "Camera permission was denied. Please enable it in Settings."
            case .trackingLost: return "AR tracking was lost. Try moving to a well-lit area with more visual features."
            }
        }
    }

    /// Whether this device supports AR world tracking
    static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    override init() {
        super.init()
    }

    func checkPermissions() {
        guard Self.isSupported else {
            error = .arNotSupported
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.error = .permissionDenied
                    }
                }
            }
        case .denied, .restricted:
            error = .permissionDenied
        @unknown default:
            break
        }
    }

    private func configureSession() {
        let config = ARWorldTrackingConfiguration()

        // Enable horizontal plane detection for finding the scan surface
        config.planeDetection = [.horizontal]

        // Use high-res video format for better Vision detection
        if let hiResFormat = ARWorldTrackingConfiguration.supportedVideoFormats
            .sorted(by: { $0.imageResolution.width > $1.imageResolution.width })
            .first {
            config.videoFormat = hiResFormat
        }

        // Enable scene reconstruction on LiDAR devices
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        // Auto-focus for close-up scanning
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }

        config.isAutoFocusEnabled = true

        session.delegate = self
        session.run(config)
        isSessionRunning = true
    }

    func startSession() {
        guard !isSessionRunning else { return }
        let config = session.configuration ?? {
            let c = ARWorldTrackingConfiguration()
            c.planeDetection = [.horizontal]
            c.isAutoFocusEnabled = true
            return c
        }()
        session.run(config)
        isSessionRunning = true
    }

    func stopSession() {
        guard isSessionRunning else { return }
        session.pause()
        isSessionRunning = false
    }

    /// Capture a high-res snapshot from the current AR frame
    func capturePhoto() {
        guard let frame = session.currentFrame else { return }
        let ciImage = CIImage(cvPixelBuffer: frame.capturedImage)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        capturedImage = UIImage(cgImage: cgImage)
    }

    // MARK: - World-Space Helpers

    /// Unproject a 2D screen point onto the detected horizontal plane.
    /// Returns a 3D world-space position, or nil if no plane is available.
    func unprojectToPlane(screenPoint: CGPoint, viewportSize: CGSize) -> simd_float3? {
        guard let frame = session.currentFrame else { return nil }

        // Try raycast against detected horizontal planes
        let normalizedPoint = CGPoint(
            x: screenPoint.x / viewportSize.width,
            y: screenPoint.y / viewportSize.height
        )

        // Convert to ARKit viewport coordinates
        let arPoint = CGPoint(
            x: normalizedPoint.x * CGFloat(frame.camera.imageResolution.width),
            y: normalizedPoint.y * CGFloat(frame.camera.imageResolution.height)
        )

        let query = frame.raycastQuery(from: arPoint, allowing: .existingPlaneGeometry, alignment: .horizontal)
        let results = session.raycast(query)
        if let hit = results.first {
            return simd_float3(
                hit.worldTransform.columns.3.x,
                hit.worldTransform.columns.3.y,
                hit.worldTransform.columns.3.z
            )
        }

        return nil
    }

    /// Unproject a Vision normalized bounding box center (origin bottom-left, 0–1)
    /// to a world-space position on the horizontal plane.
    func unprojectDetection(boundingBox: CGRect, viewportSize: CGSize) -> simd_float3? {
        // Vision coordinates: origin bottom-left
        // Screen coordinates: origin top-left
        let screenX = boundingBox.midX * viewportSize.width
        let screenY = (1 - boundingBox.midY) * viewportSize.height
        return unprojectToPlane(screenPoint: CGPoint(x: screenX, y: screenY), viewportSize: viewportSize)
    }

    /// Project a world-space 3D point back to screen coordinates.
    /// Returns normalized coordinates (0–1, origin top-left).
    func projectToScreen(worldPoint: simd_float3, viewportSize: CGSize) -> CGPoint? {
        guard let frame = session.currentFrame else { return nil }

        let point4 = simd_float4(worldPoint.x, worldPoint.y, worldPoint.z, 1.0)
        let camera = frame.camera

        // Project to camera image coordinates
        let projected = camera.projectPoint(
            simd_float3(point4.x, point4.y, point4.z),
            orientation: .portrait,
            viewportSize: viewportSize
        )

        let nx = projected.x / viewportSize.width
        let ny = projected.y / viewportSize.height

        // Check if point is in front of camera and within screen bounds
        guard nx >= -0.1 && nx <= 1.1 && ny >= -0.1 && ny <= 1.1 else { return nil }

        return CGPoint(x: nx, y: ny)
    }

    /// Check what fraction of a world-space rect is visible in the current camera frustum.
    /// Returns 0.0–1.0. Samples corners and center.
    func visibilityFraction(worldCorners: [simd_float3], viewportSize: CGSize) -> Double {
        guard !worldCorners.isEmpty else { return 0 }
        var visibleCount = 0
        for corner in worldCorners {
            if let pt = projectToScreen(worldPoint: corner, viewportSize: viewportSize),
               pt.x >= 0 && pt.x <= 1 && pt.y >= 0 && pt.y <= 1 {
                visibleCount += 1
            }
        }
        return Double(visibleCount) / Double(worldCorners.count)
    }

    /// Sample the LiDAR / scene depth at a screen point and return the
    /// corresponding world-space 3D position.
    ///
    /// - Parameters:
    ///   - normalizedScreenPoint: point in `[0, 1]` screen space, origin top-left.
    ///   - viewportSize: the SwiftUI view size the wireframe is being drawn in.
    /// - Returns: world-space (x, y, z) of the surface under that point, or nil
    ///   if depth is unavailable / invalid at that location.
    ///
    /// This is the core building block for the LiDAR topographic wireframe.
    /// The depth map is in the camera's landscape orientation; we rotate
    /// portrait coords → landscape pixel coords, read the depth, then
    /// unproject through the camera intrinsics to get world coords.
    func worldPosition(
        forNormalizedScreenPoint normalizedScreenPoint: CGPoint,
        viewportSize: CGSize
    ) -> simd_float3? {
        guard let depth = latestSceneDepth else { return nil }
        let buffer = depth.depthMap
        let pixelW = CVPixelBufferGetWidth(buffer)
        let pixelH = CVPixelBufferGetHeight(buffer)
        guard pixelW > 0, pixelH > 0 else { return nil }
        guard let frame = session.currentFrame else { return nil }
        let camera = frame.camera

        // Portrait normalized → landscape depth-pixel coords.
        // Portrait (px, py) → landscape (lx, ly) = (py · W, (1 − px) · H).
        let px = max(0, min(1, normalizedScreenPoint.x))
        let py = max(0, min(1, normalizedScreenPoint.y))
        let lx = Int(Float(py) * Float(pixelW))
        let ly = Int((1 - Float(px)) * Float(pixelH))
        guard lx >= 0, lx < pixelW, ly >= 0, ly < pixelH else { return nil }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let row = base.advanced(by: ly * bytesPerRow)
        let depthPtr = row.bindMemory(to: Float32.self, capacity: pixelW)
        let z = depthPtr[lx]
        guard z.isFinite, z > 0.05, z < 5.0 else { return nil }

        // Unproject through camera intrinsics. Intrinsics are expressed in
        // landscape image-resolution pixels — but we already converted to
        // landscape pixel coords scaled to the depth map, so first scale
        // back to image-resolution pixels.
        let imgW = Float(camera.imageResolution.width)
        let imgH = Float(camera.imageResolution.height)
        let u = Float(lx) * imgW / Float(pixelW)
        let v = Float(ly) * imgH / Float(pixelH)
        let intr = camera.intrinsics
        let fx = intr[0, 0], fy = intr[1, 1]
        let cx = intr[2, 0], cy = intr[2, 1]
        guard fx != 0, fy != 0 else { return nil }

        // Camera-space coords (right-handed, Y down, Z forward).
        let xCam = (u - cx) * z / fx
        let yCam = (v - cy) * z / fy
        let camPoint = simd_float4(xCam, yCam, z, 1)

        // Camera → world.
        let world4 = camera.transform * camPoint
        return simd_float3(world4.x, world4.y, world4.z)
    }
}

// MARK: - ARSessionDelegate

extension ARCameraManager: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Feed pixel buffer to Vision pipeline and AR frame for spatial processing
        let pixelBuffer = frame.capturedImage
        let trackingState = frame.camera.trackingState
        let transform = frame.camera.transform
        let intrinsics = frame.camera.intrinsics
        let imageRes = CGSize(width: frame.camera.imageResolution.width,
                              height: frame.camera.imageResolution.height)
        let depth = frame.sceneDepth ?? frame.smoothedSceneDepth

        // Cache nonisolated state synchronously (safe — only ARKit thread writes these).
        self.latestSceneDepth = depth
        self.latestCameraIntrinsics = intrinsics
        self.latestImageResolution = imageRes

        Task { @MainActor [weak self] in
            self?.onFrameCaptured?(pixelBuffer)
            self?.onARFrameUpdated?(frame)
            self?.trackingState = trackingState
            self?.cameraTransform = transform
        }
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let meshes = anchors.compactMap { $0 as? ARMeshAnchor }
        let planes = anchors.compactMap { $0 as? ARPlaneAnchor }.filter { $0.alignment == .horizontal }

        Task { @MainActor [weak self] in
            guard let self else { return }
            if !meshes.isEmpty {
                self.meshAnchors.append(contentsOf: meshes)
            }
            for plane in planes {
                if !self.hasDetectedPlane {
                    self.hasDetectedPlane = true
                    self.scanPlaneAnchor = plane
                }
                if let current = self.scanPlaneAnchor,
                   plane.planeExtent.width * plane.planeExtent.height >
                   current.planeExtent.width * current.planeExtent.height {
                    self.scanPlaneAnchor = plane
                }
            }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        let updatedMeshes = anchors.compactMap { $0 as? ARMeshAnchor }
        let updatedPlanes = anchors.compactMap { $0 as? ARPlaneAnchor }.filter { $0.alignment == .horizontal }

        Task { @MainActor [weak self] in
            guard let self else { return }
            if !updatedMeshes.isEmpty {
                let updatedIDs = Set(updatedMeshes.map(\.identifier))
                self.meshAnchors.removeAll { updatedIDs.contains($0.identifier) }
                self.meshAnchors.append(contentsOf: updatedMeshes)
            }
            for plane in updatedPlanes {
                if self.scanPlaneAnchor?.identifier == plane.identifier {
                    self.scanPlaneAnchor = plane
                }
            }
        }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let removedIDs = Set(anchors.compactMap { ($0 as? ARMeshAnchor)?.identifier })
        guard !removedIDs.isEmpty else { return }
        Task { @MainActor [weak self] in
            self?.meshAnchors.removeAll { removedIDs.contains($0.identifier) }
        }
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        Task { @MainActor [weak self] in
            self?.trackingState = camera.trackingState
        }
    }
}
