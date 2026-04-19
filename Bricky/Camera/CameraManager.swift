import AVFoundation
import UIKit
import Combine

/// Manages the camera session for live preview and frame capture
final class CameraManager: NSObject, ObservableObject {
    @Published var error: CameraError?
    @Published var isSessionRunning = false
    @Published var capturedImage: UIImage?

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: AppConfig.keychainPrefix + ".camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var photoOutput = AVCapturePhotoOutput()

    var onFrameCaptured: ((CVPixelBuffer) -> Void)?

    enum CameraError: LocalizedError {
        case cameraUnavailable
        case cannotAddInput
        case cannotAddOutput
        case permissionDenied
        case notReady

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable: return "Camera is not available on this device."
            case .cannotAddInput: return "Cannot add camera input to session."
            case .cannotAddOutput: return "Cannot add video output to session."
            case .permissionDenied: return "Camera permission was denied. Please enable it in Settings."
            case .notReady: return "Camera is still warming up. Try again in a second."
            }
        }
    }

    override init() {
        super.init()
    }

    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureSession()
                } else {
                    DispatchQueue.main.async {
                        self?.error = .permissionDenied
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in
                self?.error = .permissionDenied
            }
        @unknown default:
            break
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            // Add video input
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                DispatchQueue.main.async { self.error = .cameraUnavailable }
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                guard self.session.canAddInput(input) else {
                    DispatchQueue.main.async { self.error = .cannotAddInput }
                    return
                }
                self.session.addInput(input)

                // Configure autofocus for close-up LEGO scanning
                if camera.isFocusModeSupported(.continuousAutoFocus) {
                    try camera.lockForConfiguration()
                    camera.focusMode = .continuousAutoFocus
                    if camera.isAutoFocusRangeRestrictionSupported {
                        camera.autoFocusRangeRestriction = .near
                    }
                    // Target 30fps for smooth preview with recognition headroom
                    camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                    camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                    camera.unlockForConfiguration()
                }
            } catch {
                DispatchQueue.main.async { self.error = .cannotAddInput }
                return
            }

            // Add video output for frame analysis
            self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: AppConfig.keychainPrefix + ".camera.video"))
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]

            guard self.session.canAddOutput(self.videoOutput) else {
                DispatchQueue.main.async { self.error = .cannotAddOutput }
                return
            }
            self.session.addOutput(self.videoOutput)

            // Add photo output for high-res captures
            guard self.session.canAddOutput(self.photoOutput) else {
                DispatchQueue.main.async { self.error = .cannotAddOutput }
                return
            }
            self.session.addOutput(self.photoOutput)

            self.session.commitConfiguration()

            self.session.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
            }
        }
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = true
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else {
                DispatchQueue.main.async { self.error = .notReady }
                return
            }
            // photoOutput must have an active video connection. If
            // configureSession() hasn't completed, bail out with an error
            // instead of crashing in AVFoundation.
            guard self.photoOutput.connection(with: .video) != nil else {
                DispatchQueue.main.async { self.error = .notReady }
                return
            }
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

// MARK: - Video Frame Delegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        PerformanceMonitor.shared.recordFrame()
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Lighting assessment (every 10th frame to minimize overhead)
        if Int.random(in: 0..<10) == 0 {
            EnvironmentMonitor.shared.analyzeFrame(pixelBuffer)
        }
        onFrameCaptured?(pixelBuffer)
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        PerformanceMonitor.shared.recordDroppedFrame()
    }
}

// MARK: - Photo Capture Delegate
extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.capturedImage = image
        }
    }
}
