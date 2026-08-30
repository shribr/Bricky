import SceneKit
import UIKit
import ObjectiveC

/// Renders bricks with the "paper LEGO instructions" look and expresses build
/// order through outline + colour + ghosting:
///
/// * **Outline** — every brick keeps a thin edge-wireframe on its own edges, so
///   you can always read where one piece ends and the next begins. Because the
///   lines sit on the true edges (not an inflated shell), flush bricks' shared
///   edges coincide into a single crisp line instead of a doubled band.
/// * **Current step** — full vivid colour, opaque, self-lit, with a slightly
///   glowing edge so the pieces to add *now* pop.
/// * **Previous steps** — desaturated and *ghosted* (semi-transparent, tuned by
///   the viewer's slider) while their edges stay crisp and opaque for placement.
///
/// Original diffuse colours are captured per-material the first time a brick is
/// styled, so repeated step transitions re-derive from the true colour and never
/// drift.
enum BrickStepStyler {

    /// Name applied to every outline-shell node so styling can recolour them and
    /// skip them when desaturating the real brick body.
    static let outlineNodeName = "brick_outline_shell"

    /// Mesh outline shells scale up proportionally (arbitrary geometry).
    private static let outlineScale: Float = 1.02
    /// Box edge wireframes sit a hair proud of the body (mm) so the lines avoid
    /// z-fighting with the surfaces they trace, without visibly inflating.
    private static let edgeInflation: Float = 0.2
    private static let previousSaturation: CGFloat = 0.5
    private static let previousBrightness: CGFloat = 0.85

    enum Emphasis {
        /// Pieces added in the step currently being shown — pop with a highlight.
        case current
        /// Pieces added in an earlier step — recede via desaturation.
        case previous
    }

    // MARK: - Outline construction

    /// Add a thin edge-wireframe tracing the 12 edges of the brick's box. Lines
    /// live on the true edges (nudged a hair proud to avoid z-fighting), so
    /// flush bricks share a single crisp seam instead of two inflated shells.
    static func addBoxOutline(to brick: SCNNode, width: Float, height: Float, length: Float) {
        let m = edgeInflation
        let lo = SCNVector3(-m, -m, -m)
        let hi = SCNVector3(width + m, height + m, length + m)
        let c = [
            SCNVector3(lo.x, lo.y, lo.z), SCNVector3(hi.x, lo.y, lo.z),
            SCNVector3(hi.x, lo.y, hi.z), SCNVector3(lo.x, lo.y, hi.z),
            SCNVector3(lo.x, hi.y, lo.z), SCNVector3(hi.x, hi.y, lo.z),
            SCNVector3(hi.x, hi.y, hi.z), SCNVector3(lo.x, hi.y, hi.z),
        ]
        let indices: [Int32] = [
            0, 1, 1, 2, 2, 3, 3, 0, // bottom face
            4, 5, 5, 6, 6, 7, 7, 4, // top face
            0, 4, 1, 5, 2, 6, 3, 7, // vertical edges
        ]
        let source = SCNGeometrySource(vertices: c)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial = lineMaterial()
        let shell = SCNNode(geometry: geometry)
        shell.name = outlineNodeName
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

    /// Apply build-order emphasis to a whole placement subtree. `previousOpacity`
    /// (1 = opaque) lets the user see through already-built pieces.
    static func apply(_ emphasis: Emphasis, to root: SCNNode, previousOpacity: CGFloat = 1) {
        // LEGO-style contrast outline: light bricks get a black outline, dark
        // bricks get a white one (based on the brick's own luminance).
        let edge = edgeColor(for: representativeBodyColor(root))
        root.enumerateHierarchy { node, _ in
            if node.name == outlineNodeName {
                // Every shown step keeps its edges so piece boundaries always read;
                // the current step's edge glows slightly to stand out.
                if let geometry = node.geometry {
                    styleOutline(geometry, emphasis: emphasis, edge: edge)
                }
            } else if let geometry = node.geometry {
                styleBody(geometry, emphasis: emphasis, previousOpacity: previousOpacity)
            }
        }
    }

    private static func styleBody(_ geometry: SCNGeometry, emphasis: Emphasis, previousOpacity: CGFloat) {
        for material in geometry.materials {
            guard let base = baseColor(of: material) else { continue }
            switch emphasis {
            case .current:
                // Vivid, opaque, self-lit — the pieces to add *now*.
                material.diffuse.contents = base
                material.emission.contents = scaled(base, by: 0.12) // gentle self-glow
                material.transparency = 1
                material.blendMode = .alpha
                material.writesToDepthBuffer = true
            case .previous:
                // Desaturated + ghosted. Not writing depth lets the transparency
                // actually read against same-coloured bricks behind it.
                material.diffuse.contents = desaturated(base)
                material.emission.contents = UIColor.black
                material.transparency = previousOpacity
                material.blendMode = .alpha
                material.writesToDepthBuffer = previousOpacity >= 0.999
            }
        }
    }

    private static func styleOutline(_ geometry: SCNGeometry, emphasis: Emphasis, edge: UIColor) {
        for material in geometry.materials {
            material.diffuse.contents = edge
            // Current-step edges glow a touch so the active pieces read.
            material.emission.contents = emphasis == .current ? scaled(edge, by: 0.6) : UIColor.black
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

    /// Flat, depth-tested material for the edge-wireframe lines. Reads depth so
    /// hidden back edges are occluded, but doesn't write it to avoid fighting
    /// the body surfaces the lines trace.
    private static func lineMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.black
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
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
