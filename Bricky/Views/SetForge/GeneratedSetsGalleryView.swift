import SwiftUI

/// History of the user's Set Forge creations. Each row shows the original
/// scanned/photographed image (when the set came from a photo or scan) next to
/// the generated build, the model-quality badge, and key stats. Tapping opens
/// the full result screen; swipe to delete. Offline; all data is on-device.
struct GeneratedSetsGalleryView: View {
    @StateObject private var store = GeneratedSetStore.shared
    /// Set whose interactive 3D instructions are being presented.
    @State private var instructionsSet: GeneratedLegoSet?

    var body: some View {
        Group {
            if store.sets.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(store.sets) { set in
                        NavigationLink {
                            GeneratedSetView(set: set)
                        } label: {
                            row(for: set)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                instructionsSet = set
                            } label: {
                                Label("3D Steps", systemImage: "cube.transparent")
                            }
                            .tint(Color.legoBlue)
                        }
                        .contextMenu {
                            Button {
                                instructionsSet = set
                            } label: {
                                Label("View 3D Instructions", systemImage: "cube.transparent")
                            }
                        }
                    }
                    .onDelete { store.delete(at: $0) }
                }
            }
        }
        .navigationTitle("My Forged Sets")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $instructionsSet) { set in
            BuildStepViewer(assembly: set.asAssemblyModel(), title: set.name)
        }
    }

    // MARK: - Row

    private func row(for set: GeneratedLegoSet) -> some View {
        HStack(spacing: 12) {
            thumbnails(for: set)
            VStack(alignment: .leading, spacing: 4) {
                Text(set.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(set.generator.label, systemImage: set.generator.systemImage)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(.tertiarySystemFill)))
                    Text(set.sizeLabel.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("\(set.brickCount) bricks · \(set.difficulty.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(set.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// The original scanned image (if any) beside a small render of the build.
    @ViewBuilder
    private func thumbnails(for set: GeneratedLegoSet) -> some View {
        HStack(spacing: 4) {
            if let source = store.sourceImage(for: set.id) {
                Image(uiImage: source)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            BrickModelSceneView(bricks: set.bricks, interactive: false)
                .frame(width: 52, height: 52)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "No Forged Sets Yet",
            systemImage: "cube.transparent",
            description: Text("Sets you create with Set Forge — from a photo, a 3D scan, or a description — are saved here.")
        )
    }
}
