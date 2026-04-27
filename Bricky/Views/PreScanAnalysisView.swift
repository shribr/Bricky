import SwiftUI
import UIKit
import Combine

/// Pre-scan analysis view: shows a camera preview with a scan frame,
/// lets the user tap "Start Scan" to begin type detection, then routes
/// to the appropriate scanner (brick pile or minifigure).
///
/// The captured frame is passed to MinifigureScanView so identification
/// can start immediately without requiring another photo.
struct PreScanAnalysisView: View {
    @StateObject private var camera = CameraManager()
    @Environment(\.dismiss) private var dismiss

    enum ScanType: Equatable {
        case pile
        case minifigure
    }

    enum Phase: Equatable {
        case ready       // Camera running, waiting for user to tap Start
        case preparing   // Brief warm-up after tap
        case scanning    // Frame captured, analyzing
        case detecting   // Evaluating results
        case result(ScanType)
    }

    @State private var phase: Phase = .ready
    @State private var navigateToPile = false
    @State private var navigateToMinifigure = false
    @State private var hScanProgress: CGFloat = 0
    @State private var vScanProgress: CGFloat = 0
    @State private var selectedOverride: ScanType?
    @State private var preCapturedImage: UIImage?

    var body: some View {
        GeometryReader { geo in
            let frameW = max(0, geo.size.width - 56)
            let frameH = min(frameW * 1.1, geo.size.height * 0.40)

            ZStack {
                // Camera background
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()

                // Main layout — the dim overlay is built from the same VStack
                // so it always aligns with the scan frame.
                VStack(spacing: 0) {
                    // Top bar
                    topBar

                    // Top dim region (above scan frame)
                    Color.black.opacity(0.65)
                        .frame(maxWidth: .infinity)
                        .frame(height: 12)

                    // Scan frame with horizontal dim sides
                    HStack(spacing: 0) {
                        Color.black.opacity(0.65)
                            .frame(width: 28)
                        scanFrame(width: frameW, height: frameH)
                        Color.black.opacity(0.65)
                            .frame(width: 28)
                    }
                    .frame(height: frameH)

                    // Status section (below frame, on top of dim)
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.65)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        statusSection
                            .padding(.top, 24)
                            .padding(.horizontal, 24)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: phase)
        .statusBarHidden()
        .onAppear {
            camera.checkPermissions()
        }
        .onDisappear {
            camera.releaseCamera()
        }
        .navigationDestination(isPresented: $navigateToPile) {
            CameraScanView()
        }
        .navigationDestination(isPresented: $navigateToMinifigure) {
            MinifigureScanView(
                preCapturedImage: preCapturedImage
            )
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .padding(12)
                    .background(Circle().fill(.black.opacity(0.55)))
                    .foregroundStyle(.white)
            }
            Spacer()
            Text("Pre-Scan Analysis")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.55)))
                .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal)
    }

    // MARK: - Scan Frame

    private func scanFrame(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Frame border
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.7), lineWidth: 2.5)

            // Corner brackets
            cornerBrackets(width: width, height: height)

            // Scanning animations (active during scanning/detecting phases)
            if isScanning {
                // Horizontal scan line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .cyan.opacity(0.6), .cyan, .cyan.opacity(0.6), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, width - 20), height: 2)
                    .shadow(color: .cyan.opacity(0.5), radius: 8)
                    .offset(y: -height / 2 + 10 + hScanProgress * (height - 20))

                // Vertical scan line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .blue.opacity(0.5), .blue.opacity(0.7), .blue.opacity(0.5), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2, height: max(0, height - 20))
                    .shadow(color: .blue.opacity(0.4), radius: 6)
                    .offset(x: -width / 2 + 10 + vScanProgress * (width - 20))
            }

            // Checkmark when result is ready
            if isResult {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                    .shadow(color: .black.opacity(0.3), radius: 6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func cornerBrackets(width: CGFloat, height: CGFloat) -> some View {
        let len: CGFloat = 24
        let inset: CGFloat = 4
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: -width/2 + inset, y: -height/2 + inset + len))
                p.addLine(to: CGPoint(x: -width/2 + inset, y: -height/2 + inset))
                p.addLine(to: CGPoint(x: -width/2 + inset + len, y: -height/2 + inset))
            }
            .stroke(.white, lineWidth: 3)
            Path { p in
                p.move(to: CGPoint(x: width/2 - inset - len, y: -height/2 + inset))
                p.addLine(to: CGPoint(x: width/2 - inset, y: -height/2 + inset))
                p.addLine(to: CGPoint(x: width/2 - inset, y: -height/2 + inset + len))
            }
            .stroke(.white, lineWidth: 3)
            Path { p in
                p.move(to: CGPoint(x: -width/2 + inset, y: height/2 - inset - len))
                p.addLine(to: CGPoint(x: -width/2 + inset, y: height/2 - inset))
                p.addLine(to: CGPoint(x: -width/2 + inset + len, y: height/2 - inset))
            }
            .stroke(.white, lineWidth: 3)
            Path { p in
                p.move(to: CGPoint(x: width/2 - inset - len, y: height/2 - inset))
                p.addLine(to: CGPoint(x: width/2 - inset, y: height/2 - inset))
                p.addLine(to: CGPoint(x: width/2 - inset, y: height/2 - inset - len))
            }
            .stroke(.white, lineWidth: 3)
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(spacing: 16) {
            if phase == .ready {
                // Start scan button
                VStack(spacing: 16) {
                    Text("Point your camera at a LEGO minifigure or brick pile")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)

                    Button {
                        startAnalysis()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "viewfinder")
                                .font(.title3)
                            Text("Start Scan")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
            } else {
                // Progress steps
                VStack(spacing: 12) {
                    stepRow("Performing pre-scan analysis…",
                            active: true,
                            complete: phase != .preparing)
                    stepRow("Analyzing scene composition…",
                            active: phase == .scanning || phase == .detecting || isResult,
                            complete: phase == .detecting || isResult)
                    stepRow("Detecting scan type…",
                            active: phase == .detecting || isResult,
                            complete: isResult)
                    resultRow
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
            }

            // Scan type override + Continue (after result)
            if isResult {
                HStack(spacing: 12) {
                    typeToggle(.minifigure, icon: "person.fill", label: "Minifigure")
                    typeToggle(.pile, icon: "square.grid.3x3.fill", label: "Brick Pile")
                }
                .transition(.opacity)

                Button {
                    navigateToResult()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Button { dismiss() } label: {
                Text("Cancel")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.top, 4)
        }
    }

    private func typeToggle(_ type: ScanType, icon: String, label: String) -> some View {
        let isActive = effectiveScanType == type
        return Button {
            selectedOverride = type
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? Color.blue : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isActive ? Color.blue : Color.white.opacity(0.3), lineWidth: 1)
            )
            .foregroundStyle(isActive ? .white : .white.opacity(0.7))
        }
    }

    // MARK: - Step Rows

    private func stepRow(_ text: String, active: Bool, complete: Bool) -> some View {
        HStack(spacing: 12) {
            if complete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else if active {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.white.opacity(0.3))
                    .font(.title3)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(active ? .white : .white.opacity(0.4))
            Spacer()
        }
    }

    @ViewBuilder
    private var resultRow: some View {
        if case .result(.minifigure) = phase {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                Text("Minifigure detected. Tap Continue to identify.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
        } else if case .result(.pile) = phase {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                Text("Brick pile detected. Tap Continue to scan.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "circle")
                    .foregroundStyle(.white.opacity(0.3))
                    .font(.title3)
                Text("Identifying scan type…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private var isScanning: Bool {
        phase == .scanning || phase == .detecting
    }

    private var isResult: Bool {
        if case .result = phase { return true }
        return false
    }

    private var detectedScanType: ScanType? {
        if case .result(let type) = phase { return type }
        return nil
    }

    private var effectiveScanType: ScanType {
        selectedOverride ?? detectedScanType ?? .pile
    }

    // MARK: - Navigation

    private func navigateToResult() {
        camera.releaseCamera()
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let type = effectiveScanType
            switch type {
            case .pile: navigateToPile = true
            case .minifigure: navigateToMinifigure = true
            }
        }
    }

    // MARK: - Analysis Logic

    private func startAnalysis() {
        Task {
            // Phase 1: Brief camera stabilization
            phase = .preparing
            try? await Task.sleep(nanoseconds: 1_200_000_000)

            // Phase 2: Capture frame + analyze
            phase = .scanning
            startScanAnimations()
            try? await Task.sleep(nanoseconds: 600_000_000)

            guard let capturedImage = await captureFrameAsImage() else {
                stopScanAnimations()
                phase = .result(.pile)
                return
            }
            preCapturedImage = capturedImage

            // Run lightweight Vision-based probe (saliency + aspect ratio).
            // Fast: ~1-2 seconds, no network required.
            let probe = await MinifigureIdentificationService.shared
                .probeForMinifigure(image: capturedImage)

            // Phase 3: Evaluating
            phase = .detecting
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            stopScanAnimations()

            if probe.isMinifigure {
                phase = .result(.minifigure)
            } else {
                phase = .result(.pile)
            }
        }
    }

    private func startScanAnimations() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            hScanProgress = 1
        }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            vScanProgress = 1
        }
    }

    private func stopScanAnimations() {
        withAnimation(.easeOut(duration: 0.3)) {
            hScanProgress = 0.5
            vScanProgress = 0.5
        }
    }

    /// Capture a single frame from the camera's live feed as a UIImage.
    /// Applies portrait orientation since the camera sensor is landscape-native
    /// but the user is holding the phone vertically.
    private func captureFrameAsImage() async -> UIImage? {
        // Use AVCapturePhotoOutput (full-resolution still capture) instead
        // of grabbing a video preview frame. The preview stream caps out
        // around 1920×1080 with no HDR / exposure lock — which is roughly
        // 4× linear smaller than what the direct shutter path feeds the
        // identification pipeline. That resolution gap was producing
        // measurably worse CLIP / hat-color / hybrid-analyzer results
        // for figures routed through the type-detection flow vs. the
        // direct minifig scan flow.
        await withCheckedContinuation { continuation in
            var hasResumed = false

            // Watch for the photo to land on camera.capturedImage. We
            // don't have a direct callback API on CameraManager for
            // photo capture, so we observe the published property and
            // resume on the first non-nil value.
            var cancellable: AnyCancellable?
            cancellable = camera.$capturedImage
                .compactMap { $0 }
                .first()
                .sink { image in
                    guard !hasResumed else { return }
                    hasResumed = true
                    cancellable?.cancel()
                    // Bake EXIF orientation into the bitmap so .cgImage
                    // downstream sees a portrait pixel buffer.
                    let normalized = image.normalizedOrientation()
                    // Clear so the next capture (re-scan) doesn't fire
                    // the sink immediately with the stale image.
                    self.camera.capturedImage = nil
                    continuation.resume(returning: normalized)
                }

            camera.capturePhoto()

            // Safety timeout — preserves the prior 3s ceiling so the UI
            // never hangs forever if the photo pipeline stalls.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard !hasResumed else { return }
                hasResumed = true
                cancellable?.cancel()
                continuation.resume(returning: nil)
            }
        }
    }
}
