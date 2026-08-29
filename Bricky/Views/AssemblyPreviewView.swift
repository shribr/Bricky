import SwiftUI
import SceneKit

/// A lightweight 3D preview of a finished `AssemblyModel` — the whole model,
/// optionally auto-rotating in place. Used as the hero on a project's Overview.
struct AssemblyPreviewView: UIViewRepresentable {
    let assembly: AssemblyModel
    var autoRotate: Bool = true
    var allowsCameraControl: Bool = true

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = allowsCameraControl

        let scene = SCNScene()

        let content = AssemblySceneBuilder.contentNode(for: assembly)
        let (center, radius) = content.boundingSphere

        // Spin about the model centre rather than its corner.
        let spinner = SCNNode()
        spinner.position = center
        content.position = SCNVector3(-center.x, -center.y, -center.z)
        spinner.addChildNode(content)
        scene.rootNode.addChildNode(spinner)

        if autoRotate {
            spinner.runAction(.repeatForever(
                .rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 16)
            ))
        }

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 500
        scene.rootNode.addChildNode(ambient)

        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        cameraNode.camera = camera
        let r = max(radius, 20)
        cameraNode.position = SCNVector3(center.x, center.y + r * 0.6, center.z + r * 2.4)
        cameraNode.look(at: center)
        scene.rootNode.addChildNode(cameraNode)

        view.scene = scene
        view.pointOfView = cameraNode
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
