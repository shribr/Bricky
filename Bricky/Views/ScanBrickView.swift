import SwiftUI

/// **Scan One Brick** — the accurate per-brick flow. The user centers a single
/// brick, captures, and the cloud recognizer returns ranked candidates to
/// confirm (with a color they pick) into a "Scanned Bricks" inventory.
struct ScanBrickView: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var viewModel = ScanBrickViewModel()
    @ObservedObject private var inventoryStore = InventoryStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var confirmedCount = 0

    private let contentMaxWidth: CGFloat = 480

    var body: some View {
        ZStack {
            switch viewModel.phase {
            case .results, .empty:
                resultsScreen
            case .identifying:
                loadingScreen
            case .cloudDisabled:
                messageScreen(
                    icon: "icloud.slash",
                    title: "Cloud Recognition Off",
                    message: "Turn on cloud recognition in Settings to identify a single brick accurately."
                )
            case .failed(let message):
                messageScreen(icon: "exclamationmark.triangle", title: "Couldn't Identify", message: message)
            case .idle:
                cameraScreen
            }
        }
        .navigationTitle("Scan One Brick")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { camera.checkPermissions() }
        .onDisappear { camera.stopSession() }
        .onChange(of: camera.capturedImage) { _, image in
            guard let image else { return }
            Task { await viewModel.identify(image: image) }
        }
    }

    // MARK: - Camera

    private var cameraScreen: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            VStack {
                Text("Center one brick in the frame")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.top, 12)

                Spacer()

                Button {
                    camera.capturePhoto()
                } label: {
                    ZStack {
                        Circle().fill(.white).frame(width: 74, height: 74)
                        Circle().strokeBorder(Color.legoBlue, lineWidth: 4).frame(width: 84, height: 84)
                    }
                }
                .accessibilityLabel("Capture brick photo")
                .padding(.bottom, 32)
            }
        }
    }

    private var loadingScreen: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Identifying brick…").foregroundStyle(.secondary)
        }
    }

    // MARK: - Results

    private var resultsScreen: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let image = viewModel.capturedImage {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if confirmedCount > 0 {
                    Text("\(confirmedCount) added to Scanned Bricks")
                        .font(.subheadline).foregroundStyle(Color.legoBlue)
                }

                if viewModel.phase == .empty {
                    Text("No brick recognized. Try again with the brick centered and good lighting.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    ForEach(Array(viewModel.candidates.enumerated()), id: \.offset) { _, candidate in
                        CandidateRow(candidate: candidate, defaultColor: viewModel.lastUsedColor) { color in
                            addToInventory(candidate, color: color)
                        }
                    }
                }

                Button("Scan Another") {
                    viewModel.reset()
                    camera.capturedImage = nil
                    camera.startSession()
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.legoBlue, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .padding()
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private func messageScreen(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: contentMaxWidth)
    }

    // MARK: - Actions

    private func addToInventory(_ candidate: BrickognizeService.MatchedPart, color: LegoColor) {
        let id = scannedBricksInventoryId()
        viewModel.confirm(candidate, color: color, into: id, store: inventoryStore)
        confirmedCount += 1
        HapticManager.notification(.success)
    }

    private func scannedBricksInventoryId() -> UUID {
        let name = "Scanned Bricks"
        if let existing = inventoryStore.inventories.first(where: { $0.name == name }) {
            return existing.id
        }
        return inventoryStore.createInventory(name: name)
    }
}

/// One ranked candidate with a color picker and a blue Add button.
private struct CandidateRow: View {
    let candidate: BrickognizeService.MatchedPart
    let onAdd: (LegoColor) -> Void

    @State private var color: LegoColor

    init(
        candidate: BrickognizeService.MatchedPart,
        defaultColor: LegoColor,
        onAdd: @escaping (LegoColor) -> Void
    ) {
        self.candidate = candidate
        self.onAdd = onAdd
        _color = State(initialValue: defaultColor)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.matchedName ?? candidate.prediction.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text("#\(candidate.matchedPartNumber ?? candidate.prediction.brickLinkID)")
                        .font(.caption).foregroundStyle(.secondary)
                    if !candidate.isCatalogMatch {
                        Text("Unmatched")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                    }
                }
            }

            Spacer(minLength: 8)

            Picker("Color", selection: $color) {
                ForEach(LegoColor.allCases, id: \.self) { c in
                    Text(c.rawValue.capitalized).tag(c)
                }
            }
            .labelsHidden()
            .frame(minWidth: 96)

            Button {
                onAdd(color)
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.legoBlue, in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("Add \(candidate.matchedName ?? candidate.prediction.name)")
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
