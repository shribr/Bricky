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
    private let sceneBuilder: () -> (content: SCNNode, stepNodes: [[SCNNode]], steps: [BuildStep], stepEntities: [Int])
    private let title: String

    @State private var currentStep = 0
    @State private var scene = SCNScene()
    @State private var cameraNode = SCNNode()
    @State private var contentNode = SCNNode()
    /// Container nodes grouped by 0-based step index.
    @State private var stepNodes: [[SCNNode]] = []
    @State private var steps: [BuildStep] = []
    /// Entity (connected-component) index for each 0-based step, so the camera
    /// can focus the entity being built and push the others to the background.
    @State private var stepEntities: [Int] = []
    /// Drives the interactive camera (fit / zoom / reset).
    @State private var sceneController = BuildSceneController()
    /// Flips true once the model is built, so the view fits on first layout.
    @State private var contentReady = false
    /// How see-through already-built pieces of the current entity are (0 = solid,
    /// higher = more transparent). Solid by default so nothing drops out unless
    /// the user opts in to x-ray the build.
    @State private var previousTransparency: Double = 0.0
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
    /// Build steps plus a final "completed model" page.
    private var pageCount: Int { steps.count + 1 }
    /// The extra page after the last build step showing the finished model.
    private var isCompletionPage: Bool { currentStep >= steps.count }
    private var isFirstStep: Bool { currentStep == 0 }
    private var isLastStep: Bool { currentStep >= steps.count }
    private var currentInstruction: BuildStep? {
        guard currentStep < steps.count else { return nil }
        return steps[currentStep]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                InstructionSceneView(
                    scene: scene,
                    pointOfView: cameraNode,
                    controller: sceneController,
                    contentReady: contentReady
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGray4))
                .overlay(alignment: .topTrailing) { cameraControls }
                .accessibilityLabel(isCompletionPage ? "3D view of the completed model" : "3D assembly view showing step \(currentStep + 1) of \(totalSteps)")

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
            .onChange(of: previousTransparency) { _, _ in
                showNodesUpToStep(currentStep)
            }
        }
    }

    // MARK: - Step Control Panel

    private var stepControlPanel: some View {
        VStack(spacing: 12) {
            ProgressView(value: Double(currentStep + 1), total: Double(pageCount))
                .tint(Color.legoBlue)
                .accessibilityLabel("Step \(currentStep + 1) of \(pageCount)")

            if isCompletionPage {
                completionSummary
            } else if let instruction = currentInstruction {
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

            if currentStep > 0 && !isCompletionPage {
                fadeSlider
            }
            if canReplay {
                replayButton
            }
            navigationButtons
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    /// Shown on the final page once every step is built.
    private var completionSummary: some View {
        VStack(spacing: 4) {
            Text("Complete")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label("Your model is fully assembled", systemImage: "checkmark.seal.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        }
    }

    /// See-through control for already-built pieces (0 = solid, right = x-ray the
    /// build to see the other side / internal structure).
    private var fadeSlider: some View {
        HStack(spacing: 10) {
            Image(systemName: "cube.transparent")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(value: $previousTransparency, in: 0.0...0.85)
                .tint(Color.legoBlue)
                .accessibilityLabel("See-through level for already-built pieces")
            Text("\(Int(previousTransparency * 100))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 4)
    }

    /// Replays the current step's fly-in — the digital "assembly arrow" for this
    /// page — so the user can watch the new pieces drop into place again. Only
    /// meaningful on a real build step that adds pieces.
    private var canReplay: Bool {
        !isCompletionPage
            && currentStep < stepNodes.count
            && !stepNodes[currentStep].isEmpty
    }

    private var replayButton: some View {
        Button { replayCurrentStep() } label: {
            Label("Replay step", systemImage: "arrow.clockwise")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(Color.legoBlue)
        .accessibilityLabel("Replay this step's animation")
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

            Text(isCompletionPage ? "Done" : "\(currentStep + 1) / \(totalSteps)")
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

    // MARK: - Camera Controls

    private var cameraControls: some View {
        VStack(spacing: 8) {
            cameraButton("plus.magnifyingglass", "Zoom in") { sceneController.zoom(0.8) }
            cameraButton("minus.magnifyingglass", "Zoom out") { sceneController.zoom(1.25) }
            cameraButton("viewfinder", "Fit to screen") { sceneController.fit() }
            cameraButton("arrow.counterclockwise", "Reset view") { sceneController.reset() }
        }
        .padding(10)
    }

    private func cameraButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            HapticManager.selection()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .foregroundStyle(Color.legoBlue)
        }
        .accessibilityLabel(label)
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

        // Wire the camera controller and fit on first layout.
        sceneController.contentNode = contentNode
        sceneController.homeTransform = cameraNode.simdTransform
        contentReady = true
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
        stepEntities = built.stepEntities
        scene.rootNode.addChildNode(contentNode)
    }

    /// Grid-assembly geometry (procedural boxes) — authored/procedural/mosaic.
    private static func buildFromAssembly(_ assembly: AssemblyModel) -> (content: SCNNode, stepNodes: [[SCNNode]], steps: [BuildStep], stepEntities: [Int]) {
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
        return (content, groups, steps, assembly.stepEntityIndices())
    }

    /// Imported LDraw model — real part meshes, with step text derived from the
    /// same model so counts stay aligned.
    private static func buildFromLDraw(_ text: String) -> (content: SCNNode, stepNodes: [[SCNNode]], steps: [BuildStep], stepEntities: [Int]) {
        let mesh = LDrawMeshSceneBuilder.build(fromModelText: text)
        let steps = BuildStepPlanner.steps(for: LDrawModelParser.parseAssembly(text))
        // Entity focus applies to the grid-assembly path; LDraw is one group.
        return (mesh.content, mesh.stepNodes, steps, Array(repeating: 0, count: max(1, mesh.stepNodes.count)))
    }

    private func frameCamera() {
        let (center, radius) = contentNode.boundingSphere
        let r = max(radius, 20)
        cameraNode.position = SCNVector3(center.x + r * 1.3, center.y + r * 1.1, center.z + r * 1.8)
        cameraNode.look(at: center)
    }

    // MARK: - Reveal

    private func showNodesUpToStep(_ step: Int) {
        // Completion page: reveal everything in full colour, framed to fit.
        if step >= steps.count {
            let all = stepNodes.flatMap { $0 }
            for node in all {
                node.isHidden = false
                BrickStepStyler.stopPulsing(node)
                BrickStepStyler.apply(.finished, to: node)
            }
            sceneController.allVisibleNodes = all
            sceneController.visibleNodes = all
            sceneController.frameCurrent()
            return
        }
        let currentEntity = step < stepEntities.count ? stepEntities[step] : 0
        for (index, nodes) in stepNodes.enumerated() {
            let entity = index < stepEntities.count ? stepEntities[index] : 0
            let emphasis: BrickStepStyler.Emphasis
            if index == step {
                emphasis = .current
            } else if entity == currentEntity {
                emphasis = .previous
            } else {
                emphasis = .background  // another entity — recede into the back
            }
            for node in nodes {
                if index > step {
                    node.isHidden = true
                    BrickStepStyler.stopPulsing(node)
                } else {
                    node.isHidden = false
                    BrickStepStyler.apply(
                        emphasis,
                        to: node,
                        previousProminence: CGFloat(1 - previousTransparency)
                    )
                    // Only the pieces added in *this* step pulse "add these now".
                    if index == step {
                        BrickStepStyler.startPulsing(node)
                    } else {
                        BrickStepStyler.stopPulsing(node)
                    }
                }
            }
        }
        // Recenter on the entity being built so it dominates the frame; if there's
        // only one entity this is just the whole built-so-far model.
        var focus: [SCNNode] = []
        for (index, nodes) in stepNodes.enumerated() where index <= step {
            let entity = index < stepEntities.count ? stepEntities[index] : 0
            if entity == currentEntity { focus.append(contentsOf: nodes) }
        }
        sceneController.allVisibleNodes = stepNodes.prefix(step + 1).flatMap { $0 }
        sceneController.visibleNodes = focus.isEmpty ? stepNodes.prefix(step + 1).flatMap { $0 } : focus
        sceneController.frameCurrent()
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
        currentStep = steps.count  // the completed-model page
        animateReveal()
        HapticManager.impact(.medium)
    }

    /// Re-run the current step's fly-in without changing the step, so the user
    /// can watch the "add these now" pieces drop into place again.
    private func replayCurrentStep() {
        guard canReplay else { return }
        animateReveal()
        HapticManager.impact(.light)
    }

    private func animateReveal() {
        // Fly the step's new pieces in from a short drop so it reads as "placed
        // here" — the digital stand-in for paper instructions' assembly arrows.
        let newNodes = currentStep < stepNodes.count ? stepNodes[currentStep] : []
        let drop: Float = 26
        for node in newNodes {
            node.isHidden = false
            node.position.y += drop
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.35
        showNodesUpToStep(currentStep)
        for node in newNodes { node.position.y -= drop }
        SCNTransaction.commit()
    }
}

// MARK: - Interactive Camera

/// Commands the SceneKit camera for the step viewer: fit / zoom / reset.
@MainActor
final class BuildSceneController {
    weak var scnView: SCNView?
    var contentNode: SCNNode?
    /// Every piece currently shown (all revealed steps) — framed by `fit()`.
    var allVisibleNodes: [SCNNode] = []
    /// The pieces of the entity being built — framed per step by `frameCurrent()`.
    var visibleNodes: [SCNNode] = []
    /// The initial framed camera transform, restored by `reset()`.
    var homeTransform: simd_float4x4?

    /// Frame every visible piece so the whole build (all entities) fits.
    func fit() {
        frame(allVisibleNodes.isEmpty ? [contentNode].compactMap { $0 } : allVisibleNodes, animated: true)
    }

    /// Recenter on the entity being built (falls back to everything visible).
    func frameCurrent(animated: Bool = true) {
        let fallback = allVisibleNodes.isEmpty ? [contentNode].compactMap { $0 } : allVisibleNodes
        frame(visibleNodes.isEmpty ? fallback : visibleNodes, animated: animated)
    }

    /// Position the camera to fit `nodes` from the current view direction, with a
    /// margin so wide/asymmetric layouts (e.g. desk + chair) aren't clipped.
    private func frame(_ nodes: [SCNNode], animated: Bool) {
        guard let pov = scnView?.pointOfView, !nodes.isEmpty,
              let bounds = worldBounds(of: nodes), bounds.radius > 0 else { return }
        let fov = Float((pov.camera?.fieldOfView ?? 45) * .pi / 180)
        let distance = bounds.radius / tan(fov / 2) * 1.25  // 1.25 = breathing room
        let newPosition = bounds.center - pov.simdWorldFront * distance
        let move = {
            pov.simdPosition = newPosition
            pov.look(at: SCNVector3(bounds.center))
        }
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.35
            move()
            SCNTransaction.commit()
        } else {
            move()
        }
    }

    /// Combined world-space bounds of the visible geometry under `nodes`
    /// (recurses children, since brick bodies live under container nodes).
    private func worldBounds(of nodes: [SCNNode]) -> (center: simd_float3, radius: Float)? {
        var minv = simd_float3(repeating: .greatestFiniteMagnitude)
        var maxv = simd_float3(repeating: -.greatestFiniteMagnitude)
        var found = false
        func accumulate(_ node: SCNNode) {
            if node.geometry != nil {
                let (bmin, bmax) = node.boundingBox
                if bmin.x != bmax.x || bmin.y != bmax.y || bmin.z != bmax.z {
                    for cx in [bmin.x, bmax.x] {
                        for cy in [bmin.y, bmax.y] {
                            for cz in [bmin.z, bmax.z] {
                                let w = node.convertPosition(SCNVector3(cx, cy, cz), to: nil)
                                let v = simd_float3(Float(w.x), Float(w.y), Float(w.z))
                                minv = simd_min(minv, v); maxv = simd_max(maxv, v); found = true
                            }
                        }
                    }
                }
            }
            for child in node.childNodes where !child.isHidden { accumulate(child) }
        }
        for node in nodes where !node.isHidden { accumulate(node) }
        guard found else { return nil }
        return ((minv + maxv) / 2, simd_length(maxv - minv) / 2)
    }

    /// Dolly the camera toward (`< 1`) or away from (`> 1`) the model centre.
    func zoom(_ factor: Float) {
        guard let pov = scnView?.pointOfView, let contentNode else { return }
        let center = contentNode.convertPosition(contentNode.boundingSphere.center, to: nil)
        let p = pov.position
        pov.position = SCNVector3(
            center.x + (p.x - center.x) * factor,
            center.y + (p.y - center.y) * factor,
            center.z + (p.z - center.z) * factor
        )
    }

    /// Restore the original framing and orientation.
    func reset() {
        guard let pov = scnView?.pointOfView, let homeTransform else { return }
        pov.simdTransform = homeTransform
        fit()
    }
}

/// A SceneKit view with orbit/pinch camera control plus a bridge to
/// `BuildSceneController`; fits the model to the view on first layout.
private struct InstructionSceneView: UIViewRepresentable {
    let scene: SCNScene
    let pointOfView: SCNNode
    let controller: BuildSceneController
    let contentReady: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.pointOfView = pointOfView
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling2X
        view.backgroundColor = .clear
        controller.scnView = view
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        controller.scnView = uiView
        if contentReady && !context.coordinator.didFit {
            context.coordinator.didFit = true
            DispatchQueue.main.async { controller.frameCurrent(animated: false) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator { var didFit = false }
}

