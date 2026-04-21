import SwiftUI
import UIKit

/// Full-screen camera view dedicated to identifying minifigures by torso scan.
/// The user frames the figure's torso inside a silhouette guide, taps the
/// shutter, and gets up to 3 ranked candidates from the cloud model.
struct MinifigureScanView: View {
    /// Image captured during pre-scan analysis — auto-starts identification.
    var preCapturedImage: UIImage? = nil

    @StateObject private var camera = CameraManager()
    @Environment(\.dismiss) private var dismiss

    @State private var isIdentifying = false
    @State private var resolvedCandidates: [MinifigureIdentificationService.ResolvedCandidate] = []
    @State private var showResults = false
    @State private var errorMessage: String?
    @State private var capturedImage: UIImage?
    @State private var pendingConfirmation: MinifigureIdentificationService.ResolvedCandidate?
    @State private var pendingAddToCatalog: MinifigureIdentificationService.ResolvedCandidate?
    @State private var savedFigureName: String?
    @State private var showCorrectionPicker = false
    @State private var autoEnhance: Bool = ScanImageEnhancer.isEnabled
    @State private var enhancingInProgress = false
    /// Briefly true after enhance completes — drives the
    /// "✓ Enhanced!" confirmation message before identification stages.
    @State private var enhanceJustCompleted = false
    /// True for the duration of identification once enhance succeeded —
    /// drives the persistent "✓ Auto-enhanced" badge so the user always
    /// has visual proof the step ran.
    @State private var enhanceWasApplied = false
    @State private var hybridAnalysis: HybridFigureAnalyzer.Analysis?
    @State private var showSubjectFullScreen = false

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            // Silhouette guide overlay (hidden during identification)
            if !isIdentifying {
                silhouetteOverlay
                    .allowsHitTesting(false)
            }

            VStack {
                topBar
                Spacer()
                if !isIdentifying {
                    bottomControls
                }
            }

