import SceneKit
import UIKit
import ObjectiveC

/// Renders bricks with the "paper LEGO instructions" look and expresses build
/// order through outline + colour + fade — all fully opaque, so every stud and
/// edge stays visible from every angle (no transparency sorting artifacts):
///
/// * **Outline** — every brick keeps a thin edge-wireframe on its own edges, so
///   you can always read where one piece ends and the next begins. Because the
///   lines sit on the true edges (not an inflated shell), flush bricks' shared
///   edges coincide into a single crisp line instead of a doubled band.
/// * **Current step** — full vivid colour, self-lit, with a slightly glowing
///   edge so the pieces to add *now* pop.
/// * **Previous steps** — desaturated and *faded toward pale* (amount tuned by
///   the viewer's slider) so already-built pieces recede while staying opaque
///   and fully detailed.
///
/// Original diffuse colours are captured per-material the first time a brick is
/// styled, so repeated step transitions re-derive from the true colour and never
/// drift.
enum BrickStepStyler {

    /// Name applied to every outline-shell node so styling can recolour them and
    /// skip them when desaturating the real brick body.
    static let outlineNodeName = "brick_outline_shell"

    /// Mesh part outlines come from the real LDraw type-2 edge lines rendered by
    /// `LDrawGeometryBuilder` (named `outlineNodeName`), so no synthetic shell is
    /// needed — matching how LDView/LPub3D/Stud.io draw part borders.
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

    // MARK: - Step emphasis

    /// Apply build-order emphasis to a whole placement subtree. `previousProminence`
    /// (1 = just desaturated, lower = more faded) tunes how far already-built
    /// pieces recede. Everything stays opaque so no detail is ever lost.
    static func apply(_ emphasis: Emphasis, to root: SCNNode, previousProminence: CGFloat = 1) {
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
                styleBody(geometry, emphasis: emphasis, prominence: previousProminence)
            }
        }
    }

    private static func styleBody(_ geometry: SCNGeometry, emphasis: Emphasis, prominence: CGFloat) {
        for material in geometry.materials {
            guard let base = baseColor(of: material) else { continue }
            switch emphasis {
            case .current:
                material.diffuse.contents = base
                material.emission.contents = scaled(base, by: 0.12) // gentle self-glow
            case .previous:
                // Opaque + faded (desaturated, washed toward pale). Never uses
                // alpha, so studs and edges never drop out at any angle.
                material.diffuse.contents = receded(base, fade: 1 - prominence)
                material.emission.contents = UIColor.black
            }
            material.transparency = 1
            material.blendMode = .replace
            material.writesToDepthBuffer = true
            material.readsFromDepthBuffer = true
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

    /// Desaturate then wash the colour toward a pale neutral by `fade` (0…0.85),
    /// giving already-built pieces an opaque "receded" look without transparency.
    private static func receded(_ color: UIColor, fade: CGFloat) -> UIColor {
        let f = max(0, min(0.75, fade))
        return blend(desaturated(color), toward: UIColor(white: 0.85, alpha: 1), fraction: f)
    }

    private static func blend(_ a: UIColor, toward b: UIColor, fraction: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        guard a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa),
              b.getRed(&br, green: &bg, blue: &bb, alpha: &ba) else { return a }
        return UIColor(red: ar + (br - ar) * fraction,
                       green: ag + (bg - ag) * fraction,
                       blue: ab + (bb - ab) * fraction,
                       alpha: aa)
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
