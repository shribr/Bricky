import SwiftUI
import AVFoundation

/// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.session = session
    }
}

class CameraPreviewView: UIView {
    var session: AVCaptureSession? {
        didSet {
            (layer as? AVCaptureVideoPreviewLayer)?.session = session
        }
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else { return }
        previewLayer.videoGravity = .resizeAspectFill
    }
}
