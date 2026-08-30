import SceneKit
import UIKit
import ObjectiveC

/// Renders bricks with the "paper LEGO instructions" look and expresses build
/// order without transparency or gray-recolouring:
///
/// * **Outline** — every brick gets a black inverted-hull shell (a slightly
///   enlarged duplicate rendered with front-face culling), so its silhouette
///   reads clearly against any background.
/// * **Current step** — full colour, plus a bright highlight-coloured outline
///   and a soft emissive rim so the pieces to add *now* pop.
/// * **Previous steps** — kept fully opaque and true-hued but *desaturated*
///   (~50% saturation, ~15% dimmer) so already-built pieces recede. A brick that
///   is genuinely grey merely looks a touch muted, never "highlighted".
///
/// Original diffuse colours are captured per-material the first time a brick is
/// styled, so repeated step transitions re-derive from the true colour and never
/// drift.
enum BrickStepStyler {

    /// Name applied to every outline-shell node so styling can recolour them and
    /// skip them when desaturating the real brick body.
    static let outlineNodeName = "brick_outline_shell"

    private static let outlineScale: Float = 1.035
    private static let outlineScaleCurrent: Float = 1.06
    private static let previousSaturation: CGFloat = 0.5
    private static let previousBrightness: CGFloat = 0.85

    enum Emphasis {
        /// Pieces added in the step currently being shown — pop with a highlight.
        case current
        /// Pieces added in an earlier step — recede via desaturation.
        case previous
    }

    // MARK: - Outline construction

    /// Add a single box-shaped black outline shell sized to a procedural brick's
    /// solid body. One extra box per brick keeps large models performant.
    static func addBoxOutline(to brick: SCNNode, width: Float, height: Float, length: Float) {
        let box = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length), chamferRadius: 0.2)
        box.firstMaterial = shellMaterial()
        let shell = SCNNode(geometry: box)
        shell.name = outlineNodeName
        // Match `generateSolidBody`'s body placement, then grow about its centre.
        shell.position = SCNVector3(width / 2, height / 2, length / 2)
        shell.scale = SCNVector3(outlineScale, outlineScale, outlineScale)
        brick.addChildNode(shell)
    }

    /// Add a black outline shell that mirrors an arbitrary mesh subtree (used for
    /// real LDraw part meshes). Geometry is deep-copied so recolouring the shell
    /// never mutates the shared source mesh.
    static func addMeshOutline(to node: SCNNode) {
        // The shell is a child of `node`, so the parent already applies `node`'s
        // transform — the top shell must stay at identity; only descendants keep
        // their local transforms.
        let shell = mirrorForOutline(node)
        shell.transform = SCNMatrix4Identity
        shell.scale = SCNVector3(outlineScale, outlineScale, outlineScale)
        node.addChildNode(shell)
    }

    private static func mirrorForOutline(_ node: SCNNode) -> SCNNode {
        let shell = SCNNode()
        shell.name = outlineNodeName
        shell.transform = node.transform
        if let copied = node.geometry?.copy() as? SCNGeometry {
            copied.materials = copied.materials.map { _ in shellMaterial() }
            shell.geometry = copied
        }
        for child in node.childNodes where child.name != outlineNodeName {
            shell.addChildNode(mirrorForOutline(child))
        }
        return shell
    }

    // MARK: - Step emphasis

    /// Apply build-order emphasis to a whole placement subtree.
    static func apply(_ emphasis: Emphasis, to root: SCNNode) {
        // LEGO-style contrast outline: light bricks get a black outline, dark
        // bricks get a white one (based on the brick's own luminance).
        let edge = edgeColor(for: representativeBodyColor(root))
        root.enumerateHierarchy { node, _ in
            if node.name == outlineNodeName {
                // Bolder edge on the active pieces — a colour-agnostic "add now"
                // cue that works even for black/white/grey bricks.
                let scale = emphasis == .current ? outlineScaleCurrent : outlineScale
                node.scale = SCNVector3(scale, scale, scale)
                if let geometry = node.geometry {
                    styleOutline(geometry, emphasis: emphasis, edge: edge)
                }
            } else if let geometry = node.geometry {
                styleBody(geometry, emphasis: emphasis)
            }
        }
    }

    private static func styleBody(_ geometry: SCNGeometry, emphasis: Emphasis) {
        for material in geometry.materials {
            guard let base = baseColor(of: material) else { continue }
            switch emphasis {
            case .current:
                material.diffuse.contents = base
                material.emission.contents = scaled(base, by: 0.12) // gentle self-glow
            case .previous:
                material.diffuse.contents = desaturated(base)
                material.emission.contents = UIColor.black
            }
        }
    }

    private static func styleOutline(_ geometry: SCNGeometry, emphasis: Emphasis, edge: UIColor) {
        for material in geometry.materials {
            material.diffuse.contents = edge
            // A slight glow makes the (already bolder) current-step edge read.
            material.emission.contents = emphasis == .current ? scaled(edge, by: 0.5) : UIColor.black
        }
    }

    // MARK: - Helpers

    /// The brick's true body colour (first non-outline material), for choosing
    /// the contrasting outline.
    private static func representativeBodyColor(_ root: SCNNode) -> UIColor {
        var found: UIColor?
        root.enumerateHierarchy { node, stop in
            guard node.name != outlineNodeName,
                  let material = node.geometry?.materials.first,
                  let color = baseColor(of: material) else { return }
            found = color
            stop.pointee = true
        }
        return found ?? .gray
    }

    /// Black outline for light bricks, white outline for dark bricks — the
    /// high-contrast scheme LEGO uses in printed instructions.
    private static func edgeColor(for color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return UIColor(white: 0.08, alpha: 1)
        }
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.55
            ? UIColor(white: 0.08, alpha: 1)   // light brick → black outline
            : UIColor(white: 0.96, alpha: 1)    // dark brick → white outline
    }

    private static func scaled(_ color: UIColor, by factor: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return .black }
        return UIColor(hue: h, saturation: s, brightness: b * factor, alpha: a)
    }

    private static func shellMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.black
        material.cullMode = .front           // render only the shell's inside faces
        material.isDoubleSided = false
        material.writesToDepthBuffer = true
        material.readsFromDepthBuffer = true
        return material
    }

    private static func desaturated(_ color: UIColor) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return color }
        return UIColor(hue: h, saturation: s * previousSaturation, brightness: b * previousBrightness, alpha: a)
    }

    private nonisolated(unsafe) static var baseColorAssocKey: UInt8 = 0

    /// Original diffuse colour for a body material, captured (once) on first use
    /// so desaturation always derives from the true hue.
    private static func baseColor(of material: SCNMaterial) -> UIColor? {
        if let stored = objc_getAssociatedObject(material, &baseColorAssocKey) as? UIColor {
            return stored
        }
        guard let current = material.diffuse.contents as? UIColor else { return nil }
        objc_setAssociatedObject(material, &baseColorAssocKey, current, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return current
    }
}
