import SwiftUI
import SceneKit

/// Interactive 3D viewer for LEGO brick models with rotate/zoom/pan controls.
/// Uses SceneKit for rendering with physically-based lighting.
struct ModelViewerView: View {
    let piece: LegoPiece
    var scanSession: ScanSession?
    @State private var showStuds = true
    @State private var showTubes = true
    @State private var isHollow = true
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var showShareSheet = false
    @State private var showPieceLocation = false
    @Environment(\.dismiss) private var dismiss

    private var hasLocation: Bool {
        piece.locationSnapshot != nil ||
        (piece.boundingBox != nil && piece.boundingBox != .zero && scanSession?.sourceImage(for: piece) != nil)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 3D Scene
                ZStack {
                    SceneView(
                        scene: makeScene(),
                        pointOfView: makeCameraNode(),
                        options: [.allowsCameraControl, .autoenablesDefaultLighting]
                    )
                    .accessibilityLabel("3D model of \(piece.name)")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))

                // Controls
                controlsPanel
            }
            .navigationTitle("3D Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if hasLocation {
                            Button {
                                showPieceLocation = true
                            } label: {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .accessibilityLabel("Show location of \(piece.name) in scan")
                        }
                        exportButton
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .fullScreenCover(isPresented: $showPieceLocation) {
                PieceLocationView(piece: piece, scanSession: scanSession)
            }
        }
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        let brickNode = BrickGeometryGenerator.generateBrick(
            for: piece, showStuds: showStuds, showTubes: showTubes, hollow: isHollow
        )

        let (minBB, maxBB) = brickNode.boundingBox
        let cx = (minBB.x + maxBB.x) / 2
        let cy = (minBB.y + maxBB.y) / 2
        let cz = (minBB.z + maxBB.z) / 2
        brickNode.position = SCNVector3(-cx, -cy, -cz)
        let height = maxBB.y - minBB.y
        scene.rootNode.addChildNode(brickNode)

        let floor = SCNFloor()
        floor.reflectivity = 0.05
        let floorMaterial = SCNMaterial()
        floorMaterial.diffuse.contents = UIColor.systemGray5
        floor.firstMaterial = floorMaterial
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, -height / 2 - 0.1, 0)
        scene.rootNode.addChildNode(floorNode)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        ambientLight.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambientLight)

        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.intensity = 800
        directionalLight.light?.castsShadow = true
        directionalLight.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(directionalLight)

        return scene
    }

    private func makeCameraNode() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 45
        camera.automaticallyAdjustsZRange = true

        // Use actual brick bounds for camera distance — works for both
        // LDraw meshes (mm scale) and procedural geometry (stud scale).
        let brickNode = BrickGeometryGenerator.generateBrick(
            for: piece, showStuds: showStuds, showTubes: showTubes, hollow: isHollow
        )
        let (minBB, maxBB) = brickNode.boundingBox
        let extentX = maxBB.x - minBB.x
        let extentY = maxBB.y - minBB.y
        let extentZ = maxBB.z - minBB.z
        let maxExtent = max(extentX, extentY, extentZ)
        let distance = max(maxExtent * 2.0, 30.0)

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(distance * 0.6, distance * 0.5, distance * 0.8)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        return cameraNode
    }

    // MARK: - Controls Panel

    private var controlsPanel: some View {
        VStack(spacing: 12) {
            // Piece info
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.legoColor(piece.color))
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(piece.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("\(piece.dimensions.displayString) · \(piece.color.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Estimated file size
                VStack(alignment: .trailing, spacing: 2) {
                    Text("STL Size")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(estimatedSize)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.legoBlue)
                }
            }

            Divider()

            // Toggle options
            HStack(spacing: 16) {
                Toggle("Studs", isOn: $showStuds)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Toggle("Tubes", isOn: $showTubes)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Toggle("Hollow", isOn: $isHollow)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Spacer()
            }
            .tint(.blue)

            // Print settings
            printSettingsRow

            // Export hint
            Label("Tap the share button above to export as STL for 3D printing", systemImage: "square.and.arrow.up")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .padding()
        .background(.regularMaterial)
    }

    private var printSettingsRow: some View {
        let settings = STLExporter.recommendedSettings(
            studsWide: piece.dimensions.studsWide,
            studsLong: piece.dimensions.studsLong,
            heightUnits: piece.dimensions.heightUnits
        )

        return VStack(alignment: .leading, spacing: 6) {
            Text("Print Settings")
                .font(.caption)
                .fontWeight(.semibold)

            HStack(spacing: 16) {
                settingBadge(icon: "square.3.layers.3d", label: settings.layerHeight)
                settingBadge(icon: "square.grid.3x3.fill", label: settings.infill)
                settingBadge(icon: "cube.transparent", label: settings.material)
                if settings.supports {
                    settingBadge(icon: "arrow.up.and.line.horizontal.and.arrow.down", label: "Supports")
                }
            }
        }
    }

    private func settingBadge(icon: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.1))
        .clipShape(Capsule())
        .foregroundStyle(.secondary)
    }

    // MARK: - Export

    private var exportButton: some View {
        Button {
            exportSTL()
        } label: {
            if isExporting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Export STL", systemImage: "square.and.arrow.up")
            }
        }
        .disabled(isExporting)
        .accessibilityLabel("Export as STL file for 3D printing")
    }

    private func exportSTL() {
        isExporting = true
        exportError = nil

        let currentPiece = piece
        let studs = showStuds
        let tubes = showTubes
        let hollow = isHollow

        Task.detached(priority: .userInitiated) {
            let node = BrickGeometryGenerator.generateBrick(
                for: currentPiece, showStuds: studs, showTubes: tubes, hollow: hollow
            )
            do {
                let url = try STLExporter.exportToSTL(
                    node: node,
                    fileName: "\(currentPiece.name)_\(currentPiece.color.rawValue)"
                )
                await MainActor.run {
                    exportURL = url
                    isExporting = false
                    showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }

    // MARK: - Scene Setup

    private var estimatedSize: String {
        let bytes = STLExporter.estimatedFileSize(
            studsWide: piece.dimensions.studsWide,
            studsLong: piece.dimensions.studsLong,
            heightUnits: piece.dimensions.heightUnits,
            hollow: isHollow
        )
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Build Model Viewer

/// 3D viewer for a complete build project showing all pieces laid out
struct BuildModelViewerView: View {
    let project: LegoProject
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SceneView(
                    scene: makeScene(),
                    pointOfView: makeCameraNode(),
                    options: [.allowsCameraControl, .autoenablesDefaultLighting]
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
                .accessibilityLabel("3D model of \(project.name) build with all required pieces")

                // Info bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("\(project.requiredPieces.reduce(0) { $0 + $1.quantity }) pieces")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        exportBuildSTL()
                    } label: {
                        if isExporting {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Export STL", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.legoBlue)
                    .disabled(isExporting)
                    .accessibilityLabel("Export all pieces as STL for 3D printing")
                }
                .padding()
                .background(.regularMaterial)
            }
            .navigationTitle("3D Build Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        let buildNode = BrickGeometryGenerator.generateBuildModel(for: project)
        scene.rootNode.addChildNode(buildNode)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        scene.rootNode.addChildNode(ambientLight)

        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.intensity = 800
        directionalLight.light?.castsShadow = true
        directionalLight.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(directionalLight)

        return scene
    }

    private func makeCameraNode() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 60
        camera.automaticallyAdjustsZRange = true

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(100, 80, 150)
        cameraNode.look(at: SCNVector3(50, 0, 50))

        return cameraNode
    }

    private func exportBuildSTL() {
        isExporting = true
        let node = BrickGeometryGenerator.generateBuildModel(for: project)

        Task {
            do {
                let url = try STLExporter.exportToSTL(
                    node: node,
                    fileName: project.name
                )
                await MainActor.run {
                    exportURL = url
                    isExporting = false
                    showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                }
            }
        }
    }
}
