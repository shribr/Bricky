import Foundation
import SceneKit

/// Builds an `SCNNode` from parsed LDraw records, recursively resolving
/// sub-file references via a provided file loader.
///
/// LDraw uses a left-handed coordinate system with **Y pointing down**.
/// We flip Y on output so the model is right-side-up in SceneKit.
///
/// LDraw uses LDU (LDraw Units) where 1 LDU = 0.4mm. We scale to mm
/// to match the rest of `BrickGeometryGenerator`.
final class LDrawGeometryBuilder {

    /// 1 LDU = 0.4 mm
    private static let lduToMM: Float = 0.4

    /// Closure that returns the parsed records for a given sub-file name
    /// (e.g. "stud.dat", "4-4cyli.dat", "3001.dat"). Returns nil if missing.
    typealias FileResolver = (String) -> [LDrawParser.Record]?

    private let resolver: FileResolver
    private var triangles: [Triangle] = []
    /// Maximum recursion depth to guard against malformed/cyclic libraries
    private let maxDepth = 50

    init(resolver: @escaping FileResolver) {
        self.resolver = resolver
    }

    // MARK: - Public

    /// Build an SCNNode from a top-level part's records.
    /// - Parameters:
    ///   - records: parsed records of the part file
    ///   - inheritedColorCode: the color to substitute for code 16 (inherit)
    /// - Returns: an SCNNode with combined geometry per color
    func buildNode(records: [LDrawParser.Record], inheritedColorCode: Int) -> SCNNode {
        triangles.removeAll(keepingCapacity: true)
        flatten(records: records,
                transform: .identity,
                inheritedColor: inheritedColorCode,
                invertWinding: false,
                depth: 0)

        // Apply LDU → mm scale and flip Y axis (LDraw Y points down)
        let scale = LDrawGeometryBuilder.lduToMM
        let scaled = triangles.map { tri -> Triangle in
            Triangle(
                v1: SCNVector3(tri.v1.x * scale, -tri.v1.y * scale, tri.v1.z * scale),
                v2: SCNVector3(tri.v2.x * scale, -tri.v2.y * scale, tri.v2.z * scale),
                v3: SCNVector3(tri.v3.x * scale, -tri.v3.y * scale, tri.v3.z * scale),
                color: tri.color
            )
        }

        return makeNode(from: scaled)
    }

    // MARK: - Flatten

    private struct Triangle {
        let v1: SCNVector3
        let v2: SCNVector3
        let v3: SCNVector3
        let color: Int
    }

    private func flatten(records: [LDrawParser.Record],
                         transform: LDrawParser.Transform,
                         inheritedColor: Int,
                         invertWinding: Bool,
                         depth: Int) {
        guard depth < maxDepth else { return }

        var pendingInvert = false  // BFC INVERTNEXT applies to the very next subfile
        let detNeg = transform.determinant < 0
        // Mirroring transform also flips winding
        let baseInvert = invertWinding != detNeg

        for record in records {
            switch record {
            case .bfcCommand(let invertNext, _):
                if invertNext { pendingInvert.toggle() }

            case .subfile(let colorCode, let subTransform, let fileName):
                guard let subRecords = resolver(fileName) else {
                    pendingInvert = false
                    continue
                }
                let combined = transform.multiplied(by: subTransform)
                let nextColor = colorCode == LDrawColorMap.inheritColorCode ? inheritedColor : colorCode
                let nextInvert = baseInvert != pendingInvert
                flatten(records: subRecords,
                        transform: combined,
                        inheritedColor: nextColor,
                        invertWinding: nextInvert,
                        depth: depth + 1)
                pendingInvert = false

            case .triangle(let colorCode, let v1, let v2, let v3):
                let resolvedColor = colorCode == LDrawColorMap.inheritColorCode ? inheritedColor : colorCode
                let p1 = transform.apply(v1)
                let p2 = transform.apply(v2)
                let p3 = transform.apply(v3)
                if baseInvert {
                    triangles.append(Triangle(v1: p1, v2: p3, v3: p2, color: resolvedColor))
                } else {
                    triangles.append(Triangle(v1: p1, v2: p2, v3: p3, color: resolvedColor))
                }

            case .quad(let colorCode, let v1, let v2, let v3, let v4):
                let resolvedColor = colorCode == LDrawColorMap.inheritColorCode ? inheritedColor : colorCode
                let p1 = transform.apply(v1)
                let p2 = transform.apply(v2)
                let p3 = transform.apply(v3)
                let p4 = transform.apply(v4)
                // Split quad into two triangles: (p1,p2,p3) and (p1,p3,p4)
                if baseInvert {
                    triangles.append(Triangle(v1: p1, v2: p3, v3: p2, color: resolvedColor))
                    triangles.append(Triangle(v1: p1, v2: p4, v3: p3, color: resolvedColor))
                } else {
                    triangles.append(Triangle(v1: p1, v2: p2, v3: p3, color: resolvedColor))
                    triangles.append(Triangle(v1: p1, v2: p3, v3: p4, color: resolvedColor))
                }
            }
        }
    }

    // MARK: - SceneKit geometry assembly

    private func makeNode(from tris: [Triangle]) -> SCNNode {
        let rootNode = SCNNode()
        rootNode.name = "ldraw_part"
        if tris.isEmpty { return rootNode }

        // Group triangles by color
        var byColor: [Int: [Triangle]] = [:]
        for t in tris {
            byColor[t.color, default: []].append(t)
        }

        for (colorCode, group) in byColor {
            let geometry = makeGeometry(for: group, colorCode: colorCode)
            let node = SCNNode(geometry: geometry)
            rootNode.addChildNode(node)
        }

        return rootNode
    }

    private func makeGeometry(for tris: [Triangle], colorCode: Int) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        vertices.reserveCapacity(tris.count * 3)
        normals.reserveCapacity(tris.count * 3)

        for t in tris {
            let n = faceNormal(t.v1, t.v2, t.v3)
            vertices.append(t.v1); vertices.append(t.v2); vertices.append(t.v3)
            normals.append(n); normals.append(n); normals.append(n)
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)

        // Index buffer: 0,1,2,3,4,5,...
        let indices: [Int32] = (0..<Int32(vertices.count)).map { $0 }
        let data = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
            data: data,
            primitiveType: .triangles,
            primitiveCount: tris.count,
            bytesPerIndex: MemoryLayout<Int32>.size
        )

        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
        geometry.firstMaterial = makeMaterial(colorCode: colorCode)
        return geometry
    }

    private func faceNormal(_ a: SCNVector3, _ b: SCNVector3, _ c: SCNVector3) -> SCNVector3 {
        let ux = b.x - a.x, uy = b.y - a.y, uz = b.z - a.z
        let vx = c.x - a.x, vy = c.y - a.y, vz = c.z - a.z
        var nx = uy * vz - uz * vy
        var ny = uz * vx - ux * vz
        var nz = ux * vy - uy * vx
        let len = sqrt(nx * nx + ny * ny + nz * nz)
        if len > 0 {
            nx /= len; ny /= len; nz /= len
        }
        return SCNVector3(nx, ny, nz)
    }

    private func makeMaterial(colorCode: Int) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = LDrawColorMap.uiColor(for: colorCode)
        material.specular.contents = UIColor.white
        material.shininess = 0.4
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.3
        material.metalness.contents = 0.0
        material.isDoubleSided = true  // Some LDraw parts rely on this
        return material
    }
}
