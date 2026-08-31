import SwiftUI
import UIKit

/// Shared result screen for both Set Forge flows. Shows a rotatable 3D preview
/// of the generated brick model, key stats, an optional "buildable with your
/// inventory" match, the full parts list, step-by-step instructions, and export
/// (LDraw) / share. The set is already saved to `GeneratedSetStore`.
struct GeneratedSetView: View {
    let set: GeneratedLegoSet

    @StateObject private var inventoryStore = InventoryStore.shared
    @State private var shareItem: ShareItem?
    @State private var showInstructions = false
    @State private var show3DInstructions = false
    @State private var show3DViewer = false
    @State private var previewImage: PreviewImage?
    @Environment(\.dismiss) private var dismiss

    private struct ShareItem: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    private struct PreviewImage: Identifiable {
        let id: Int
        let image: UIImage
    }

    /// Every original captured image for this set (1 photo, or the 4 angle
    /// photos / video-sweep frames used to build the model).
    private var sourceImages: [UIImage] {
        GeneratedSetStore.shared.sourceImages(for: set.id)
    }

    private var inventoryMatch: Double? {
        let owned = inventoryStore.activePiecesAsLegoPieces()
        guard !owned.isEmpty else { return nil }
        return set.asLegoProject().matchPercentage(with: owned)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                preview
                let images = sourceImages
                if !images.isEmpty {
                    scannedSource(images)
                }
                statsRow
                if let match = inventoryMatch {
                    inventoryChip(match)
                }
                actionButtons
                partsSection
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(set.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showInstructions) {
            InstructionStepsView(set: set)
        }
        .fullScreenCover(isPresented: $show3DInstructions) {
            BuildStepViewer(assembly: set.asAssemblyModel(), title: set.name)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .fullScreenCover(isPresented: $show3DViewer) {
            Model3DViewerView(bricks: set.bricks, title: set.name)
        }
        .fullScreenCover(item: $previewImage) { item in
            ImageViewerView(images: sourceImages, startIndex: item.id)
        }
    }

    // MARK: - Preview

    private var preview: some View {
        BrickModelSceneView(bricks: set.bricks)
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Color(.secondarySystemGroupedBackground), Color(.tertiarySystemGroupedBackground)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .topLeading) {
                Label(set.generator.label, systemImage: set.generator.systemImage)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                    .padding(8)
                    .accessibilityLabel("Model quality: \(set.generator.label)")
            }
            .overlay(alignment: .bottomTrailing) {
                Label("Drag to rotate · pinch to zoom", systemImage: "hand.draw")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    show3DViewer = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .padding(8)
                        .background(.thinMaterial, in: Circle())
                }
                .padding(8)
                .accessibilityLabel("View model full screen")
            }
    }

    /// The original captured image(s) this set was forged from, shown so the
    /// build can be compared against the real subject. Tap any to view full.
    private func scannedSource(_ images: [UIImage]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(images.count > 1 ? "Captured Angles (\(images.count))" : "Scanned Subject",
                  systemImage: "camera.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if images.count == 1 {
                Button {
                    previewImage = PreviewImage(id: 0, image: images[0])
                } label: {
                    Image(uiImage: images[0])
                        .resizable()
                        .scaledToFill()
                        .frame(height: 160)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            Button {
                                previewImage = PreviewImage(id: index, image: image)
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(value: "\(set.brickCount)", label: "Bricks", icon: "square.stack.3d.up.fill")
            statCard(value: "\(set.layerCount)", label: "Layers", icon: "square.3.layers.3d")
            statCard(value: set.difficulty.rawValue, label: "Difficulty", icon: "chart.bar.fill")
        }
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.legoBlue)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func inventoryChip(_ match: Double) -> some View {
        let percent = Int((match * 100).rounded())
        return HStack(spacing: 10) {
            Image(systemName: percent >= 100 ? "checkmark.seal.fill" : "tray.full.fill")
                .foregroundStyle(percent >= 100 ? .green : Color.legoOrange)
            Text(percent >= 100
                 ? "You have all the pieces to build this!"
                 : "You already own \(percent)% of the pieces")
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                show3DInstructions = true
            } label: {
                Label("View 3D Instructions", systemImage: "cube.transparent")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.legoBlue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button {
                showInstructions = true
            } label: {
                Label("Printable Step List", systemImage: "list.number")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
            }

            Button {
                exportLDraw()
            } label: {
                Label("Export & Share (LDraw)", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
            }

            Button {
                exportSTL()
            } label: {
                Label("Export for 3D Printing (STL)", systemImage: "cube.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
            }
        }
    }

    // MARK: - Parts

    private var partsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Parts List")
                .font(.headline)
            Text("\(set.parts.count) unique parts · \(set.brickCount) bricks total")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(set.parts) { part in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: part.color.hexColor))
                        .frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.black.opacity(0.15)))
                    Text(part.name)
                        .font(.subheadline)
                    Spacer()
                    Text("×\(part.quantity)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Export

    private func exportLDraw() {
        let dir = FileManager.default.temporaryDirectory
        let safeName = set.name.replacingOccurrences(of: "/", with: "-")
        let url = dir.appendingPathComponent("\(safeName).ldr")
        do {
            try set.ldrText.write(to: url, atomically: true, encoding: .utf8)
            shareItem = ShareItem(url: url)
        } catch {
            // Non-fatal; simply don't present the share sheet.
        }
    }

    private func exportSTL() {
        let dir = FileManager.default.temporaryDirectory
        let safeName = set.name.replacingOccurrences(of: "/", with: "-")
        let url = dir.appendingPathComponent("\(safeName).stl")
        do {
            try SetForgeSTLExporter.export(set.bricks).write(to: url, options: .atomic)
            shareItem = ShareItem(url: url)
        } catch {
            // Non-fatal; simply don't present the share sheet.
        }
    }
}

/// Step-by-step instructions for a generated set. Each step shows a real 3D
/// render of the model built up to that point, with the bricks added in this
/// step highlighted (earlier bricks ghosted) — like a printed LEGO manual.
private struct InstructionStepsView: View {
    let set: GeneratedLegoSet
    @Environment(\.dismiss) private var dismiss

    /// Bricks introduced at each step, index-aligned with `set.steps`.
    private var stepGroups: [[PlacedBrick]] { SetForgeInstructions.stepGroups(for: set.bricks) }

    /// Cumulative bricks through step `index` (all earlier groups + this one),
    /// ordered so the last `stepGroups[index].count` are the new bricks.
    private func cumulativeBricks(through index: Int) -> [PlacedBrick] {
        guard index < stepGroups.count else { return set.bricks }
        return stepGroups[0...index].flatMap { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(set.steps.enumerated()), id: \.element.id) { index, step in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Step \(step.stepNumber)")
                            .font(.headline)
                            .foregroundStyle(Color.legoBlue)

                        if index < stepGroups.count {
                            BrickModelSceneView(
                                bricks: cumulativeBricks(through: index),
                                highlightCount: stepGroups[index].count
                            )
                            .frame(height: 220)
                            .frame(maxWidth: .infinity)
                            .background(
                                LinearGradient(
                                    colors: [Color(.secondarySystemGroupedBackground), Color(.tertiarySystemGroupedBackground)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(alignment: .bottomTrailing) {
                                Text("Drag to rotate")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                                    .background(.thinMaterial, in: Capsule())
                                    .padding(8)
                            }
                        }

                        Text(step.instruction)
                            .font(.subheadline)
                        if !step.piecesUsed.isEmpty {
                            Text(step.piecesUsed)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let tip = step.tip {
                            Label(tip, systemImage: "lightbulb.fill")
                                .font(.caption)
                                .foregroundStyle(Color.legoOrange)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
