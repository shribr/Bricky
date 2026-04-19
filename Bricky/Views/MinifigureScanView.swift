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
                    MinifigureScanStatusView()
                    Text("Photo captured — you can put the camera down")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 32)
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
        .sheet(isPresented: $showResults, onDismiss: { resolvedCandidates = [] }) {
            resultsSheet
        }
        .alert("Saved",
               isPresented: Binding(
                get: { savedFigureName != nil },
                set: { if !$0 { savedFigureName = nil } }
               )
        ) {
            Button("Scan another") { savedFigureName = nil }
            Button("Done") { savedFigureName = nil; dismiss() }
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
            Button { dismiss() } label: {
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
        }
        .padding(.bottom, 30)
    }

    // MARK: - Identify

    @MainActor
    private func identify(image: UIImage) async {
        isIdentifying = true
        defer { isIdentifying = false }

        do {
            let resolved = try await MinifigureIdentificationService.shared
                .identify(torsoImage: image)
            resolvedCandidates = resolved
            showResults = true
        } catch {
            errorMessage = error.localizedDescription
        }
        camera.capturedImage = nil
    }

    // MARK: - Results sheet

    private var resultsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
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
                        showResults = false
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
                    Button("Close") { showResults = false; dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        // Confirmation + add-to-catalog sheets are attached HERE, on the
        // results sheet — not on the underlying scan view. iOS won't
        // present a sheet from a view that's already presenting one.
        .sheet(item: $pendingConfirmation) { candidate in
            if let fig = candidate.figure {
                MinifigureConfirmationSheet(
                    figure: fig,
                    candidate: candidate,
                    capturedImage: capturedImage,
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
                        // Close everything and ask the catalog to push the
                        // detail view for this figure.
                        showResults = false
                        dismiss()
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
                }
            )
        }
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

// MARK: - Cross-view navigation

extension Notification.Name {
    /// Posted when a scan flow finishes (confirm or add-to-catalog).
    /// Catalog view observes this and pushes the figure's detail view.
    /// `userInfo["minifigId"]` is the `Minifigure.id` to display.
    static let minifigureScanCompleted = Notification.Name("BrickVision.minifigureScanCompleted")
}
