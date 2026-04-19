import SwiftUI
import SceneKit

/// Interactive 3D instruction viewer that shows step-by-step assembly.
/// Each step incrementally adds pieces to the SceneKit scene with fly-in animation.
struct BuildStepViewer: View {
    let project: LegoProject
    @State private var currentStep = 0
    @State private var scene = SCNScene()
    @State private var cameraNode = SCNNode()
    @State private var stepNodes: [[SCNNode]] = []
    @State private var isAnimating = false
    @Environment(\.dismiss) private var dismiss

    private var totalSteps: Int { project.instructions.count }
    private var isFirstStep: Bool { currentStep == 0 }
    private var isLastStep: Bool { currentStep >= totalSteps - 1 }
    private var currentInstruction: BuildStep? {
        guard currentStep < project.instructions.count else { return nil }
        return project.instructions[currentStep]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 3D Scene
                SceneView(
                    scene: scene,
                    pointOfView: cameraNode,
                    options: [.allowsCameraControl, .autoenablesDefaultLighting]
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
                .accessibilityLabel("3D assembly view showing step \(currentStep + 1) of \(totalSteps)")

                // Step info & controls
                stepControlPanel
            }
            .navigationTitle("3D Instructions")
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
            // Progress bar
            ProgressView(value: Double(currentStep + 1), total: Double(totalSteps))
                .tint(Color.legoBlue)
                .accessibilityLabel("Step \(currentStep + 1) of \(totalSteps)")

            // Step instruction
            if let instruction = currentInstruction {
                VStack(spacing: 4) {
                    Text("Step \(instruction.stepNumber) of \(totalSteps)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(instruction.instruction)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)

                    Label(instruction.piecesUsed, systemImage: "cube.fill")
                        .font(.caption)
                        .foregroundStyle(Color.legoBlue)

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

            // Navigation buttons
            HStack(spacing: 24) {
                Button {
                    goToFirstStep()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                }
                .disabled(isFirstStep || isAnimating)
                .accessibilityLabel("First step")

                Button {
                    previousStep()
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title)
                }
                .disabled(isFirstStep || isAnimating)
                .accessibilityLabel("Previous step")

                // Step counter
                Text("\(currentStep + 1) / \(totalSteps)")
                    .font(.headline)
                    .monospacedDigit()
                    .frame(minWidth: 60)

                Button {
                    nextStep()
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title)
                }
                .disabled(isLastStep || isAnimating)
                .accessibilityLabel("Next step")

                Button {
                    goToLastStep()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title3)
                }
                .disabled(isLastStep || isAnimating)
                .accessibilityLabel("Last step")
            }
            .foregroundStyle(Color.legoBlue)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Scene Setup

    private func setupScene() {
        scene.background.contents = UIColor.systemGroupedBackground

        // Camera
        let camera = SCNCamera()
        camera.fieldOfView = 45
        camera.automaticallyAdjustsZRange = true
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(60, 80, 120)
        cameraNode.look(at: SCNVector3(40, 10, 40))
        scene.rootNode.addChildNode(cameraNode)

        // Ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 400
        ambientLight.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambientLight)

        // Directional light
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.intensity = 800
        directionalLight.light?.castsShadow = true
        directionalLight.position = SCNVector3(50, 100, 50)
        directionalLight.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(directionalLight)

        // Floor grid
        let floor = SCNFloor()
        floor.reflectivity = 0.05
        floor.firstMaterial?.diffuse.contents = UIColor.systemGray5
        let floorNode = SCNNode(geometry: floor)
        scene.rootNode.addChildNode(floorNode)

        // Pre-generate nodes for all steps
        buildAllStepNodes()

        // Show first step
        showNodesUpToStep(0)
    }

