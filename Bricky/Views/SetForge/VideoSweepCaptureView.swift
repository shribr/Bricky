import AVFoundation
import SwiftUI

/// Guided "record a sweep" capture: the user slowly orbits the subject while a
/// coverage ring fills, then the captured frames are handed back as multiple
/// views for the 3D (multiview) model path.
///
/// Device-only — the camera does not run in the simulator.
struct VideoSweepCaptureView: View {
    var onComplete: ([UIImage]) -> Void

    @StateObject private var sweep = VideoSweepCapture()
    @Environment(\.dismiss) private var dismiss
    @State private var permissionDenied = false

    var body: some View {
        ZStack {
            CameraPreview(session: sweep.session)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if permissionDenied {
                    permissionMessage
                } else {
                    coaching
                    controls
                }
            }
            .padding()
        }
        .statusBarHidden()
        .onAppear { requestAndStart() }
        .onDisappear { sweep.stop() }
        .onChange(of: sweep.completed) { _, done in
            guard done else { return }
            // Pass many evenly-spaced frames so on-device photogrammetry has
            // enough overlapping views to reconstruct real 3D geometry.
            let views = sweep.selectedViews(32)
            sweep.stop()
            onComplete(views)
            dismiss()
        }
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .padding(12)
                    .background(Circle().fill(.black.opacity(0.55)))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Cancel")
            Spacer()
            Text("3D Sweep")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.55)))
                .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var coaching: some View {
        VStack(spacing: 8) {
            Text(sweep.isSweeping
                 ? "Slowly walk around the subject — capture every side, then tap Finish."
                 : "Center the subject, then start the sweep")
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if sweep.isSweeping {
                Text(sweep.canFinish
                     ? "\(sweep.frameCount) views captured"
                     : "\(sweep.frameCount) captured — keep going (need \(sweep.minFramesToFinish))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.4)))
    }

    private var controls: some View {
        VStack(spacing: 16) {
            if sweep.isSweeping {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.25), lineWidth: 8)
                        .frame(width: 96, height: 96)
                    Circle()
                        .trim(from: 0, to: sweep.progress)
                        .stroke(Color.legoBlue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 96, height: 96)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title2)
                        .foregroundStyle(.white)
                }

                Button {
                    sweep.finishSweep()
                } label: {
                    Text(sweep.canFinish ? "Finish Scan" : "Keep Scanning…")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(sweep.canFinish ? Color.legoBlue : Color.gray.opacity(0.6))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .frame(maxWidth: 360)
                .disabled(!sweep.canFinish)
                .accessibilityHint(sweep.canFinish
                                   ? "Ends the sweep and builds the model"
                                   : "Capture at least \(sweep.minFramesToFinish) views first")
            } else {
                Button {
                    sweep.startSweep()
                } label: {
                    Text("Start Sweep")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.legoBlue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .frame(maxWidth: 360)
            }
        }
        .padding(.bottom, 12)
    }

    private var permissionMessage: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash.fill")
                .font(.largeTitle)
                .foregroundStyle(.white)
            Text("Camera access is needed to record a 3D sweep. Enable it in Settings.")
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.5)))
    }

    // MARK: - Permission + start

    private func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sweep.start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted { sweep.start() } else { permissionDenied = true }
                }
            }
        default:
            permissionDenied = true
        }
    }
}
