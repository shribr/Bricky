import SceneKit
import simd

extension LDrawParser.Transform {
    /// LDU → mm (must match `LDrawGeometryBuilder.lduToMM`).
    fileprivate static let lduToMM: Float = 0.4

    /// Node transform to place a bundled part mesh at this LDraw transform.
    ///
    /// `LDrawLibrary` bakes each part's geometry into millimetres with the Y
    /// axis flipped (LDraw Y points down). So to position a whole part by its
    /// LDraw model transform `T`, we conjugate `T` by that same scale+flip
    /// `S = diag(0.4, -0.4, 0.4)`: `M = S · T · S⁻¹`. The `0.4`/`2.5` cancel, so
    /// `M` is a pure rotation (with the Y row/column sign-flipped) plus a
    /// scaled, Y-flipped translation.
    func meshSceneMatrix() -> simd_float4x4 {
        let s = Self.lduToMM
        // Columns are the images of the x / y / z basis vectors.
        let col0 = SIMD4<Float>( a, -d,  g, 0)
        let col1 = SIMD4<Float>(-b,  e, -h, 0)
        let col2 = SIMD4<Float>( c, -f,  i, 0)
        let col3 = SIMD4<Float>(x * s, -y * s, z * s, 1)
        return simd_float4x4(columns: (col0, col1, col2, col3))
    }
}

/// Builds a SceneKit scene from an imported LDraw model (`.ldr`/`.mpd`) using the
/// real bundled part *meshes* at their true transforms — for accurate rendering
/// of sophisticated models (e.g. OMR set models), grouped by build step.
enum LDrawMeshSceneBuilder {

    struct Result {
        let content: SCNNode
        /// Part nodes grouped by 0-based step index.
        let stepNodes: [[SCNNode]]
        let stepCount: Int
        /// Referenced parts not in the bundled library (skipped in the scene).
        let missingParts: [String]
    }

    static func build(fromModelText text: String, defaultColor: LegoColor = .gray) -> Result {
        let placements = LDrawModelParser.meshPlacements(text, defaultColor: defaultColor)
        let stepCount = placements.map(\.step).max() ?? 0

        let content = SCNNode()
        var groups: [[SCNNode]] = Array(repeating: [], count: max(1, stepCount))
        var missing: Set<String> = []

        for placement in placements {
            guard let node = LDrawLibrary.shared.node(forPartNumber: placement.partNumber, color: placement.color) else {
                missing.insert(placement.partNumber)
                continue
            }
            node.simdTransform = placement.transform.meshSceneMatrix()
            BrickStepStyler.addMeshOutline(to: node)
            content.addChildNode(node)
            let index = min(max(0, placement.step - 1), groups.count - 1)
            groups[index].append(node)
        }

        return Result(content: content, stepNodes: groups, stepCount: stepCount, missingParts: missing.sorted())
    }
}
