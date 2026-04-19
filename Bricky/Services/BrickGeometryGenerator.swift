import SceneKit
import SwiftUI
import Foundation

/// Generates accurate 3D geometry for LEGO bricks using SceneKit.
/// Dimensions follow real LEGO specifications:
/// - 1 stud = 8mm wide
/// - 1 plate height = 3.2mm
/// - 1 brick height = 9.6mm (3 plates)
/// - Stud diameter = 4.8mm, stud height = 1.7mm
/// - Tube inner diameter (underside) = 3.2mm
final class BrickGeometryGenerator {

    // MARK: - Constants (in millimeters, converted to scene units at 1:1 mm)

    /// Width/length of one stud unit
    static let studPitch: Float = 8.0
    /// Height of one plate (1 height unit)
    static let plateHeight: Float = 3.2
    /// Brick height (3 height units) = 9.6mm
    static let brickHeight: Float = 9.6
    /// Stud cylinder diameter
    static let studDiameter: Float = 4.8
    /// Stud cylinder height protruding above the brick
    static let studHeight: Float = 1.7
    /// Wall thickness of the brick shell
    static let wallThickness: Float = 1.5
    /// Tube outer diameter (underside structural tubes)
    static let tubeOuterDiameter: Float = 6.51
    /// Tube inner diameter (underside)
    static let tubeInnerDiameter: Float = 4.8

    // MARK: - Public API

    /// Generate a complete SCNNode for a LEGO piece
    /// - Parameters:
    ///   - piece: The LEGO piece to generate geometry for
    ///   - showStuds: Whether to add stud cylinders on top
    ///   - showTubes: Whether to add underside structural tubes
    ///   - hollow: Whether the body is hollow (shell) or solid
    /// - Returns: An SCNNode containing the brick geometry
    static func generateBrick(
        for piece: LegoPiece,
        showStuds: Bool = true,
        showTubes: Bool = true,
        hollow: Bool = true
    ) -> SCNNode {
        // Prefer real LDraw geometry when available — accurate per-part meshes
        // built by the LDraw community. Falls back to procedural geometry
        // when the library is missing or the part isn't bundled.
        if let ldraw = LDrawLibrary.shared.node(forPartNumber: piece.partNumber, color: piece.color) {
            ldraw.name = "ldraw_\(piece.partNumber)"
            return ldraw
        }

        // Resolve effective category: use the stored category, but fall back to
        // name-based inference when the pipeline assigned a generic category
        let effectiveCategory = resolveCategory(for: piece)

        // Use category-specific generators for non-rectangular pieces
        switch effectiveCategory {
        case .technic:
            return generateTechnicPiece(for: piece, showStuds: showStuds, hollow: hollow)
        case .round:
            return generateRoundPiece(for: piece, showStuds: showStuds, hollow: hollow)
        case .slope:
            return generateSlopePiece(for: piece, showStuds: showStuds, hollow: hollow)
        case .arch:
            return generateArchPiece(for: piece, showStuds: showStuds, hollow: hollow)
        case .wheel:
            return generateWheelPiece(for: piece)
        case .tile:
            return generateTilePiece(for: piece, hollow: hollow)
        case .wedge:
            return generateWedgePiece(for: piece, showStuds: showStuds, hollow: hollow)
        case .minifigure:
            return generateMinifigurePiece(for: piece)
        case .connector, .hinge, .bracket:
            return generateConnectorPiece(for: piece)
        case .specialty:
            return generateSpecialtyPiece(for: piece, showStuds: showStuds, hollow: hollow)
        case .window:
            return generateWindowPiece(for: piece, showStuds: showStuds)
        default:
            return generateBrick(
                studsWide: piece.dimensions.studsWide,
                studsLong: piece.dimensions.studsLong,
                heightUnits: piece.dimensions.heightUnits,
                color: piece.color,
                showStuds: showStuds,
                showTubes: showTubes,
                hollow: hollow
            )
        }
    }

    /// Infer the effective category from the piece name when the stored category
    /// is generic (.brick, .plate, .other). This fixes old scans where the
    /// pipeline could not classify non-rectangular pieces.
    private static func resolveCategory(for piece: LegoPiece) -> PieceCategory {
        // If the stored category is already specific, trust it
        switch piece.category {
        case .technic, .round, .slope, .arch, .wheel, .tile, .wedge,
             .minifigure, .connector, .hinge, .bracket, .window, .specialty:
            return piece.category
        default:
            break // .brick, .plate, .other — try name inference
        }

        let name = piece.name.lowercased()

        // Technic family
        if name.contains("gear") || name.contains("technic") || name.contains("beam") ||
           name.contains("liftarm") || name.contains("axle") || name.contains("pin") {
            return .technic
        }
        // Wheels and tires
        if name.contains("wheel") || name.contains("tire") || name.contains("tyre") {
            return .wheel
        }
        // Round pieces
        if name.contains("round") || name.contains("cone") || name.contains("dome") ||
           name.contains("hemisphere") || name.contains("cylinder") || name.contains("dish") {
            return .round
        }
        // Slopes
        if name.contains("slope") {
            return .slope
        }
        // Arches
        if name.contains("arch") {
            return .arch
        }
        // Tiles
        if name.contains("tile") {
            return .tile
        }
        // Wedges
        if name.contains("wedge") {
            return .wedge
        }
        // Minifigures
        if name.contains("minifig") || name.contains("torso") || name.contains("legs") {
            return .minifigure
        }
        // Connectors / hinges / brackets
        if name.contains("hinge") { return .hinge }
        if name.contains("bracket") { return .bracket }
        if name.contains("connector") || name.contains("joint") { return .connector }
        // Specialty — plants, flowers, flags, panels, wings, antennas
        if name.contains("plant") || name.contains("leaf") || name.contains("leaves") ||
           name.contains("flower") || name.contains("tree") || name.contains("stem") ||
           name.contains("flag") || name.contains("banner") || name.contains("wing") ||
           name.contains("panel") || name.contains("antenna") || name.contains("fence") ||
           name.contains("ladder") || name.contains("horn") {
            return .specialty
        }
        // Windows / doors
        if name.contains("window") || name.contains("door") || name.contains("shutter") {
            return .window
        }

        return piece.category
    }

    /// Generate a complete SCNNode for a LEGO brick with explicit dimensions
    static func generateBrick(
        studsWide: Int,
        studsLong: Int,
        heightUnits: Int,
        color: LegoColor,
        showStuds: Bool = true,
        showTubes: Bool = true,
        hollow: Bool = true
    ) -> SCNNode {
        let rootNode = SCNNode()
        rootNode.name = "brick_\(studsWide)x\(studsLong)x\(heightUnits)"

        let width = Float(studsWide) * studPitch
        let length = Float(studsLong) * studPitch
        let height = Float(heightUnits) * plateHeight

        let brickColor = scnColor(for: color)

        // Body
        if hollow {
            let shellNode = generateHollowBody(width: width, length: length, height: height, color: brickColor)
            rootNode.addChildNode(shellNode)
        } else {
            let bodyNode = generateSolidBody(width: width, length: length, height: height, color: brickColor)
            rootNode.addChildNode(bodyNode)
        }

        // Studs on top
        if showStuds {
            let studsNode = generateStuds(studsWide: studsWide, studsLong: studsLong, brickHeight: height, color: brickColor)
            rootNode.addChildNode(studsNode)
        }

        // Underside tubes (only for bricks wider or longer than 1)
        if showTubes && (studsWide > 1 || studsLong > 1) {
            let tubesNode = generateTubes(studsWide: studsWide, studsLong: studsLong, brickHeight: height, color: brickColor)
            rootNode.addChildNode(tubesNode)
        }

        return rootNode
    }

