import SceneKit

/// Shared SceneKit node construction for an `AssemblyModel`, used by both the
/// step-by-step viewer and the overview 3D preview so the brick placement math
/// lives in one place.
enum AssemblySceneBuilder {
    static let pitch = BrickGeometryGenerator.studPitch
    static let plate = BrickGeometryGenerator.plateHeight

    /// A positioned container for one placement. The brick is centered in X/Z
    /// (bottom at y=0) so rotating the container about Y spins it about the
    /// footprint centre; the container sits at the footprint's grid position.
    static func brickNode(for placement: BrickPlacement) -> SCNNode {
        let brick = BrickGeometryGenerator.generateBrick(
            studsWide: placement.dimensions.studsWide,
            studsLong: placement.dimensions.studsLong,
            heightUnits: placement.dimensions.heightUnits,
            color: placement.color,
            showStuds: true,
            showTubes: false,
            hollow: false
        )
        let w = Float(placement.dimensions.studsWide) * pitch
        let l = Float(placement.dimensions.studsLong) * pitch
        brick.position = SCNVector3(-w / 2, 0, -l / 2)

        let container = SCNNode()
        container.addChildNode(brick)

        let rotated = placement.rotationDegrees == 90 || placement.rotationDegrees == 270
        let footprintW = Float(rotated ? placement.dimensions.studsLong : placement.dimensions.studsWide)
        let footprintL = Float(rotated ? placement.dimensions.studsWide : placement.dimensions.studsLong)
        container.position = SCNVector3(
            (Float(placement.position.x) + footprintW / 2) * pitch,
            Float(placement.position.y) * plate,
            (Float(placement.position.z) + footprintL / 2) * pitch
        )
        container.eulerAngles.y = Float(placement.rotationDegrees) * .pi / 180
        return container
    }

    /// A node containing every placement in the model.
    static func contentNode(for model: AssemblyModel) -> SCNNode {
        let node = SCNNode()
        for placement in model.placements {
            node.addChildNode(brickNode(for: placement))
        }
        return node
    }
}