    private func buildAllStepNodes() {
        stepNodes = []
        let piecesPerStep = distributePiecesAcrossSteps()

        var yStack: Float = 0

        for (stepIndex, pieces) in piecesPerStep.enumerated() {
            var nodesForStep: [SCNNode] = []
            var xOffset: Float = 0
            var maxLengthInRow: Float = 0
            let maxRowWidth: Float = 100.0

            for piece in pieces {
                let brickNode = BrickGeometryGenerator.generateBrick(
                    studsWide: piece.dimensions.studsWide,
                    studsLong: piece.dimensions.studsLong,
                    heightUnits: piece.dimensions.heightUnits,
                    color: piece.colorPreference ?? .gray,
                    showStuds: true,
                    showTubes: false,
                    hollow: false
                )

                let width = Float(piece.dimensions.studsWide) * BrickGeometryGenerator.studPitch
                let length = Float(piece.dimensions.studsLong) * BrickGeometryGenerator.studPitch

                if xOffset + width > maxRowWidth && xOffset > 0 {
                    xOffset = 0
                    maxLengthInRow = 0
                }

                let containerNode = SCNNode()
                containerNode.addChildNode(brickNode)
                containerNode.position = SCNVector3(xOffset, yStack, maxLengthInRow)
                containerNode.opacity = 0 // Start hidden

                scene.rootNode.addChildNode(containerNode)
                nodesForStep.append(containerNode)

                xOffset += width + 4.0
                maxLengthInRow = max(maxLengthInRow, length)
            }

            // Stack layers vertically
            let layerHeight = Float(pieces.first?.dimensions.heightUnits ?? 3) * BrickGeometryGenerator.plateHeight
            yStack += layerHeight

            stepNodes.append(nodesForStep)

            // Hide all except step 0 initially — handled in showNodesUpToStep
            _ = stepIndex
        }
    }

    /// Distribute requiredPieces across build steps proportionally
    private func distributePiecesAcrossSteps() -> [[RequiredPiece]] {
        // Expand to individual pieces
        var expanded: [RequiredPiece] = []
        for piece in project.requiredPieces {
            for _ in 0..<piece.quantity {
                expanded.append(RequiredPiece(
                    category: piece.category,
                    dimensions: piece.dimensions,
                    colorPreference: piece.colorPreference,
                    quantity: 1,
                    flexible: piece.flexible
                ))
            }
        }

        let stepCount = max(1, project.instructions.count)
        guard !expanded.isEmpty else { return Array(repeating: [], count: stepCount) }

        // Distribute evenly
        let piecesPerStep = expanded.count / stepCount
        let remainder = expanded.count % stepCount
        var result: [[RequiredPiece]] = []
        var idx = 0

        for step in 0..<stepCount {
            let count = piecesPerStep + (step < remainder ? 1 : 0)
            let end = min(idx + count, expanded.count)
            result.append(Array(expanded[idx..<end]))
            idx = end
        }

        // Pad if fewer pieces than steps
        while result.count < stepCount {
            result.append([])
        }

        return result
    }

    // MARK: - Navigation

    private func showNodesUpToStep(_ step: Int) {
        for (stepIndex, nodes) in stepNodes.enumerated() {
            for node in nodes {
                node.opacity = stepIndex <= step ? 1.0 : 0.0
            }
        }
    }

    private func animateStepIn(_ step: Int) {
        guard step < stepNodes.count else { return }
        isAnimating = true

        let nodes = stepNodes[step]
        for (index, node) in nodes.enumerated() {
            // Start above and fade in
            let targetPosition = node.position
            node.position = SCNVector3(targetPosition.x, targetPosition.y + 30, targetPosition.z)
            node.opacity = 0

            let delay = Double(index) * 0.1
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.4
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.4
                node.position = targetPosition
                node.opacity = 1.0
                SCNTransaction.commit()
            }

            SCNTransaction.commit()
        }

        // Re-enable after animation completes
        let totalDelay = Double(nodes.count) * 0.1 + 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
            isAnimating = false
        }
    }

    private func animateStepOut(_ step: Int) {
        guard step < stepNodes.count else { return }
        let nodes = stepNodes[step]
        for node in nodes {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.3
            node.opacity = 0
            SCNTransaction.commit()
        }
    }

    private func nextStep() {
        guard !isLastStep else { return }
        currentStep += 1
        animateStepIn(currentStep)
        HapticManager.impact(.light)
    }

    private func previousStep() {
        guard !isFirstStep else { return }
        animateStepOut(currentStep)
        currentStep -= 1
        HapticManager.impact(.light)
    }

    private func goToFirstStep() {
        currentStep = 0
        showNodesUpToStep(0)
        HapticManager.impact(.medium)
    }

    private func goToLastStep() {
        currentStep = totalSteps - 1
        showNodesUpToStep(currentStep)
        HapticManager.impact(.medium)
    }
}
