import SwiftUI
import SceneKit

/// Interactive 3D instruction viewer. Renders the project's real
/// `AssemblyModel` placements at their true grid coordinates, revealing them
/// cumulatively per build step and highlighting the pieces added in the current
/// step. Step text comes from `BuildStepPlanner`, so the words always match what
/// is shown on screen.
struct BuildStepViewer: View {
    /// Builds the scene content, per-step node groups, and step text. Assigned by
    /// each initializer so grid assemblies and LDraw mesh models share the same
    /// reveal / camera / controls.
    private let sceneBuilder: () -> (content: SCNNode, stepNodes: [[SCNNode]], steps: [BuildStep])
    private let title: String

    @State private var currentStep = 0
    @State private var scene = SCNScene()
    @State private var cameraNode = SCNNode()
    @State private var contentNode = SCNNode()
    /// Container nodes grouped by 0-based step index.
    @State private var stepNodes: [[SCNNode]] = []
    @State private var steps: [BuildStep] = []
    @Environment(\.dismiss) private var dismiss

    init(project: LegoProject) {
        let assembly = project.resolvedAssembly
        self.sceneBuilder = { Self.buildFromAssembly(assembly) }
        self.title = "3D Instructions"
    }

    /// Drive the viewer directly from an assembly (mosaics, forged sets, etc.).
    init(assembly: AssemblyModel, title: String = "3D Instructions") {
        self.sceneBuilder = { Self.buildFromAssembly(assembly) }
        self.title = title
    }

    /// Drive the viewer from an imported LDraw model, rendering real part meshes.
    init(setModelText: String, title: String = "3D Instructions") {
        self.sceneBuilder = { Self.buildFromLDraw(setModelText) }
        self.title = title
    }

    private var totalSteps: Int { max(1, steps.count) }
    private var isFirstStep: Bool { currentStep == 0 }
    private var isLastStep: Bool { currentStep >= steps.count - 1 }
    private var currentInstruction: BuildStep? {
        guard currentStep < steps.count else { return nil }
        return steps[currentStep]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SceneView(
                    scene: scene,
                    pointOfView: cameraNode,
                    options: [.allowsCameraControl]
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGray4))
                .accessibilityLabel("3D assembly view showing step \(currentStep + 1) of \(totalSteps)")