    /// Generate a complete build model from a project's required pieces
    /// Each piece is placed in a grid layout for visualization
    static func generateBuildModel(for project: LegoProject) -> SCNNode {
        let rootNode = SCNNode()
        rootNode.name = "build_\(project.name)"

        var xOffset: Float = 0
        var zOffset: Float = 0
        var maxHeightInRow: Float = 0
        let spacing: Float = 4.0 // gap between pieces
        let maxRowWidth: Float = 200.0

        for required in project.requiredPieces {
            for _ in 0..<required.quantity {
                let piece = SCNNode()
                let brickNode = generateBrick(
                    studsWide: required.dimensions.studsWide,
                    studsLong: required.dimensions.studsLong,
                    heightUnits: required.dimensions.heightUnits,
                    color: required.colorPreference ?? .gray,
                    showStuds: true,
                    showTubes: false,
                    hollow: false
                )
                piece.addChildNode(brickNode)

                let width = Float(required.dimensions.studsWide) * studPitch
                let length = Float(required.dimensions.studsLong) * studPitch

                // Wrap to next row if needed
                if xOffset + width > maxRowWidth && xOffset > 0 {
                    xOffset = 0
                    zOffset += maxHeightInRow + spacing
                    maxHeightInRow = 0
                }

                piece.position = SCNVector3(xOffset + width / 2, 0, zOffset + length / 2)
                rootNode.addChildNode(piece)

                xOffset += width + spacing
                maxHeightInRow = max(maxHeightInRow, length)
            }
        }

        return rootNode
    }

    // MARK: - Body Generation