            if isIdentifying {
                // Snapshot of the captured image replaces live camera
                if let snapshot = capturedImage {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                }
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 24) {
                    MinifigureScanStatusView(
                        overrideMessage: enhanceOverrideMessage
                    )
                }
                // Persistent badge in bottom-right so the user always has
                // visual confirmation the auto-enhance pipeline ran.
                // Bottom-right is used (rather than top-right) because
                // the captured-image backdrop sometimes pushes the
                // top-right placement outside the visible frame on the
                // direct-scan entry path.
                if enhanceWasApplied {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            enhancedBadge
                                .padding(.trailing, 16)
                                .padding(.bottom, 60)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .statusBarHidden()
        .onAppear {
            // If pre-scan captured an image, auto-start identification
            // immediately. Set isIdentifying BEFORE camera setup so the
            // silhouette never flashes on screen.
            if let preImage = preCapturedImage {
                capturedImage = preImage
                isIdentifying = true
                // Start camera in background for manual re-scan later
                if camera.isSessionRunning {
                    camera.startSession()
                } else {
                    camera.checkPermissions()
                }
                Task { await identify(image: preImage) }
            } else {
                // Normal entry: show camera + silhouette guide
                if camera.isSessionRunning {
                    camera.startSession()
                } else {
                    camera.checkPermissions()
                }
            }
        }
        .onDisappear {
            camera.stopSession()
        }
        .onReceive(camera.$error) { err in
            if let err {
                errorMessage = err.localizedDescription
            }
        }
        .onChange(of: camera.capturedImage) { _, newImage in
            guard let image = newImage else { return }
            capturedImage = image
            Task { await identify(image: image) }
        }
        .sheet(isPresented: $showResults, onDismiss: {
            resolvedCandidates = []
            hybridAnalysis = nil
        }) {
            resultsSheet
        }
        .alert("Saved",
               isPresented: Binding(
                get: { savedFigureName != nil },
                set: { if !$0 { savedFigureName = nil } }
               )
        ) {
            Button("Done") {
                savedFigureName = nil
                dismiss()
                NotificationCenter.default.post(name: .scanFlowShouldPopToRoot, object: nil)
            }
        } message: {
            Text("\(savedFigureName ?? "Minifigure") added to your collection.")
        }
        .alert("Identification failed",
               isPresented: Binding(
                   get: { errorMessage != nil },
                   set: { if !$0 { errorMessage = nil } }
               )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Overlay

    /// Status overlay's main message, derived from current pipeline phase.
    /// Returns nil to fall through to the cycling stage messages.
    private var enhanceOverrideMessage: String? {
        if enhancingInProgress {
            return "Enhancing image — auto-cropping & adjusting lighting…"
        }
        if enhanceJustCompleted {
            return "✓ Enhanced! Now identifying…"
        }
        return nil
    }

    /// Persistent confirmation badge shown in the bottom-right during
    /// the entire identification overlay once enhance has been applied.
    private var enhancedBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.green)
            Text("Auto-enhanced")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.black.opacity(0.65)))
        .overlay(Capsule().strokeBorder(.green.opacity(0.5), lineWidth: 1))
    }

    private var silhouetteOverlay: some View {
        GeometryReader { geo in
            let height = geo.size.height * 0.6
            let width = height * 0.55
            ZStack {
                // Dimmed surround
                Rectangle()
                    .fill(.black.opacity(0.5))
                    .ignoresSafeArea()
                    .mask(
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .frame(width: width, height: height)
                                    .blendMode(.destinationOut)
                            )
                            .compositingGroup()
                    )

                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2.5, dash: [10, 6]))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: width, height: height)

                // Hint
                VStack {
                    Spacer()
                        .frame(height: (geo.size.height - height) / 2 - 50)
                    Text("Center the minifigure torso")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .foregroundStyle(.white)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
                NotificationCenter.default.post(name: .scanFlowShouldPopToRoot, object: nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .padding(12)
                    .background(Circle().fill(.black.opacity(0.55)))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Cancel")

            Spacer()

            Text("Identify Minifigure")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.55)))
                .foregroundStyle(.white)

            Spacer()

            // Right-side filler so title stays centered
            Color.clear.frame(width: 44, height: 44)
        }
        .padding()
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            Button {
                camera.capturePhoto()
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 78, height: 78)
                    Circle()
                        .fill(.white)
                        .frame(width: 64, height: 64)
                    Image(systemName: "viewfinder")
                        .font(.title2)
                        .foregroundStyle(Color.legoBlue)
                }
            }
            .disabled(isIdentifying)
            .accessibilityLabel("Capture")

            Text("Tap to scan")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))

            Button {
                autoEnhance.toggle()
                ScanImageEnhancer.isEnabled = autoEnhance
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: autoEnhance ? "wand.and.stars" : "wand.and.stars.inverse")
                    Text(autoEnhance ? "Auto-enhance: On" : "Auto-enhance: Off")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.55)))
                .foregroundStyle(autoEnhance ? Color.yellow : .white.opacity(0.75))
            }
            .accessibilityLabel(autoEnhance ? "Auto-enhance on" : "Auto-enhance off")
        }
        .padding(.bottom, 30)
    }

    // MARK: - Identify

    @MainActor
    private func identify(image: UIImage) async {
        isIdentifying = true
        defer { isIdentifying = false }

        // Bake EXIF orientation into the bitmap so .cgImage downstream
        // (saliency, color extraction, feature prints) sees the image
        // in the correct orientation. Then, if the user has auto-enhance
        // enabled (default), run our auto-crop + CoreImage enhancement
        // pipeline OFF the main actor with a visible status message.
        var oriented = image.normalizedOrientation()
        if ScanImageEnhancer.isEnabled {
            enhancingInProgress = true
            // Run enhancement in parallel with a minimum-display timer so
            // the user can clearly see "Enhancing image…" — without this
            // the message flashes too fast to register on a fast pipeline.
            // 2.0s is comfortably long enough to read and process.
            // Snapshot `oriented` as an immutable `let` before the
            // `async let` capture — Swift 6 forbids captured-var
            // mutation across concurrently-executing tasks.
            let toEnhance = oriented
            async let enhanced = ScanImageEnhancer.enhanceAsync(toEnhance)
            async let minDelay: Void = Task.sleep(nanoseconds: 2_000_000_000)
            oriented = await enhanced
            _ = try? await minDelay
            // Update the snapshot the overlay shows BEFORE clearing the
            // status — that way the user sees the enhanced (cropped,
            // tone-corrected) image as the backdrop for the next phase.
            capturedImage = oriented
            enhancingInProgress = false
            // Show "✓ Enhanced!" confirmation for ~1.2s before
            // identification stages start cycling. This gives the user
            // an unmissable confirmation that the enhance step ran.
            enhanceJustCompleted = true
            enhanceWasApplied = true
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            enhanceJustCompleted = false
        } else if oriented !== image {
            capturedImage = oriented
        }

        // Run identification and a minimum-duration timer in parallel so
        // the user always sees the full 6-phase animation cycle (~9 s),
        // even when the on-device pipeline finishes in milliseconds.
        let started = Date()
        let minimumDuration: TimeInterval = 9.0

        do {
            // Snapshot the (possibly enhanced) image as a `let` for the
            // `async let` capture — Swift 6 forbids captured-var
            // mutation across concurrently-executing tasks.
            let identifyImage = oriented
            async let resolved = MinifigureIdentificationService.shared
                .identify(torsoImage: identifyImage)

            let result = try await resolved
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < minimumDuration {
                let remaining = UInt64((minimumDuration - elapsed) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: remaining)
            }
            resolvedCandidates = result

            // Run hybrid analysis using the top candidate as the anchor
            // and up to ~7 additional candidates as cross-attribution
            // sources (so we can say "torso looks like X but face looks
            // like Y" when parts come from different figures).
            let analyzerCandidates: [HybridFigureAnalyzer.Candidate] =
                result.prefix(8).compactMap { resolved in
                    guard let fig = resolved.figure else { return nil }
                    let refImage: UIImage? = {
                        if MinifigureCatalog.isUserFigureId(fig.id) {
                            return UserFigureImageStorage.shared.image(for: fig.id)
                        }
                        if let bundled = MinifigureReferenceImageStore.shared.image(for: fig.id) {
                            return bundled
                        }
                        if let url = fig.imageURL {
                            return MinifigureImageCache.shared.image(for: url)
                        }
                        return nil
                    }()
                    guard let refImage else { return nil }
                    return HybridFigureAnalyzer.Candidate(
                        figure: fig,
                        referenceImage: refImage
                    )
                }
            if !analyzerCandidates.isEmpty {
                // Low-confidence guard: when the top candidate's
                // confidence is below ~0.65 (≈ "weak visual match" or
                // worse), the result list is essentially noise — every
                // distance is in the same poor band. Running the
                // hybrid analyzer in that regime just produces
                // confidently-stated nonsense like "the hair piece
                // matches Catwoman" on a bald figure, because every
                // region's colors are equally close to every
                // candidate's. Skip the detailed analyzer in that
                // case but still provide a basic observation.
                let topConfidence = result.first?.confidence ?? 0
                let shouldAnalyzeHybrid = topConfidence >= 0.65
                if shouldAnalyzeHybrid {
                    let captured = oriented
                    // Prefer the embedding-enhanced async analysis when
                    // encoders are available; falls back to color-only
                    // internally when they aren't.
                    let analysis = await HybridFigureAnalyzer.analyzeWithEmbeddings(
                        captured: captured,
                        candidates: analyzerCandidates
                    )
                    hybridAnalysis = analysis
                } else if let topFig = analyzerCandidates.first?.figure {
                    // Low-confidence fallback — still show what the model observed.
                    hybridAnalysis = HybridFigureAnalyzer.Analysis(
                        isLikelyHybrid: false,
                        anchorFigure: topFig,
                        findings: [],
                        unexpectedYellowHands: false,
                        summary: "Low confidence match",
                        detail: "The closest match is \(topFig.name) (\(topFig.theme)), but the confidence is low. Try scanning with better lighting or a closer crop."
                    )
                } else {
                    hybridAnalysis = nil
                }
            } else {
                hybridAnalysis = nil
            }

            // Auto-save EVERY scan to history with the enhanced/cropped
            // subject image. Records the top candidate (or a placeholder
            // if no candidates returned). Confirm/reject flows below
            // will UPDATE this entry rather than create a new one.
            // Without this, scans the user closes without confirming or
            // rejecting are lost — and the user explicitly asked that
            // ALL scans be saved with delete-one and clear-all controls.
            let topCandidate = result.first
            MinifigureScanHistoryStore.shared.record(
                figure: topCandidate?.figure,
                candidateName: topCandidate?.modelName ?? "No match",
                confidence: topCandidate?.confidence ?? 0,
                reasoning: topCandidate?.reasoning ?? "",
                capturedImage: oriented,
                confirmed: false
            )

            showResults = true
        } catch {
            errorMessage = error.localizedDescription
        }
        camera.capturedImage = nil
        // Clear badge so it doesn't linger on a subsequent re-scan that
        // takes the manual (non-enhance) path.
        enhanceWasApplied = false
        enhanceJustCompleted = false
    }

    // MARK: - Results sheet

    private var resultsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let hybrid = hybridAnalysis {
                        analysisBanner(hybrid)
                    }

                    if resolvedCandidates.isEmpty {
                        ContentUnavailableView(
                            "No matches",
                            systemImage: "person.fill.questionmark",
                            description: Text("Try a clearer torso photo.")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(resolvedCandidates) { candidate in
                            candidateRow(candidate)
                        }
                    }

                    Button {
                        showCorrectionPicker = true
                    } label: {
                        Label("Not right? Help improve", systemImage: "sparkle.magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.15)))
                            .foregroundStyle(Color.blue)
                    }
                    .padding(.top, 10)

                    Button {
                        showCorrectionPicker = true
                    } label: {
                        Label("None of these", systemImage: "xmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
                    }
                    .padding(.top, 10)
                }
                .padding()
            }
            .navigationTitle("Top Matches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        showResults = false
                        dismiss()
                        NotificationCenter.default.post(name: .scanFlowShouldPopToRoot, object: nil)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .fullScreenCover(isPresented: $showSubjectFullScreen) {
            SubjectFullScreenView(image: capturedImage)
        }
        // Confirmation + add-to-catalog sheets are attached HERE, on the
        // results sheet — not on the underlying scan view. iOS won't
        // present a sheet from a view that's already presenting one.
        .sheet(item: $pendingConfirmation) { candidate in
            if let fig = candidate.figure {
                MinifigureConfirmationSheet(
                    figure: fig,
                    candidate: candidate,
                    capturedImage: capturedImage,
                    analysisDetail: hybridAnalysis,
                    onConfirm: {
                        MinifigureCollectionStore.shared.markScanned(fig.id)
                        MinifigureScanHistoryStore.shared.record(
                            figure: fig,
                            candidateName: candidate.modelName,
                            confidence: candidate.confidence,
                            reasoning: candidate.reasoning,
                            capturedImage: capturedImage,
                            confirmed: true
                        )
                        // Also feed the confirmation into the training
                        // store so the correction reranker can boost this
                        // figure on future similar scans. (Previously
                        // this only happened via "None of these" flow.)
                        if let capture = capturedImage {
                            MinifigureTrainingStore.shared.record(
                                capturedImage: capture,
                                confirmedFigIds: [fig.id],
                                rejectedFigIds: [],
                                aiCandidateName: candidate.modelName,
                                aiConfidence: candidate.confidence
                            )
                        }
                        // Close everything and ask the catalog to push the
                        // detail view for this figure.
                        showResults = false
                        dismiss()
                        NotificationCenter.default.post(name: .scanFlowShouldPopToRoot, object: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            NotificationCenter.default.post(
                                name: .minifigureScanCompleted,
                                object: nil,
                                userInfo: ["minifigId": fig.id]
                            )
                        }
                    },
                    onReject: {
                        MinifigureScanHistoryStore.shared.record(
                            figure: fig,
                            candidateName: candidate.modelName,
                            confidence: candidate.confidence,
                            reasoning: candidate.reasoning,
                            capturedImage: capturedImage,
                            confirmed: false
                        )
                    }
                )
            }
        }
        .sheet(item: $pendingAddToCatalog) { candidate in
            MinifigureAddToCatalogSheet(
                candidate: candidate,
                capturedImage: capturedImage,
                onSaved: { fig in
                    showResults = false
                    dismiss()
                    NotificationCenter.default.post(name: .scanFlowShouldPopToRoot, object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        NotificationCenter.default.post(
                            name: .minifigureScanCompleted,
                            object: nil,
                            userInfo: ["minifigId": fig.id]
                        )
                    }
                }
            )
        }
        .sheet(isPresented: $showCorrectionPicker) {
            MinifigureCorrectionPicker(
                capturedImage: capturedImage,
                aiCandidateName: resolvedCandidates.first?.modelName ?? "",
                aiConfidence: resolvedCandidates.first?.confidence ?? 0,
                rejectedFigIds: resolvedCandidates.compactMap { $0.figure?.id },
                onDone: {
                    showResults = false
                    dismiss()
                    NotificationCenter.default.post(name: .scanFlowShouldPopToRoot, object: nil)
                }
            )
        }
    }

    // MARK: - Analysis banner

    private func analysisBanner(_ analysis: HybridFigureAnalyzer.Analysis) -> some View {
        Button {
            showSubjectFullScreen = true
        } label: {
            HStack(spacing: 12) {
                if let img = capturedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 70, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        )
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(analysis.summary)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Text(analysis.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func candidateRow(_ candidate: MinifigureIdentificationService.ResolvedCandidate) -> some View {
        Group {
            if candidate.figure != nil {
                Button {
                    pendingConfirmation = candidate
                } label: {
                    candidateContent(fig: candidate.figure, candidate: candidate)
                }
                .buttonStyle(.plain)
            } else {
                candidateContent(fig: nil, candidate: candidate)
            }
        }
    }

    private func candidateContent(fig: Minifigure?, candidate: MinifigureIdentificationService.ResolvedCandidate) -> some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 12) {
                MinifigureImageView(url: fig?.imageURL)
                    .frame(width: 60, height: 70)

                VStack(alignment: .leading, spacing: 4) {
                    Text(fig?.name ?? candidate.modelName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if let fig {
                        Text("\(fig.theme)\(fig.year > 0 ? " · \(String(fig.year))" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not in local catalog")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text(candidate.reasoning)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        // Reserve space so the corner Add button doesn't overlap text.
                        .padding(.trailing, fig == nil ? 110 : 0)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("\(Int(candidate.confidence * 100))%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(confidenceColor(candidate.confidence))
                    Text("match")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if fig != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))

            if fig == nil {
                AddToCatalogCornerButton {
                    pendingAddToCatalog = candidate
                }
                .padding(10)
            }
        }
    }

    private func confidenceColor(_ c: Double) -> Color {
        if c >= 0.75 { return .green }
        if c >= 0.5 { return .orange }
        return .red
    }
}

// MARK: - Add-to-catalog corner button

/// Compact "Add to catalog" pill anchored to the corner of an
/// uncatalogued candidate tile. Theme-adaptive: a deeper LEGO-blue fill in
/// light mode, a brighter sky-blue in dark mode for contrast.
private struct AddToCatalogCornerButton: View {
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .font(.caption2)
                Text("Add to catalog")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(backgroundFill)
            )
            .foregroundStyle(foregroundColor)
            .overlay(
                Capsule()
                    .strokeBorder(foregroundColor.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to catalog")
    }

    private var backgroundFill: Color {
        colorScheme == .dark
            ? Color(red: 0.62, green: 0.78, blue: 1.0)   // light sky-blue for dark UI
            : Color.legoBlue                              // deep LEGO blue for light UI
    }

    private var foregroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
}

// MARK: - Subject full-screen viewer

struct SubjectFullScreenView: View {
    let image: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding()
            }
        }
    }
}

// MARK: - Cross-view navigation

extension Notification.Name {
    /// Posted when a scan flow finishes (confirm or add-to-catalog).
    /// Catalog view observes this and pushes the figure's detail view.
    /// `userInfo["minifigId"]` is the `Minifigure.id` to display.
    static let minifigureScanCompleted = Notification.Name("BrickVision.minifigureScanCompleted")

    /// Posted whenever a scan flow ends (confirm, cancel, or close)
    /// and the user should be returned to the root home screen.
    /// ContentView's NavigationStack observes this and resets its path.
    static let scanFlowShouldPopToRoot = Notification.Name("BrickVision.scanFlowShouldPopToRoot")
}
