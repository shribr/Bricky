import SwiftUI
import PhotosUI

/// Lets the user pick (or take) a photo of a brick pile and run the same
/// detection pipeline that the live camera uses. Two modes:
/// - **Whole photo** — analyze the entire image
/// - **Trace region** — freehand-draw a closed lasso to scope the scan
///
/// Reuses `CameraViewModel.processCapture(_:)` so detection, dedup, history
/// save, and `ScanResultsView` all "just work."
struct PhotoScanView: View {
    @StateObject private var viewModel = CameraViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var imageError: String?
    @State private var lassoPoints: [CGPoint] = []  // image-space, pre-rotation
    @State private var isTracingMode = false
    @State private var isProcessing = false
    @State private var navigateToResults = false

    // MARK: - Subject routing

    /// Whether the photo should be sent through the brick-pile pipeline
    /// (`CameraViewModel.processCapture`) or the minifigure pipeline
    /// (`MinifigureScanView` with a pre-captured image).
    enum SubjectMode: String, CaseIterable, Identifiable {
        case brick
        case minifigure
        var id: String { rawValue }
        var label: String {
            switch self {
            case .brick: return "Brick"
            case .minifigure: return "Minifigure"
            }
        }
    }

    @State private var subjectMode: SubjectMode = .brick
    /// Result of the most recent auto-classification, used to render a hint
    /// ("Detected: Minifigure" / "Looks like bricks" / "Couldn't tell").
    @State private var autoDetectedSubject: PhotoSubjectClassifier.Subject?
    @State private var isClassifying = false
    @State private var navigateToMinifigureScan = false
    @State private var minifigureScanImage: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = pickedImage {
                    photoCanvas(image: image)
                } else {
                    emptyPicker
                }