    private static func generateSolidBody(width: Float, length: Float, height: Float, color: UIColor) -> SCNNode {
        let box = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length), chamferRadius: 0.2)
        box.firstMaterial = makeMaterial(color: color)
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(width / 2, height / 2, length / 2)
        node.name = "body_solid"
        return node
    }

    private static func generateHollowBody(width: Float, length: Float, height: Float, color: UIColor) -> SCNNode {
        let node = SCNNode()
        node.name = "body_hollow"

        let material = makeMaterial(color: color)
        let wt = wallThickness

        // Top face
        let top = SCNBox(width: CGFloat(width), height: CGFloat(wt), length: CGFloat(length), chamferRadius: 0.1)
        top.firstMaterial = material
        let topNode = SCNNode(geometry: top)
        topNode.position = SCNVector3(width / 2, height - wt / 2, length / 2)
        node.addChildNode(topNode)

        // Bottom face
        let bottom = SCNBox(width: CGFloat(width), height: CGFloat(wt), length: CGFloat(length), chamferRadius: 0.1)
        bottom.firstMaterial = material
        let bottomNode = SCNNode(geometry: bottom)
        bottomNode.position = SCNVector3(width / 2, wt / 2, length / 2)
        node.addChildNode(bottomNode)

        // Front wall
        let front = SCNBox(width: CGFloat(width), height: CGFloat(height - 2 * wt), length: CGFloat(wt), chamferRadius: 0.1)
        front.firstMaterial = material
        let frontNode = SCNNode(geometry: front)
        frontNode.position = SCNVector3(width / 2, height / 2, wt / 2)
        node.addChildNode(frontNode)

        // Back wall
        let back = SCNBox(width: CGFloat(width), height: CGFloat(height - 2 * wt), length: CGFloat(wt), chamferRadius: 0.1)
        back.firstMaterial = material
        let backNode = SCNNode(geometry: back)
        backNode.position = SCNVector3(width / 2, height / 2, length - wt / 2)
        node.addChildNode(backNode)

        // Left wall
        let left = SCNBox(width: CGFloat(wt), height: CGFloat(height - 2 * wt), length: CGFloat(length - 2 * wt), chamferRadius: 0.1)
        left.firstMaterial = material
        let leftNode = SCNNode(geometry: left)
        leftNode.position = SCNVector3(wt / 2, height / 2, length / 2)
        node.addChildNode(leftNode)

        // Right wall
        let right = SCNBox(width: CGFloat(wt), height: CGFloat(height - 2 * wt), length: CGFloat(length - 2 * wt), chamferRadius: 0.1)
        right.firstMaterial = material
        let rightNode = SCNNode(geometry: right)
        rightNode.position = SCNVector3(width - wt / 2, height / 2, length / 2)
        node.addChildNode(rightNode)

        return node
    }

    // MARK: - Studs

    private static func generateStuds(studsWide: Int, studsLong: Int, brickHeight: Float, color: UIColor) -> SCNNode {
        let studsNode = SCNNode()
        studsNode.name = "studs"

        let radius = studDiameter / 2
        let material = makeMaterial(color: color)

        for col in 0..<studsWide {
            for row in 0..<studsLong {
                let cylinder = SCNCylinder(radius: CGFloat(radius), height: CGFloat(studHeight))
                cylinder.radialSegmentCount = 24
                cylinder.firstMaterial = material

                let studNode = SCNNode(geometry: cylinder)
                let x = Float(col) * studPitch + studPitch / 2
                let y = brickHeight + studHeight / 2
                let z = Float(row) * studPitch + studPitch / 2
                studNode.position = SCNVector3(x, y, z)
                studsNode.addChildNode(studNode)
            }
        }

        return studsNode
    }

    // MARK: - Underside Tubes

    private static func generateTubes(studsWide: Int, studsLong: Int, brickHeight: Float, color: UIColor) -> SCNNode {
        let tubesNode = SCNNode()
        tubesNode.name = "tubes"

        let material = makeMaterial(color: color)
        let outerRadius = tubeOuterDiameter / 2
        let innerRadius = tubeInnerDiameter / 2
        let tubeHeight = brickHeight - wallThickness * 2

        // Tubes are placed between studs
        let tubeColCount = studsWide - 1
        let tubeRowCount = studsLong - 1

        for col in 0..<tubeColCount {
            for row in 0..<tubeRowCount {
                // Outer cylinder
                let outer = SCNCylinder(radius: CGFloat(outerRadius), height: CGFloat(tubeHeight))
                outer.radialSegmentCount = 24
                outer.firstMaterial = material

                // Inner cylinder (hollow)
                let inner = SCNCylinder(radius: CGFloat(innerRadius), height: CGFloat(tubeHeight + 0.1))
                inner.radialSegmentCount = 24
                inner.firstMaterial = makeMaterial(color: .black) // dark interior

                let tubeGroup = SCNNode()
                let outerNode = SCNNode(geometry: outer)
                let innerNode = SCNNode(geometry: inner)

                tubeGroup.addChildNode(outerNode)
                tubeGroup.addChildNode(innerNode)

                let x = Float(col + 1) * studPitch
                let y = wallThickness + tubeHeight / 2
                let z = Float(row + 1) * studPitch
                tubeGroup.position = SCNVector3(x, y, z)
                tubesNode.addChildNode(tubeGroup)
            }
        }

        return tubesNode
    }

    // MARK: - Materials

    private static func makeMaterial(color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.specular.contents = UIColor.white
        material.shininess = 0.4
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.3
        material.metalness.contents = 0.0
        return material
    }

    static func scnColor(for legoColor: LegoColor) -> UIColor {
        UIColor(Color(hex: legoColor.hexColor))
    }

    // MARK: - Category-Specific Geometry

    /// Technic pieces: gears, beams, axles, pins
    private static func generateTechnicPiece(for piece: LegoPiece, showStuds: Bool, hollow: Bool) -> SCNNode {
        let rootNode = SCNNode()
        let brickColor = scnColor(for: piece.color)
        let material = makeMaterial(color: brickColor)
        let name = piece.name.lowercased()

        if name.contains("gear") {
            // Technic gear — accurate representation with teeth, rim, spokes, and holes
            let toothCount = extractNumber(from: piece.name) ?? 24
            let outerRadius = Float(max(piece.dimensions.studsWide, piece.dimensions.studsLong)) * studPitch / 2
            let thickness = Float(piece.dimensions.heightUnits) * plateHeight
            let darkMat = makeMaterial(color: brickColor.withAlphaComponent(0.85))

            // --- Tooth dimensions based on real LEGO gear proportions ---
            let toothDepth = outerRadius * 0.12        // radial depth of each tooth
            let rimOuterRadius = outerRadius - toothDepth // where tooth roots sit
            let rimInnerRadius = rimOuterRadius - outerRadius * 0.06  // thin rim band
            let hubRadius = outerRadius * 0.22         // central hub
            let axleHoleSize = studPitch * 0.3         // cross-shaped axle

            // 1. Outer rim ring (the band teeth protrude from)
            let rim = SCNTorus(ringRadius: CGFloat(rimOuterRadius), pipeRadius: CGFloat(thickness / 2))
            rim.ringSegmentCount = 72
            rim.pipeSegmentCount = 12
            rim.firstMaterial = material
            let rimNode = SCNNode(geometry: rim)
            rimNode.position = SCNVector3(0, thickness / 2, 0)
            rootNode.addChildNode(rimNode)

            // Fill the rim band to make it a solid ring
            let rimDisc = SCNCylinder(radius: CGFloat(rimOuterRadius), height: CGFloat(thickness * 0.85))
            rimDisc.radialSegmentCount = 72
            rimDisc.firstMaterial = material
            let rimDiscNode = SCNNode(geometry: rimDisc)
            rimDiscNode.position = SCNVector3(0, thickness / 2, 0)
            rootNode.addChildNode(rimDiscNode)

            // Carve out the inner area (visual — dark disc inside the rim)
            let innerCutout = SCNCylinder(radius: CGFloat(rimInnerRadius), height: CGFloat(thickness * 0.87))
            innerCutout.radialSegmentCount = 72
            innerCutout.firstMaterial = darkMat
            let innerCutoutNode = SCNNode(geometry: innerCutout)
            innerCutoutNode.position = SCNVector3(0, thickness / 2, 0)
            rootNode.addChildNode(innerCutoutNode)

            // 2. Teeth — squared blocks protruding from the rim
            let toothWidth = 2 * .pi * rimOuterRadius / Float(toothCount) * 0.55
            for i in 0..<toothCount {
                let angle = Float(i) * (2 * .pi / Float(toothCount))
                let tooth = SCNBox(
                    width: CGFloat(toothWidth),
                    height: CGFloat(thickness * 0.85),
                    length: CGFloat(toothDepth * 1.3),
                    chamferRadius: CGFloat(toothWidth * 0.08)
                )
                tooth.firstMaterial = material
                let toothNode = SCNNode(geometry: tooth)
                let r = rimOuterRadius + toothDepth * 0.55
                toothNode.position = SCNVector3(
                    r * cos(angle),
                    thickness / 2,
                    r * sin(angle)
                )
                toothNode.eulerAngles.y = -angle
                rootNode.addChildNode(toothNode)
            }

            // 3. Spoke structure — cross pattern connecting hub to rim
            let spokeCount = 4
            let spokeWidth: Float = outerRadius * 0.08
            let spokeLength = rimInnerRadius - hubRadius
            for i in 0..<spokeCount {
                let angle = Float(i) * (.pi / Float(spokeCount)) + .pi / 8
                let spoke = SCNBox(
                    width: CGFloat(spokeWidth),
                    height: CGFloat(thickness * 0.6),
                    length: CGFloat(spokeLength),
                    chamferRadius: 0.2
                )
                spoke.firstMaterial = material
                let spokeNode = SCNNode(geometry: spoke)
                let r = hubRadius + spokeLength / 2
                spokeNode.position = SCNVector3(
                    r * cos(angle),
                    thickness / 2,
                    r * sin(angle)
                )
                spokeNode.eulerAngles.y = -angle
                rootNode.addChildNode(spokeNode)

                // Second spoke at opposite angle for + pattern per arm
                let angle2 = angle + .pi
                let spoke2 = SCNBox(
                    width: CGFloat(spokeWidth),
                    height: CGFloat(thickness * 0.6),
                    length: CGFloat(spokeLength),
                    chamferRadius: 0.2
                )
                spoke2.firstMaterial = material
                let spoke2Node = SCNNode(geometry: spoke2)
                spoke2Node.position = SCNVector3(
                    r * cos(angle2),
                    thickness / 2,
                    r * sin(angle2)
                )
                spoke2Node.eulerAngles.y = -angle2
                rootNode.addChildNode(spoke2Node)
            }

            // 4. Lightening holes — circular cutouts between spokes
            let holeRadius = outerRadius * 0.1
            let holeRingRadius = (hubRadius + rimInnerRadius) / 2
            let holeCount = 8
            for i in 0..<holeCount {
                let angle = Float(i) * (2 * .pi / Float(holeCount)) + .pi / Float(holeCount)
                let hole = SCNCylinder(radius: CGFloat(holeRadius), height: CGFloat(thickness + 0.2))
                hole.radialSegmentCount = 20
                hole.firstMaterial = darkMat
                let holeNode = SCNNode(geometry: hole)
                holeNode.position = SCNVector3(
                    holeRingRadius * cos(angle),
                    thickness / 2,
                    holeRingRadius * sin(angle)
                )
                rootNode.addChildNode(holeNode)
            }

            // 5. Central hub
            let hub = SCNCylinder(radius: CGFloat(hubRadius), height: CGFloat(thickness))
            hub.radialSegmentCount = 24
            hub.firstMaterial = material
            let hubNode = SCNNode(geometry: hub)
            hubNode.position = SCNVector3(0, thickness / 2, 0)
            rootNode.addChildNode(hubNode)

            // 6. Cross-shaped axle hole (+ shape using two intersecting boxes)
            let axleMat = makeMaterial(color: .darkGray)
            let axleBar1 = SCNBox(width: CGFloat(axleHoleSize), height: CGFloat(thickness + 0.3), length: CGFloat(axleHoleSize * 0.35), chamferRadius: 0)
            axleBar1.firstMaterial = axleMat
            let axleBar1Node = SCNNode(geometry: axleBar1)
            axleBar1Node.position = SCNVector3(0, thickness / 2, 0)
            rootNode.addChildNode(axleBar1Node)

            let axleBar2 = SCNBox(width: CGFloat(axleHoleSize * 0.35), height: CGFloat(thickness + 0.3), length: CGFloat(axleHoleSize), chamferRadius: 0)
            axleBar2.firstMaterial = axleMat
            let axleBar2Node = SCNNode(geometry: axleBar2)
            axleBar2Node.position = SCNVector3(0, thickness / 2, 0)
            rootNode.addChildNode(axleBar2Node)

            rootNode.name = "technic_gear_\(toothCount)"

        } else if name.contains("beam") || name.contains("liftarm") {
            // Technic beam: elongated bar with pin holes
            let length = Float(max(piece.dimensions.studsWide, piece.dimensions.studsLong)) * studPitch
            let beamHeight = studPitch
            let beamDepth = studPitch

            // Main beam body
            let body = SCNBox(width: CGFloat(length), height: CGFloat(beamHeight), length: CGFloat(beamDepth), chamferRadius: CGFloat(beamHeight * 0.15))
            body.firstMaterial = material
            let bodyNode = SCNNode(geometry: body)
            bodyNode.position = SCNVector3(length / 2, beamHeight / 2, beamDepth / 2)
            rootNode.addChildNode(bodyNode)

            // Pin holes along the length
            let holeCount = max(piece.dimensions.studsWide, piece.dimensions.studsLong)
            let holeMaterial = makeMaterial(color: .darkGray)
            for i in 0..<holeCount {
                let hole = SCNCylinder(radius: CGFloat(studPitch * 0.3), height: CGFloat(beamDepth + 0.2))
                hole.radialSegmentCount = 16
                hole.firstMaterial = holeMaterial
                let holeNode = SCNNode(geometry: hole)
                holeNode.position = SCNVector3(Float(i) * studPitch + studPitch / 2, beamHeight / 2, beamDepth / 2)
                holeNode.eulerAngles.x = .pi / 2
                rootNode.addChildNode(holeNode)
            }

            rootNode.name = "technic_beam_\(holeCount)"

        } else if name.contains("axle") {
            // Technic axle: cross-shaped profile extruded
            let length = Float(max(piece.dimensions.studsWide, piece.dimensions.studsLong)) * studPitch
            let armWidth: Float = 1.8
            let armLength: Float = studPitch * 0.45

            // Two crossed bars forming + shape
            let bar1 = SCNBox(width: CGFloat(armWidth), height: CGFloat(armLength), length: CGFloat(length), chamferRadius: 0.1)
            bar1.firstMaterial = material
            let bar1Node = SCNNode(geometry: bar1)
            bar1Node.position = SCNVector3(0, 0, length / 2)
            rootNode.addChildNode(bar1Node)

            let bar2 = SCNBox(width: CGFloat(armLength), height: CGFloat(armWidth), length: CGFloat(length), chamferRadius: 0.1)
            bar2.firstMaterial = material
            let bar2Node = SCNNode(geometry: bar2)
            bar2Node.position = SCNVector3(0, 0, length / 2)
            rootNode.addChildNode(bar2Node)

            rootNode.name = "technic_axle"

        } else if name.contains("pin") {
            // Technic pin: small cylinder with friction ridges
            let pinLength = Float(piece.dimensions.heightUnits) * plateHeight
            let pinRadius = studPitch * 0.3

            let pin = SCNCylinder(radius: CGFloat(pinRadius), height: CGFloat(pinLength))
            pin.radialSegmentCount = 16
            pin.firstMaterial = material
            let pinNode = SCNNode(geometry: pin)
            pinNode.position = SCNVector3(0, pinLength / 2, 0)
            rootNode.addChildNode(pinNode)

            // Ridge ring in the middle
            let ridge = SCNTorus(ringRadius: CGFloat(pinRadius), pipeRadius: CGFloat(pinRadius * 0.15))
            ridge.firstMaterial = material
            let ridgeNode = SCNNode(geometry: ridge)
            ridgeNode.position = SCNVector3(0, pinLength / 2, 0)
            rootNode.addChildNode(ridgeNode)

            rootNode.name = "technic_pin"

        } else {
            // Generic technic piece — fallback to rectangular with holes
            return generateBrick(
                studsWide: piece.dimensions.studsWide,
                studsLong: piece.dimensions.studsLong,
                heightUnits: piece.dimensions.heightUnits,
                color: piece.color,
                showStuds: showStuds,
                showTubes: false,
                hollow: hollow
            )
        }

        return rootNode
    }

    /// Round pieces: round bricks, round plates, cones, domes
    private static func generateRoundPiece(for piece: LegoPiece, showStuds: Bool, hollow: Bool) -> SCNNode {
        let rootNode = SCNNode()
        let brickColor = scnColor(for: piece.color)
        let material = makeMaterial(color: brickColor)
        let name = piece.name.lowercased()

        let radius = Float(max(piece.dimensions.studsWide, piece.dimensions.studsLong)) * studPitch / 2
        let height = Float(piece.dimensions.heightUnits) * plateHeight

        if name.contains("cone") {
            let cone = SCNCone(topRadius: CGFloat(radius * 0.1), bottomRadius: CGFloat(radius), height: CGFloat(height))
            cone.radialSegmentCount = 36
            cone.firstMaterial = material
            let coneNode = SCNNode(geometry: cone)
            coneNode.position = SCNVector3(0, height / 2, 0)
            rootNode.addChildNode(coneNode)
            rootNode.name = "round_cone"

        } else if name.contains("dome") || name.contains("hemisphere") {
            let sphere = SCNSphere(radius: CGFloat(radius))
            sphere.segmentCount = 36
            sphere.firstMaterial = material
            let sphereNode = SCNNode(geometry: sphere)
            sphereNode.position = SCNVector3(0, radius, 0)

            // Clip bottom half using a flat box (visual approximation)
            let baseHeight = height * 0.3
            let base = SCNCylinder(radius: CGFloat(radius), height: CGFloat(baseHeight))
            base.radialSegmentCount = 36
            base.firstMaterial = material
            let baseNode = SCNNode(geometry: base)
            baseNode.position = SCNVector3(0, baseHeight / 2, 0)

            rootNode.addChildNode(baseNode)
            rootNode.addChildNode(sphereNode)
            rootNode.name = "round_dome"

        } else {
            // Standard round brick/plate — cylinder body
            if hollow {
                // Outer cylinder
                let outer = SCNCylinder(radius: CGFloat(radius), height: CGFloat(height))
                outer.radialSegmentCount = 36
                outer.firstMaterial = material
                let outerNode = SCNNode(geometry: outer)
                outerNode.position = SCNVector3(0, height / 2, 0)
                rootNode.addChildNode(outerNode)

                // Hollow interior
                let inner = SCNCylinder(radius: CGFloat(radius - wallThickness), height: CGFloat(height - wallThickness))
                inner.radialSegmentCount = 36
                inner.firstMaterial = makeMaterial(color: .darkGray)
                let innerNode = SCNNode(geometry: inner)
                innerNode.position = SCNVector3(0, height / 2 + wallThickness * 0.25, 0)
                rootNode.addChildNode(innerNode)
            } else {
                let cyl = SCNCylinder(radius: CGFloat(radius), height: CGFloat(height))
                cyl.radialSegmentCount = 36
                cyl.firstMaterial = material
                let cylNode = SCNNode(geometry: cyl)
                cylNode.position = SCNVector3(0, height / 2, 0)
                rootNode.addChildNode(cylNode)
            }

            // Single centered stud on top
            if showStuds {
                let stud = SCNCylinder(radius: CGFloat(studDiameter / 2), height: CGFloat(studHeight))
                stud.radialSegmentCount = 24
                stud.firstMaterial = material
                let studNode = SCNNode(geometry: stud)
                studNode.position = SCNVector3(0, height + studHeight / 2, 0)
                rootNode.addChildNode(studNode)
            }
            rootNode.name = "round_brick"
        }

        return rootNode
    }

    /// Slope pieces: angled top surface
    private static func generateSlopePiece(for piece: LegoPiece, showStuds: Bool, hollow: Bool) -> SCNNode {
        let rootNode = SCNNode()
        let brickColor = scnColor(for: piece.color)
        let material = makeMaterial(color: brickColor)

        let width = Float(piece.dimensions.studsWide) * studPitch
        let length = Float(piece.dimensions.studsLong) * studPitch
        let height = Float(piece.dimensions.heightUnits) * plateHeight

        // Base rectangular portion (bottom half)
        let baseHeight = height * 0.4
        let base = SCNBox(width: CGFloat(width), height: CGFloat(baseHeight), length: CGFloat(length), chamferRadius: 0.2)
        base.firstMaterial = material
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(width / 2, baseHeight / 2, length / 2)
        rootNode.addChildNode(baseNode)

        // Sloped top portion using custom geometry (triangular prism)
        let slopeHeight = height - baseHeight
        let vertices: [SCNVector3] = [
            // Front face (low side)
            SCNVector3(0, baseHeight, 0),
            SCNVector3(width, baseHeight, 0),
            SCNVector3(0, baseHeight, length),
            SCNVector3(width, baseHeight, length),
            // Back face (high side) — slope rises from front to back
            SCNVector3(0, baseHeight + slopeHeight, length),
            SCNVector3(width, baseHeight + slopeHeight, length),
        ]

        // Use a simple wedge box approximation
        let slopeBox = SCNBox(width: CGFloat(width), height: CGFloat(slopeHeight), length: CGFloat(length), chamferRadius: 0.1)
        slopeBox.firstMaterial = material
        let slopeNode = SCNNode(geometry: slopeBox)
        slopeNode.position = SCNVector3(width / 2, baseHeight + slopeHeight / 2, length / 2)
        // Rotate to create slope effect
        slopeNode.eulerAngles.x = atan2(slopeHeight, length) * 0.5
        slopeNode.scale.y = 0.7
        rootNode.addChildNode(slopeNode)

        // Studs on the high (flat) end only
        if showStuds {
            let studMat = material
            for col in 0..<piece.dimensions.studsWide {
                let stud = SCNCylinder(radius: CGFloat(studDiameter / 2), height: CGFloat(studHeight))
                stud.radialSegmentCount = 24
                stud.firstMaterial = studMat
                let studNode = SCNNode(geometry: stud)
                studNode.position = SCNVector3(
                    Float(col) * studPitch + studPitch / 2,
                    height + studHeight / 2,
                    length - studPitch / 2
                )
                rootNode.addChildNode(studNode)
            }
        }

        rootNode.name = "slope_\(piece.dimensions.studsWide)x\(piece.dimensions.studsLong)"
        _ = vertices // suppress unused warning
        return rootNode
    }

    /// Arch pieces: brick with curved opening
    private static func generateArchPiece(for piece: LegoPiece, showStuds: Bool, hollow: Bool) -> SCNNode {
        let rootNode = SCNNode()
        let brickColor = scnColor(for: piece.color)
        let material = makeMaterial(color: brickColor)

        let width = Float(piece.dimensions.studsWide) * studPitch
        let length = Float(piece.dimensions.studsLong) * studPitch
        let height = Float(piece.dimensions.heightUnits) * plateHeight

        // Two pillars on each side
        let pillarWidth = studPitch
        let leftPillar = SCNBox(width: CGFloat(pillarWidth), height: CGFloat(height), length: CGFloat(length), chamferRadius: 0.2)
        leftPillar.firstMaterial = material
        let leftNode = SCNNode(geometry: leftPillar)
        leftNode.position = SCNVector3(pillarWidth / 2, height / 2, length / 2)
        rootNode.addChildNode(leftNode)

        let rightPillar = SCNBox(width: CGFloat(pillarWidth), height: CGFloat(height), length: CGFloat(length), chamferRadius: 0.2)
        rightPillar.firstMaterial = material
        let rightNode = SCNNode(geometry: rightPillar)
        rightNode.position = SCNVector3(width - pillarWidth / 2, height / 2, length / 2)
        rootNode.addChildNode(rightNode)

        // Top beam connecting pillars
        let beamHeight = height * 0.35
        let topBeam = SCNBox(width: CGFloat(width), height: CGFloat(beamHeight), length: CGFloat(length), chamferRadius: 0.2)
        topBeam.firstMaterial = material
        let topNode = SCNNode(geometry: topBeam)
        topNode.position = SCNVector3(width / 2, height - beamHeight / 2, length / 2)
        rootNode.addChildNode(topNode)

        // Curved arch in the opening (half-torus visual approximation)
        let archRadius = (width - 2 * pillarWidth) / 2
        if archRadius > 0 {
            let arch = SCNTorus(ringRadius: CGFloat(archRadius), pipeRadius: CGFloat(min(archRadius * 0.3, beamHeight * 0.4)))
            arch.firstMaterial = material
            let archNode = SCNNode(geometry: arch)
            archNode.position = SCNVector3(width / 2, height - beamHeight, length / 2)
            archNode.eulerAngles.x = .pi / 2
            // Only show top half
            archNode.scale = SCNVector3(1, 1, 0.5)
            rootNode.addChildNode(archNode)
        }

        // Studs on top
        if showStuds {
            let studsNode = generateStuds(studsWide: piece.dimensions.studsWide, studsLong: piece.dimensions.studsLong, brickHeight: height, color: brickColor)
            rootNode.addChildNode(studsNode)
        }

        rootNode.name = "arch_\(piece.dimensions.studsWide)x\(piece.dimensions.studsLong)"
        return rootNode
    }

    /// Wheel pieces: tire + hub
    private static func generateWheelPiece(for piece: LegoPiece) -> SCNNode {
        let rootNode = SCNNode()
        let brickColor = scnColor(for: piece.color)
        let material = makeMaterial(color: brickColor)

        let outerRadius = Float(max(piece.dimensions.studsWide, piece.dimensions.studsLong)) * studPitch / 2
        let thickness = Float(piece.dimensions.heightUnits) * plateHeight

        // Tire (outer torus)
        let tire = SCNTorus(ringRadius: CGFloat(outerRadius * 0.8), pipeRadius: CGFloat(outerRadius * 0.25))
        tire.ringSegmentCount = 48
        tire.pipeSegmentCount = 24
        tire.firstMaterial = makeMaterial(color: .darkGray)
        let tireNode = SCNNode(geometry: tire)
        tireNode.position = SCNVector3(0, outerRadius, 0)
        rootNode.addChildNode(tireNode)

        // Hub (inner disc)
        let hub = SCNCylinder(radius: CGFloat(outerRadius * 0.55), height: CGFloat(thickness * 0.6))
        hub.radialSegmentCount = 36
        hub.firstMaterial = material
        let hubNode = SCNNode(geometry: hub)
        hubNode.position = SCNVector3(0, outerRadius, 0)
        hubNode.eulerAngles.x = .pi / 2
        rootNode.addChildNode(hubNode)

        // Axle hole
        let axle = SCNCylinder(radius: CGFloat(studPitch * 0.3), height: CGFloat(thickness * 0.8))
        axle.radialSegmentCount = 4
        axle.firstMaterial = makeMaterial(color: .black)
        let axleNode = SCNNode(geometry: axle)
        axleNode.position = SCNVector3(0, outerRadius, 0)
        axleNode.eulerAngles.x = .pi / 2
        rootNode.addChildNode(axleNode)

        rootNode.name = "wheel"
        return rootNode
    }

    /// Tile pieces: flat plate without studs
    private static func generateTilePiece(for piece: LegoPiece, hollow: Bool) -> SCNNode {
        let rootNode = SCNNode()
        let brickColor = scnColor(for: piece.color)

        let width = Float(piece.dimensions.studsWide) * studPitch
        let length = Float(piece.dimensions.studsLong) * studPitch
        let height = Float(piece.dimensions.heightUnits) * plateHeight

        if hollow {
            let shellNode = generateHollowBody(width: width, length: length, height: height, color: brickColor)
            rootNode.addChildNode(shellNode)
        } else {
            let bodyNode = generateSolidBody(width: width, length: length, height: height, color: brickColor)
            rootNode.addChildNode(bodyNode)
        }

        // No studs — tiles are smooth on top
        // Add a subtle groove line around the edge (like real tiles)
        let grooveMaterial = makeMaterial(color: brickColor.withAlphaComponent(0.7))
        let grooveDepth: Float = 0.3
        let groove = SCNBox(width: CGFloat(width - 1.0), height: CGFloat(grooveDepth), length: CGFloat(length - 1.0), chamferRadius: 0.1)
        groove.firstMaterial = grooveMaterial
        let grooveNode = SCNNode(geometry: groove)
        grooveNode.position = SCNVector3(width / 2, height + grooveDepth / 2, length / 2)
        rootNode.addChildNode(grooveNode)

        rootNode.name = "tile_\(piece.dimensions.studsWide)x\(piece.dimensions.studsLong)"
        return rootNode
    }

    /// Wedge pieces: tapered/angled brick
    private static func generateWedgePiece(for piece: LegoPiece, showStuds: Bool, hollow: Bool) -> SCNNode {
        let rootNode = SCNNode()
        let brickColor = scnColor(for: piece.color)
        let material = makeMaterial(color: brickColor)

        let width = Float(piece.dimensions.studsWide) * studPitch
        let length = Float(piece.dimensions.studsLong) * studPitch
        let height = Float(piece.dimensions.heightUnits) * plateHeight

        // Wide end (full width)
        let wideEnd = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length * 0.5), chamferRadius: 0.2)
        wideEnd.firstMaterial = material
        let wideNode = SCNNode(geometry: wideEnd)
        wideNode.position = SCNVector3(width / 2, height / 2, length * 0.25)
        rootNode.addChildNode(wideNode)

        // Narrow end (tapers to half width)
        let narrowWidth = width * 0.4
        let narrowEnd = SCNBox(width: CGFloat(narrowWidth), height: CGFloat(height), length: CGFloat(length * 0.5), chamferRadius: 0.2)
        narrowEnd.firstMaterial = material
        let narrowNode = SCNNode(geometry: narrowEnd)
        narrowNode.position = SCNVector3(width / 2, height / 2, length * 0.75)
        rootNode.addChildNode(narrowNode)

        // Connecting taper panels (left and right)
        let taperLength = length * 0.5
        let taperWidth = (width - narrowWidth) / 2
        for side: Float in [-1, 1] {
            let panel = SCNBox(width: CGFloat(taperWidth * 0.6), height: CGFloat(height * 0.9), length: CGFloat(taperLength), chamferRadius: 0.1)
            panel.firstMaterial = material
            let panelNode = SCNNode(geometry: panel)
            let xPos = width / 2 + side * (narrowWidth / 2 + taperWidth * 0.3)
            panelNode.position = SCNVector3(xPos, height / 2, length * 0.65)
            rootNode.addChildNode(panelNode)
        }

        if showStuds {
            let studsNode = generateStuds(studsWide: piece.dimensions.studsWide, studsLong: piece.dimensions.studsLong, brickHeight: height, color: brickColor)
            rootNode.addChildNode(studsNode)
        }

        rootNode.name = "wedge_\(piece.dimensions.studsWide)x\(piece.dimensions.studsLong)"
        return rootNode
    }

    /// Minifigure pieces: simplified humanoid shape
    private static func generateMinifigurePiece(for piece: LegoPiece) -> SCNNode {
        let rootNode = SCNNode()
        let brickColor = scnColor(for: piece.color)
        let material = makeMaterial(color: brickColor)

        // Head (yellow)
        let headMat = makeMaterial(color: UIColor(Color.legoYellow))
        let head = SCNCylinder(radius: 4.0, height: 6.0)
        head.radialSegmentCount = 24
        head.firstMaterial = headMat
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 25, 0)
        rootNode.addChildNode(headNode)

        // Stud on head
        let stud = SCNCylinder(radius: CGFloat(studDiameter / 2), height: CGFloat(studHeight))
        stud.radialSegmentCount = 24
        stud.firstMaterial = headMat
        let studNode = SCNNode(geometry: stud)
        studNode.position = SCNVector3(0, 28.85, 0)
        rootNode.addChildNode(studNode)

        // Torso
        let torso = SCNBox(width: 10, height: 10, length: 5, chamferRadius: 0.5)
        torso.firstMaterial = material
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.position = SCNVector3(0, 16, 0)
        rootNode.addChildNode(torsoNode)

        // Legs
        for side: Float in [-1, 1] {
            let leg = SCNBox(width: 4.5, height: 10, length: 5, chamferRadius: 0.3)
            leg.firstMaterial = material
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(side * 2.5, 5, 0)
            rootNode.addChildNode(legNode)
        }

        // Arms
        for side: Float in [-1, 1] {
            let arm = SCNBox(width: 2.5, height: 8, length: 3, chamferRadius: 0.3)
            arm.firstMaterial = material
            let armNode = SCNNode(geometry: arm)
            armNode.position = SCNVector3(side * 7, 16, 0)
            rootNode.addChildNode(armNode)
        }

        rootNode.name = "minifigure"
        return rootNode
    }

    /// Connector/Hinge/Bracket pieces: small functional parts
    private static func generateConnectorPiece(for piece: LegoPiece) -> SCNNode {
        let rootNode = SCNNode()
        let brickColor = scnColor(for: piece.color)
        let material = makeMaterial(color: brickColor)
        let name = piece.name.lowercased()

        let width = Float(piece.dimensions.studsWide) * studPitch
        let length = Float(piece.dimensions.studsLong) * studPitch
        let height = Float(piece.dimensions.heightUnits) * plateHeight

        if name.contains("hinge") {
            // Two plates connected by a hinge cylinder
            let halfWidth = width / 2 - 1

            let plate1 = SCNBox(width: CGFloat(halfWidth), height: CGFloat(height), length: CGFloat(length), chamferRadius: 0.2)
            plate1.firstMaterial = material
            let plate1Node = SCNNode(geometry: plate1)
            plate1Node.position = SCNVector3(halfWidth / 2, height / 2, length / 2)
            rootNode.addChildNode(plate1Node)

            let plate2 = SCNBox(width: CGFloat(halfWidth), height: CGFloat(height), length: CGFloat(length), chamferRadius: 0.2)
            plate2.firstMaterial = material
            let plate2Node = SCNNode(geometry: plate2)
            plate2Node.position = SCNVector3(width - halfWidth / 2, height / 2, length / 2)
            rootNode.addChildNode(plate2Node)

            // Hinge cylinder
            let hinge = SCNCylinder(radius: CGFloat(height * 0.4), height: CGFloat(length * 0.6))
            hinge.radialSegmentCount = 16
            hinge.firstMaterial = makeMaterial(color: brickColor.withAlphaComponent(0.8))
            let hingeNode = SCNNode(geometry: hinge)
            hingeNode.position = SCNVector3(width / 2, height / 2, length / 2)
            hingeNode.eulerAngles.x = .pi / 2
            rootNode.addChildNode(hingeNode)

        } else if name.contains("bracket") {
            // L-shaped bracket
            let horizontal = SCNBox(width: CGFloat(width), height: CGFloat(height * 0.4), length: CGFloat(length), chamferRadius: 0.2)
            horizontal.firstMaterial = material
            let hNode = SCNNode(geometry: horizontal)
            hNode.position = SCNVector3(width / 2, height * 0.2, length / 2)
            rootNode.addChildNode(hNode)

            let vertical = SCNBox(width: CGFloat(width * 0.3), height: CGFloat(height), length: CGFloat(length), chamferRadius: 0.2)
            vertical.firstMaterial = material
            let vNode = SCNNode(geometry: vertical)
            vNode.position = SCNVector3(width * 0.15, height / 2, length / 2)
            rootNode.addChildNode(vNode)

        } else {
            // Generic connector — small cylinder + plate
            let body = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length), chamferRadius: 0.3)
            body.firstMaterial = material
            let bodyNode = SCNNode(geometry: body)
            bodyNode.position = SCNVector3(width / 2, height / 2, length / 2)
            rootNode.addChildNode(bodyNode)

            let pin = SCNCylinder(radius: CGFloat(studPitch * 0.25), height: CGFloat(studPitch))
            pin.radialSegmentCount = 16
            pin.firstMaterial = material
            let pinNode = SCNNode(geometry: pin)
            pinNode.position = SCNVector3(width / 2, height + studPitch / 2, length / 2)
            rootNode.addChildNode(pinNode)
        }

        rootNode.name = "connector_\(piece.category.rawValue.lowercased())"
        return rootNode
    }

    /// Specialty pieces: plants, flowers, flags, panels, wings, antennas
    private static func generateSpecialtyPiece(for piece: LegoPiece, showStuds: Bool, hollow: Bool) -> SCNNode {
        let rootNode = SCNNode()
        let brickColor = scnColor(for: piece.color)
        let material = makeMaterial(color: brickColor)
        let name = piece.name.lowercased()

        if name.contains("leaf") || name.contains("leaves") || name.contains("plant leaves") {
            // Plant leaves: cluster of leaf shapes radiating from a central stem
            let leafCount = max(piece.dimensions.studsWide, piece.dimensions.studsLong)
            let leafLength = Float(max(piece.dimensions.studsWide, piece.dimensions.studsLong)) * studPitch * 0.45
            let leafWidth = leafLength * 0.35
            let leafThickness: Float = plateHeight * 0.3

            // Central stem nub (connection point)
            let stem = SCNCylinder(radius: CGFloat(studDiameter / 2), height: CGFloat(plateHeight))
            stem.radialSegmentCount = 16
            stem.firstMaterial = material
            let stemNode = SCNNode(geometry: stem)
            stemNode.position = SCNVector3(0, plateHeight / 2, 0)
            rootNode.addChildNode(stemNode)

            // Leaves radiating outward
            let totalLeaves = max(leafCount, 4)
            for i in 0..<totalLeaves {
                let angle = Float(i) * (2 * .pi / Float(totalLeaves))
                let leaf = SCNBox(
                    width: CGFloat(leafWidth),
                    height: CGFloat(leafThickness),
                    length: CGFloat(leafLength),
                    chamferRadius: CGFloat(leafWidth * 0.4)
                )
                leaf.firstMaterial = material
                let leafNode = SCNNode(geometry: leaf)
                leafNode.position = SCNVector3(
                    (leafLength * 0.5) * cos(angle),
                    plateHeight + leafThickness / 2,
                    (leafLength * 0.5) * sin(angle)
                )
                leafNode.eulerAngles.y = -angle
                // Slight droop
                leafNode.eulerAngles.x = 0.15
                rootNode.addChildNode(leafNode)

                // Leaf tip (pointed end)
                let tip = SCNBox(
                    width: CGFloat(leafWidth * 0.5),
                    height: CGFloat(leafThickness),
                    length: CGFloat(leafLength * 0.4),
                    chamferRadius: CGFloat(leafWidth * 0.25)
                )
                tip.firstMaterial = material
                let tipNode = SCNNode(geometry: tip)
                tipNode.position = SCNVector3(
                    (leafLength * 0.85) * cos(angle),
                    plateHeight + leafThickness / 2,
                    (leafLength * 0.85) * sin(angle)
                )
                tipNode.eulerAngles.y = -angle
                tipNode.eulerAngles.x = 0.25
                rootNode.addChildNode(tipNode)
            }

            rootNode.name = "plant_leaves"

        } else if name.contains("flower") {
            // Flower: petals around a center
            let radius = Float(max(piece.dimensions.studsWide, piece.dimensions.studsLong)) * studPitch / 2
            let petalCount = 5

            // Center
            let center = SCNCylinder(radius: CGFloat(radius * 0.3), height: CGFloat(plateHeight * 0.8))
            center.radialSegmentCount = 16
            center.firstMaterial = makeMaterial(color: UIColor.systemYellow)
            let centerNode = SCNNode(geometry: center)
            centerNode.position = SCNVector3(0, plateHeight * 0.4, 0)
            rootNode.addChildNode(centerNode)

            // Petals
            for i in 0..<petalCount {
                let angle = Float(i) * (2 * .pi / Float(petalCount))
                let petal = SCNBox(
                    width: CGFloat(radius * 0.45),
                    height: CGFloat(plateHeight * 0.4),
                    length: CGFloat(radius * 0.7),
                    chamferRadius: CGFloat(radius * 0.2)
                )
                petal.firstMaterial = material
                let petalNode = SCNNode(geometry: petal)
                petalNode.position = SCNVector3(
                    radius * 0.55 * cos(angle),
                    plateHeight * 0.3,
                    radius * 0.55 * sin(angle)
                )
                petalNode.eulerAngles.y = -angle
                rootNode.addChildNode(petalNode)
            }

            // Stem
            let stemH: Float = radius * 1.5
            let stemGeo = SCNCylinder(radius: CGFloat(studPitch * 0.15), height: CGFloat(stemH))
            stemGeo.radialSegmentCount = 8
            stemGeo.firstMaterial = makeMaterial(color: UIColor.systemGreen)
            let stemNode = SCNNode(geometry: stemGeo)
            stemNode.position = SCNVector3(0, -stemH / 2, 0)
            rootNode.addChildNode(stemNode)

            rootNode.name = "flower"

        } else if name.contains("tree") || name.contains("palm") {
            // Tree: trunk + foliage sphere
            let trunkHeight = Float(piece.dimensions.heightUnits) * plateHeight
            let foliageRadius = Float(max(piece.dimensions.studsWide, piece.dimensions.studsLong)) * studPitch / 2

            let trunk = SCNCylinder(radius: CGFloat(studPitch * 0.4), height: CGFloat(trunkHeight))
            trunk.radialSegmentCount = 12
            trunk.firstMaterial = makeMaterial(color: UIColor.brown)
            let trunkNode = SCNNode(geometry: trunk)
            trunkNode.position = SCNVector3(0, trunkHeight / 2, 0)
            rootNode.addChildNode(trunkNode)

            let foliage = SCNSphere(radius: CGFloat(foliageRadius))
            foliage.segmentCount = 24
            foliage.firstMaterial = material
            let foliageNode = SCNNode(geometry: foliage)
            foliageNode.position = SCNVector3(0, trunkHeight + foliageRadius * 0.6, 0)
            rootNode.addChildNode(foliageNode)

            rootNode.name = "tree"

        } else if name.contains("flag") || name.contains("banner") {
            // Flag on a pole
            let height = Float(piece.dimensions.heightUnits) * plateHeight
            let flagWidth = Float(max(piece.dimensions.studsWide, piece.dimensions.studsLong)) * studPitch

            // Pole
            let pole = SCNCylinder(radius: 0.8, height: CGFloat(height * 1.5))
            pole.radialSegmentCount = 8
            pole.firstMaterial = makeMaterial(color: .darkGray)
            let poleNode = SCNNode(geometry: pole)
            poleNode.position = SCNVector3(0, height * 0.75, 0)
            rootNode.addChildNode(poleNode)

            // Flag cloth (thin box with slight wave)
            let flag = SCNBox(width: CGFloat(flagWidth), height: CGFloat(height * 0.6), length: CGFloat(plateHeight * 0.2), chamferRadius: 0.3)
            flag.firstMaterial = material
            let flagNode = SCNNode(geometry: flag)
            flagNode.position = SCNVector3(flagWidth / 2 + 1, height * 1.1, 0)
            flagNode.eulerAngles.z = -0.05 // slight droop
            rootNode.addChildNode(flagNode)

            rootNode.name = "flag"

        } else if name.contains("wing") {
            // Wing: flat tapered plate
            let width = Float(piece.dimensions.studsWide) * studPitch
            let length = Float(piece.dimensions.studsLong) * studPitch
            let height = plateHeight

            // Main wing surface
            let wing = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length), chamferRadius: 0.3)
            wing.firstMaterial = material
            let wingNode = SCNNode(geometry: wing)
            wingNode.position = SCNVector3(width / 2, height / 2, length / 2)
            rootNode.addChildNode(wingNode)

            // Tapered trailing edge
            let taper = SCNBox(width: CGFloat(width * 0.6), height: CGFloat(height * 0.6), length: CGFloat(length * 0.3), chamferRadius: 0.2)
            taper.firstMaterial = material
            let taperNode = SCNNode(geometry: taper)
            taperNode.position = SCNVector3(width * 0.7, height * 0.3, length * 0.85)
            rootNode.addChildNode(taperNode)

            if showStuds {
                let studsNode = generateStuds(studsWide: piece.dimensions.studsWide, studsLong: piece.dimensions.studsLong, brickHeight: height, color: brickColor)
                rootNode.addChildNode(studsNode)
            }

            rootNode.name = "wing"

        } else if name.contains("panel") {
            // Flat panel wall
            let width = Float(piece.dimensions.studsWide) * studPitch
            let length = Float(piece.dimensions.studsLong) * studPitch
            let height = Float(piece.dimensions.heightUnits) * plateHeight

            let panel = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(wallThickness), chamferRadius: 0.2)
            panel.firstMaterial = material
            let panelNode = SCNNode(geometry: panel)
            panelNode.position = SCNVector3(width / 2, height / 2, wallThickness / 2)
            rootNode.addChildNode(panelNode)

            // Bottom rail with studs
            let rail = SCNBox(width: CGFloat(width), height: CGFloat(plateHeight), length: CGFloat(length), chamferRadius: 0.2)
            rail.firstMaterial = material
            let railNode = SCNNode(geometry: rail)
            railNode.position = SCNVector3(width / 2, plateHeight / 2, length / 2)
            rootNode.addChildNode(railNode)

            rootNode.name = "panel"

        } else if name.contains("fence") || name.contains("ladder") {
            // Fence/ladder: vertical bars
            let width = Float(piece.dimensions.studsWide) * studPitch
            let height = Float(piece.dimensions.heightUnits) * plateHeight
            let barCount = max(piece.dimensions.studsWide + 1, 3)
            let barSpacing = width / Float(barCount - 1)

            // Vertical bars
            for i in 0..<barCount {
                let bar = SCNCylinder(radius: 0.6, height: CGFloat(height))
                bar.radialSegmentCount = 8
                bar.firstMaterial = material
                let barNode = SCNNode(geometry: bar)
                barNode.position = SCNVector3(Float(i) * barSpacing, height / 2, 0)
                rootNode.addChildNode(barNode)
            }

            // Top rail
            let topRail = SCNBox(width: CGFloat(width), height: 1.2, length: 1.2, chamferRadius: 0.2)
            topRail.firstMaterial = material
            let topNode = SCNNode(geometry: topRail)
            topNode.position = SCNVector3(width / 2, height, 0)
            rootNode.addChildNode(topNode)

            // Bottom rail
            let bottomRail = SCNBox(width: CGFloat(width), height: 1.2, length: 1.2, chamferRadius: 0.2)
            bottomRail.firstMaterial = material
            let bottomNode = SCNNode(geometry: bottomRail)
            bottomNode.position = SCNVector3(width / 2, plateHeight * 0.5, 0)
            rootNode.addChildNode(bottomNode)

            rootNode.name = "fence"

        } else if name.contains("antenna") {
            // Antenna: thin pole with optional top element
            let height = Float(piece.dimensions.heightUnits) * plateHeight * 2
            let pole = SCNCylinder(radius: 0.5, height: CGFloat(height))
            pole.radialSegmentCount = 8
            pole.firstMaterial = material
            let poleNode = SCNNode(geometry: pole)
            poleNode.position = SCNVector3(0, height / 2, 0)
            rootNode.addChildNode(poleNode)

            // Top ball
            let ball = SCNSphere(radius: 1.0)
            ball.segmentCount = 16
            ball.firstMaterial = material
            let ballNode = SCNNode(geometry: ball)
            ballNode.position = SCNVector3(0, height + 1.0, 0)
            rootNode.addChildNode(ballNode)

            rootNode.name = "antenna"

        } else {
            // Generic specialty — use standard brick shape
            return generateBrick(
                studsWide: piece.dimensions.studsWide,
                studsLong: piece.dimensions.studsLong,
                heightUnits: piece.dimensions.heightUnits,
                color: piece.color,
                showStuds: showStuds,
                showTubes: false,
                hollow: hollow
            )
        }

        return rootNode
    }

    /// Window/door pieces: frame with transparent opening
    private static func generateWindowPiece(for piece: LegoPiece, showStuds: Bool) -> SCNNode {
        let rootNode = SCNNode()
        let brickColor = scnColor(for: piece.color)
        let material = makeMaterial(color: brickColor)

        let width = Float(piece.dimensions.studsWide) * studPitch
        let length = Float(piece.dimensions.studsLong) * studPitch
        let height = Float(piece.dimensions.heightUnits) * plateHeight

        let frameWidth = wallThickness * 1.2

        // Frame — four edges
        // Bottom
        let bottom = SCNBox(width: CGFloat(width), height: CGFloat(frameWidth), length: CGFloat(length), chamferRadius: 0.2)
        bottom.firstMaterial = material
        let bottomNode = SCNNode(geometry: bottom)
        bottomNode.position = SCNVector3(width / 2, frameWidth / 2, length / 2)
        rootNode.addChildNode(bottomNode)

        // Top
        let top = SCNBox(width: CGFloat(width), height: CGFloat(frameWidth), length: CGFloat(length), chamferRadius: 0.2)
        top.firstMaterial = material
        let topNode = SCNNode(geometry: top)
        topNode.position = SCNVector3(width / 2, height - frameWidth / 2, length / 2)
        rootNode.addChildNode(topNode)

        // Left
        let left = SCNBox(width: CGFloat(frameWidth), height: CGFloat(height - frameWidth * 2), length: CGFloat(length), chamferRadius: 0.2)
        left.firstMaterial = material
        let leftNode = SCNNode(geometry: left)
        leftNode.position = SCNVector3(frameWidth / 2, height / 2, length / 2)
        rootNode.addChildNode(leftNode)

        // Right
        let right = SCNBox(width: CGFloat(frameWidth), height: CGFloat(height - frameWidth * 2), length: CGFloat(length), chamferRadius: 0.2)
        right.firstMaterial = material
        let rightNode = SCNNode(geometry: right)
        rightNode.position = SCNVector3(width - frameWidth / 2, height / 2, length / 2)
        rootNode.addChildNode(rightNode)

        // Glass pane (transparent)
        let glassMaterial = SCNMaterial()
        glassMaterial.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.15)
        glassMaterial.transparency = 0.3
        glassMaterial.lightingModel = .physicallyBased
        glassMaterial.roughness.contents = 0.1
        glassMaterial.metalness.contents = 0.0

        let glass = SCNBox(
            width: CGFloat(width - frameWidth * 2),
            height: CGFloat(height - frameWidth * 2),
            length: CGFloat(length * 0.2),
            chamferRadius: 0.1
        )
        glass.firstMaterial = glassMaterial
        let glassNode = SCNNode(geometry: glass)
        glassNode.position = SCNVector3(width / 2, height / 2, length / 2)
        rootNode.addChildNode(glassNode)

        if showStuds {
            let studsNode = generateStuds(studsWide: piece.dimensions.studsWide, studsLong: piece.dimensions.studsLong, brickHeight: height, color: brickColor)
            rootNode.addChildNode(studsNode)
        }

        rootNode.name = "window"
        return rootNode
    }

    // MARK: - Utility

    /// Extract a number from a piece name (e.g. "Gear 40 Tooth" → 40)
    private static func extractNumber(from name: String) -> Int? {
        let pattern = #"(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range(at: 1), in: name) else {
            return nil
        }
        return Int(name[range])
    }
}
