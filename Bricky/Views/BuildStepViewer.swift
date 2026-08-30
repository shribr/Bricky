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
                    options: [.allowsCameraControl, .autoenablesDefaultLighting]
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
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
        scene.background.contents = UIColor.systemGroupedBackground

        let camera = SCNCamera()
        camera.fieldOfView = 45
        camera.automaticallyAdjustsZRange = true
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        ambientLight.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambientLight)

        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.intensity = 700
        directionalLight.position = SCNVector3(100, 200, 100)
        directionalLight.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(directionalLight)

        buildAssemblyNodes()
        frameCamera()
        showNodesUpToStep(0)
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
            // Already-built pieces recede (lighter/translucent); the current
            // step's new pieces show in full colour so they stand out; future
            // pieces are hidden.
            let opacity: CGFloat
            if index > step { opacity = 0 }
            else if index == step { opacity = 1 }
            else { opacity = 0.6 }
            for node in nodes { node.opacity = opacity }
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