                if isProcessing {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView().tint(.white).scaleEffect(1.4)
                        Text("Scanning photo…")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                }
            }
            .navigationTitle("Scan a Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                if pickedImage != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Image(systemName: "photo.on.rectangle")
                        }
                        .accessibilityLabel("Pick a different photo")
                    }
                }
            }
            .navigationDestination(isPresented: $navigateToResults) {
                ScanResultsView(session: viewModel.scanSession)
            }
            .navigationDestination(isPresented: $navigateToMinifigureScan) {
                if let image = minifigureScanImage {
                    MinifigureScanView(preCapturedImage: image,
                                       skipEnhancement: false)
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                Task { await loadPickedImage(newItem) }
            }
            .alert("Couldn't load photo",
                   isPresented: Binding(get: { imageError != nil }, set: { if !$0 { imageError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(imageError ?? "")
            }
        }
    }

    // MARK: - Empty state

    private var emptyPicker: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.stack")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.6))
            Text("Pick a photo of your brick pile")
                .font(.headline)
                .foregroundStyle(.white)
            Text("\(AppConfig.appName) will identify pieces just like a live scan.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                    Text("Choose Photo")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.legoBlue)
                )
            }
            .accessibilityLabel("Choose Photo")
        }
        .padding()
    }

    // MARK: - Photo canvas (with optional lasso)

    @ViewBuilder
    private func photoCanvas(image: UIImage) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .accessibilityHidden(true)

                    // Lasso overlay — captures drag in view coordinates,
                    // converts to normalized [0,1] lasso points on commit.
                    if isTracingMode {
                        LassoOverlay(points: $lassoPoints,
                                     viewSize: geo.size)
                    }
                }
            }
            .clipped()

            controlBar
        }
    }

    // MARK: - Bottom action bar

    private var controlBar: some View {
        VStack(spacing: 10) {
            if isTracingMode {
                Text(lassoPoints.count >= 6
                     ? "Region traced — tap Scan Region to analyze"
                     : "Drag your finger to trace the area to scan")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button {
                        lassoPoints.removeAll()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(lassoPoints.isEmpty)

                    Button {
                        isTracingMode = false
                        lassoPoints.removeAll()
                    } label: {
                        Label("Whole Photo", systemImage: "rectangle")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button {
                        runScan()
                    } label: {
                        Label("Scan Region", systemImage: "wand.and.stars")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.legoBlue)
                    .disabled(lassoPoints.count < 6)
                }
            } else {
                subjectPicker

                HStack(spacing: 12) {
                    Button {
                        isTracingMode = true
                    } label: {
                        Label("Trace Region", systemImage: "scribble.variable")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    // Tracing a freehand region only makes sense for brick
                    // piles — minifigure ID needs the whole torso framed.
                    .disabled(subjectMode == .minifigure)
                    .opacity(subjectMode == .minifigure ? 0.4 : 1)

                    Button {
                        runScan()
                    } label: {
                        Label(scanButtonLabel, systemImage: "wand.and.stars")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.legoBlue)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.black.opacity(0.6))
    }

    // MARK: - Subject picker

    @ViewBuilder
    private var subjectPicker: some View {
        VStack(spacing: 6) {
            Picker("Subject", selection: $subjectMode) {
                ForEach(SubjectMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)

            Text(subjectHintText)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var subjectHintText: String {
        if isClassifying { return "Detecting subject…" }
        guard let detected = autoDetectedSubject else {
            return "Choose what's in the photo, then tap scan."
        }
        switch detected {
        case .minifigure:
            return "Detected: minifigure. Tap to override if wrong."
        case .brick:
            return "Looks like a brick or pile. Tap to override if wrong."
        case .ambiguous:
            return "Couldn't tell — pick the right mode before scanning."
        }
    }

    private var scanButtonLabel: String {
        switch subjectMode {
        case .minifigure: return "Scan Minifigure"
        case .brick: return "Scan Whole Photo"
        }
    }

    // MARK: - Photo loading

    private func loadPickedImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                let normalized = image.normalizedOrientation()
                await MainActor.run {
                    self.pickedImage = normalized
                    self.lassoPoints = []
                    self.isTracingMode = false
                    self.autoDetectedSubject = nil
                    self.isClassifying = true
                }
                let detected = await PhotoSubjectClassifier.classify(normalized)
                await MainActor.run {
                    self.isClassifying = false
                    self.autoDetectedSubject = detected
                    // Only auto-set the mode when the classifier is
                    // confident — leave .ambiguous alone so the user's
                    // current selection is preserved.
                    switch detected {
                    case .minifigure: self.subjectMode = .minifigure
                    case .brick: self.subjectMode = .brick
                    case .ambiguous: break
                    }
                }
            } else {
                await MainActor.run { imageError = "Photo data was unreadable." }
            }
        } catch {
            await MainActor.run { imageError = error.localizedDescription }
        }
    }

    // MARK: - Run the actual scan

    private func runScan() {
        guard let image = pickedImage else { return }

        // Minifigure mode bypasses the brick-pile pipeline entirely and
        // hands the image to MinifigureScanView, which auto-starts
        // identification on appear via its `preCapturedImage` path.
        if subjectMode == .minifigure {
            minifigureScanImage = image
            navigateToMinifigureScan = true
            return
        }

        isProcessing = true

        // Reset to a fresh session — picking a photo is a brand-new scan,
        // not a continuation of any live capture.
        viewModel.resetSession()

        // Crop to the lasso bounding box (with the rest masked out) so the
        // recognition pipeline only sees the region the user traced. If no
        // lasso, just run on the full photo.
        let imageToScan: UIImage = {
            guard isTracingMode, lassoPoints.count >= 6 else { return image }
            return PhotoLassoCrop.crop(image: image, normalizedPolygon: lassoPoints) ?? image
        }()

        viewModel.processCapture(imageToScan)

        // processCapture is async behind the scenes — ScanSession publishes
        // pieces as they're identified. Wait briefly for the recognition
        // service to finish before navigating.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // Poll once per 0.25s for up to 8s.
            pollUntilDone(maxAttempts: 32, delay: 0.25)
        }
    }

    private func pollUntilDone(maxAttempts: Int, delay: TimeInterval) {
        guard maxAttempts > 0 else {
            finishScan()
            return
        }
        if !viewModel.recognitionService.isProcessing {
            finishScan()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            pollUntilDone(maxAttempts: maxAttempts - 1, delay: delay)
        }
    }

    private func finishScan() {
        isProcessing = false
        navigateToResults = true
    }
}

// MARK: - Lasso overlay

/// Captures a freehand stroke and renders it as a yellow path with a
/// translucent fill. Stores normalized [0,1] points in the bound array.
private struct LassoOverlay: View {
    @Binding var points: [CGPoint]      // normalized 0–1
    let viewSize: CGSize

    @State private var liveStroke: [CGPoint] = []  // view-space, while dragging

    var body: some View {
        ZStack {
            // Committed path
            if !points.isEmpty {
                Path { p in
                    let viewPts = points.map {
                        CGPoint(x: $0.x * viewSize.width, y: $0.y * viewSize.height)
                    }
                    p.move(to: viewPts[0])
                    for pt in viewPts.dropFirst() { p.addLine(to: pt) }
                    p.closeSubpath()
                }
                .fill(Color.yellow.opacity(0.18))

                Path { p in
                    let viewPts = points.map {
                        CGPoint(x: $0.x * viewSize.width, y: $0.y * viewSize.height)
                    }
                    p.move(to: viewPts[0])
                    for pt in viewPts.dropFirst() { p.addLine(to: pt) }
                    p.closeSubpath()
                }
                .stroke(Color.yellow, lineWidth: 2.5)
            }

            // Live stroke being drawn
            if !liveStroke.isEmpty {
                Path { p in
                    p.move(to: liveStroke[0])
                    for pt in liveStroke.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let p = clamp(value.location, to: viewSize)
                    if liveStroke.isEmpty || liveStroke.last.map({ distance($0, p) > 4 }) ?? true {
                        liveStroke.append(p)
                    }
                }
                .onEnded { _ in
                    guard liveStroke.count >= 6 else {
                        liveStroke.removeAll()
                        return
                    }
                    let normalized = liveStroke.map {
                        CGPoint(x: $0.x / viewSize.width, y: $0.y / viewSize.height)
                    }
                    points = simplify(normalized)
                    liveStroke.removeAll()
                }
        )
    }

    private func clamp(_ p: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(x: max(0, min(size.width, p.x)),
                y: max(0, min(size.height, p.y)))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Cheap polyline simplification: drop intermediate points that are
    /// within ~0.5% of the line connecting their neighbours.
    private func simplify(_ pts: [CGPoint]) -> [CGPoint] {
        guard pts.count > 8 else { return pts }
        var out: [CGPoint] = [pts[0]]
        let tol: CGFloat = 0.005
        for i in 1..<(pts.count - 1) {
            let prev = out.last!
            let next = pts[i + 1]
            // Distance from pts[i] to segment prev→next.
            let d = perpendicularDistance(point: pts[i], lineStart: prev, lineEnd: next)
            if d > tol {
                out.append(pts[i])
            }
        }
        out.append(pts.last!)
        return out
    }

    private func perpendicularDistance(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let len = hypot(dx, dy)
        guard len > 0.0001 else { return hypot(point.x - lineStart.x, point.y - lineStart.y) }
        return abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x) / len
    }
}

// MARK: - UIImage helpers
// `normalizedOrientation()` lives in Extensions/UIImage+Orientation.swift

// MARK: - Lasso → cropped image

/// Builds a new UIImage that contains only the pixels inside the lasso
/// polygon, with the rest masked white (background that the detector
/// will treat as "no brick"). The returned image is also cropped to the
/// polygon's bounding box so the detector spends compute on the region.
enum PhotoLassoCrop {
    static func crop(image: UIImage, normalizedPolygon: [CGPoint]) -> UIImage? {
        guard normalizedPolygon.count >= 3 else { return nil }
        let pxSize = image.size
        let scale = image.scale

        // Convert normalized [0,1] points to pixel-space (origin top-left).
        let polyPx: [CGPoint] = normalizedPolygon.map {
            CGPoint(x: $0.x * pxSize.width, y: $0.y * pxSize.height)
        }
        let bbox = polyPx.reduce(CGRect.null) { acc, p in
            acc.union(CGRect(origin: p, size: .zero))
        }.insetBy(dx: -4, dy: -4)
                  .intersection(CGRect(origin: .zero, size: pxSize))

        guard bbox.width > 8, bbox.height > 8 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: bbox.size, format: format)
        return renderer.image { ctx in
            // White background.
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: bbox.size))

            // Clip to the polygon (translated into bbox-local coords).
            let path = UIBezierPath()
            let translated = polyPx.map {
                CGPoint(x: $0.x - bbox.minX, y: $0.y - bbox.minY)
            }
            path.move(to: translated[0])
            for p in translated.dropFirst() { path.addLine(to: p) }
            path.close()
            path.addClip()

            // Draw the source image, offset so the bbox region lands in [0,0].
            image.draw(at: CGPoint(x: -bbox.minX, y: -bbox.minY))
        }
    }
}