                stepControlPanel
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { setupScene() }
        }
    }

    // MARK: - Step Control Panel

    private var stepControlPanel: some View {
        VStack(spacing: 12) {
            ProgressView(value: Double(currentStep + 1), total: Double(totalSteps))
                .tint(Color.legoBlue)
                .accessibilityLabel("Step \(currentStep + 1) of \(totalSteps)")

            if let instruction = currentInstruction {
                VStack(spacing: 4) {
                    Text("Step \(instruction.stepNumber) of \(totalSteps)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(instruction.instruction)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)

                    if !instruction.piecesUsed.isEmpty {
                        Label(instruction.piecesUsed, systemImage: "cube.fill")
                            .font(.caption)
                            .foregroundStyle(Color.legoBlue)
                            .multilineTextAlignment(.center)
                    }

                    if let tip = instruction.tip {
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption2)
                            Text(tip)
                                .font(.caption2)
                                .italic()
                        }
                        .foregroundStyle(Color.legoOrange)
                    }
                }
            }

            navigationButtons
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var navigationButtons: some View {
        HStack(spacing: 24) {
            Button { goToFirstStep() } label: {
                Image(systemName: "backward.end.fill").font(.title3)
            }
            .disabled(isFirstStep)
            .accessibilityLabel("First step")

            Button { previousStep() } label: {
                Image(systemName: "chevron.left.circle.fill").font(.title)
            }
            .disabled(isFirstStep)
            .accessibilityLabel("Previous step")

            Text("\(currentStep + 1) / \(totalSteps)")
                .font(.headline)
                .monospacedDigit()
                .frame(minWidth: 60)

            Button { nextStep() } label: {
                Image(systemName: "chevron.right.circle.fill").font(.title)
            }
            .disabled(isLastStep)
            .accessibilityLabel("Next step")

            Button { goToLastStep() } label: {
                Image(systemName: "forward.end.fill").font(.title3)
            }
            .disabled(isLastStep)
            .accessibilityLabel("Last step")
        }
        .foregroundStyle(Color.legoBlue)
    }

    // MARK: - Scene Setup

    private func setupScene() {
        // Neutral vertical gradient (lighter at top, darker toward the bottom) so
        // both light and dark bricks keep contrast against the backdrop.
        scene.background.contents = Self.backgroundGradientImage()

        let camera = SCNCamera()
        camera.fieldOfView = 45
        camera.automaticallyAdjustsZRange = true
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        addLighting()

        buildAssemblyNodes()
        frameCamera()
        showNodesUpToStep(0)
    }

    /// Ambient + key/fill/rim rig so light-coloured bricks show edges and shading
    /// rather than washing out flat.
    private func addLighting() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 350
        ambient.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 850
        key.light?.color = UIColor.white
        key.position = SCNVector3(120, 220, 140)
        key.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 300
        fill.light?.color = UIColor.white
        fill.position = SCNVector3(-160, 80, 120)
        fill.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(fill)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 450
        rim.light?.color = UIColor.white
        rim.position = SCNVector3(-40, 120, -200)
        rim.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(rim)
    }

    /// Vertical gradient backdrop rendered once as a bitmap.
    private static func backgroundGradientImage() -> UIImage {
        let size = CGSize(width: 8, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors = [UIColor.systemGray3.cgColor, UIColor.systemGray.cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
    }

    private func buildAssemblyNodes() {
        let built = sceneBuilder()
        contentNode = built.content
        stepNodes = built.stepNodes
        steps = built.steps
        scene.rootNode.addChildNode(contentNode)
    }

    /// Grid-assembly geometry (procedural boxes) — authored/procedural/mosaic.
    private static func buildFromAssembly(_ assembly: AssemblyModel) -> (content: SCNNode, stepNodes: [[SCNNode]], steps: [BuildStep]) {
        let steps = BuildStepPlanner.steps(for: assembly)
        let count = max(1, assembly.stepCount)
        var groups: [[SCNNode]] = Array(repeating: [], count: count)
        let content = SCNNode()
        for placement in assembly.placements {
            let node = AssemblySceneBuilder.brickNode(for: placement)
            content.addChildNode(node)
            let index = min(max(0, placement.step - 1), count - 1)
            groups[index].append(node)
        }
        return (content, groups, steps)
    }

    /// Imported LDraw model — real part meshes, with step text derived from the
    /// same model so counts stay aligned.
    private static func buildFromLDraw(_ text: String) -> (content: SCNNode, stepNodes: [[SCNNode]], steps: [BuildStep]) {
        let mesh = LDrawMeshSceneBuilder.build(fromModelText: text)
        let steps = BuildStepPlanner.steps(for: LDrawModelParser.parseAssembly(text))
        return (mesh.content, mesh.stepNodes, steps)
    }

    private func frameCamera() {
        let (center, radius) = contentNode.boundingSphere
        let r = max(radius, 20)
        cameraNode.position = SCNVector3(center.x + r * 1.3, center.y + r * 1.1, center.z + r * 1.8)
        cameraNode.look(at: center)
    }

    // MARK: - Reveal

    private func showNodesUpToStep(_ step: Int) {
        for (index, nodes) in stepNodes.enumerated() {
            for node in nodes {
                if index > step {
                    // Future pieces stay hidden.
                    node.isHidden = true
                } else {
                    // Every shown piece keeps its true colour and black outline;
                    // the current step pops (highlight outline + full colour) while
                    // earlier steps recede via desaturation — never transparency
                    // and never a forced grey.
                    node.isHidden = false
                    BrickStepStyler.apply(index == step ? .current : .previous, to: node)
                }
            }
        }
    }

    // MARK: - Navigation

    private func nextStep() {
        guard !isLastStep else { return }
        currentStep += 1
        animateReveal()
        HapticManager.impact(.light)
    }

    private func previousStep() {
        guard !isFirstStep else { return }
        currentStep -= 1
        animateReveal()
        HapticManager.impact(.light)
    }

    private func goToFirstStep() {
        currentStep = 0
        animateReveal()
        HapticManager.impact(.medium)
    }

    private func goToLastStep() {
        currentStep = max(0, steps.count - 1)
        animateReveal()
        HapticManager.impact(.medium)
    }

    private func animateReveal() {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.25
        showNodesUpToStep(currentStep)
        SCNTransaction.commit()
    }
}
