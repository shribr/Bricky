import Foundation
import SceneKit

/// Parses LDraw .dat file content into typed records.
/// Reference: https://www.ldraw.org/article/218.html
///
/// LDraw line types:
/// - 0: Comment / meta-command
/// - 1: Sub-file reference (with transformation matrix)
/// - 2: Line (2 vertices)
/// - 3: Triangle (3 vertices)
/// - 4: Quadrilateral (4 vertices)
/// - 5: Optional line (4 vertices, ignored for solid rendering)
enum LDrawParser {

    // MARK: - Record Types

    /// A 4×4 transformation matrix, expressed as the LDraw form:
    /// `x y z a b c d e f g h i` where translation is (x,y,z)
    /// and the 3×3 rotation/scale is:
    ///     [a b c]
    ///     [d e f]
    ///     [g h i]
    struct Transform {
        var x: Float = 0
        var y: Float = 0
        var z: Float = 0
        var a: Float = 1, b: Float = 0, c: Float = 0
        var d: Float = 0, e: Float = 1, f: Float = 0
        var g: Float = 0, h: Float = 0, i: Float = 1

        static let identity = Transform()

        /// Apply this transform to a vertex (matrix × vector + translation)
        func apply(_ v: SCNVector3) -> SCNVector3 {
            SCNVector3(
                a * v.x + b * v.y + c * v.z + x,
                d * v.x + e * v.y + f * v.z + y,
                g * v.x + h * v.y + i * v.z + z
            )
        }

        /// Combine with another transform: result = self * other
        func multiplied(by other: Transform) -> Transform {
            var r = Transform()
            r.a = a * other.a + b * other.d + c * other.g
            r.b = a * other.b + b * other.e + c * other.h
            r.c = a * other.c + b * other.f + c * other.i
            r.d = d * other.a + e * other.d + f * other.g
            r.e = d * other.b + e * other.e + f * other.h
            r.f = d * other.c + e * other.f + f * other.i
            r.g = g * other.a + h * other.d + i * other.g
            r.h = g * other.b + h * other.e + i * other.h
            r.i = g * other.c + h * other.f + i * other.i
            r.x = a * other.x + b * other.y + c * other.z + x
            r.y = d * other.x + e * other.y + f * other.z + y
            r.z = g * other.x + h * other.y + i * other.z + z
            return r
        }

        /// Determinant of the 3×3 rotation/scale portion.
        /// Negative = mirrored (need to flip winding order for BFC).
        var determinant: Float {
            a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        }
    }

    enum Record {
        case subfile(colorCode: Int, transform: Transform, fileName: String)
        case triangle(colorCode: Int, v1: SCNVector3, v2: SCNVector3, v3: SCNVector3)
        case quad(colorCode: Int, v1: SCNVector3, v2: SCNVector3, v3: SCNVector3, v4: SCNVector3)
        case bfcCommand(invertNext: Bool, ccw: Bool?)
    }

    // MARK: - Parsing

    /// Parse a complete .dat file content into records.
    static func parse(_ content: String) -> [Record] {
        var records: [Record] = []
        // Split on newlines via CharacterSet, which operates at the unicode
        // scalar level. Swift treats "\r\n" as a SINGLE grapheme cluster, so
        // splitting on Character "\n" or "\r" silently fails for CRLF files
        // (and most LDraw .dat files use CRLF).
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let typeStr = tokens.first, let type = Int(typeStr) else { continue }

            switch type {
            case 0:
                if let bfc = parseBFC(tokens: tokens) {
                    records.append(bfc)
                }
            case 1:
                if let r = parseSubfile(tokens: tokens) {
                    records.append(r)
                }
            case 3:
                if let r = parseTriangle(tokens: tokens) {
                    records.append(r)
                }
            case 4:
                if let r = parseQuad(tokens: tokens) {
                    records.append(r)
                }
            default:
                break  // ignore lines (type 2) and optional lines (type 5)
            }
        }
        return records
    }

    // MARK: - Per-line parsers

    private static func parseSubfile(tokens: [String]) -> Record? {
        // 1 <color> x y z a b c d e f g h i <file>
        guard tokens.count >= 15 else { return nil }
        guard let color = Int(tokens[1]),
              let x = Float(tokens[2]), let y = Float(tokens[3]), let z = Float(tokens[4]),
              let a = Float(tokens[5]), let b = Float(tokens[6]), let c = Float(tokens[7]),
              let d = Float(tokens[8]), let e = Float(tokens[9]), let f = Float(tokens[10]),
              let g = Float(tokens[11]), let h = Float(tokens[12]), let i = Float(tokens[13]) else {
            return nil
        }
        // Filename can contain spaces — rejoin everything from index 14 onward.
        // LDraw uses Windows-style backslash separators (e.g. `s\3649s01.dat`,
        // `48\1-4cyli.dat`) — normalize to forward slash so downstream path
        // operations like `lastPathComponent` work correctly.
        let raw = tokens[14...].joined(separator: " ").lowercased()
        let fileName = raw.replacingOccurrences(of: "\\", with: "/")
        var t = Transform()
        t.x = x; t.y = y; t.z = z
        t.a = a; t.b = b; t.c = c
        t.d = d; t.e = e; t.f = f
        t.g = g; t.h = h; t.i = i
        return .subfile(colorCode: color, transform: t, fileName: fileName)
    }

    private static func parseTriangle(tokens: [String]) -> Record? {
        // 3 <color> x1 y1 z1 x2 y2 z2 x3 y3 z3
        guard tokens.count >= 11 else { return nil }
        guard let color = Int(tokens[1]),
              let v1 = vec(tokens, 2),
              let v2 = vec(tokens, 5),
              let v3 = vec(tokens, 8) else {
            return nil
        }
        return .triangle(colorCode: color, v1: v1, v2: v2, v3: v3)
    }

    private static func parseQuad(tokens: [String]) -> Record? {
        // 4 <color> x1 y1 z1 x2 y2 z2 x3 y3 z3 x4 y4 z4
        guard tokens.count >= 14 else { return nil }
        guard let color = Int(tokens[1]),
              let v1 = vec(tokens, 2),
              let v2 = vec(tokens, 5),
              let v3 = vec(tokens, 8),
              let v4 = vec(tokens, 11) else {
            return nil
        }
        return .quad(colorCode: color, v1: v1, v2: v2, v3: v3, v4: v4)
    }

    /// Parse BFC (Back-Face Culling) meta-commands.
    /// Examples:
    ///   0 BFC INVERTNEXT
    ///   0 BFC CCW
    ///   0 BFC CW
    ///   0 BFC NOCERTIFY
    private static func parseBFC(tokens: [String]) -> Record? {
        guard tokens.count >= 2, tokens[1].uppercased() == "BFC" else { return nil }
        var invertNext = false
        var ccw: Bool?
        for t in tokens.dropFirst(2) {
            switch t.uppercased() {
            case "INVERTNEXT": invertNext = true
            case "CCW": ccw = true
            case "CW": ccw = false
            default: break
            }
        }
        if invertNext || ccw != nil {
            return .bfcCommand(invertNext: invertNext, ccw: ccw)
        }
        return nil
    }

    private static func vec(_ tokens: [String], _ start: Int) -> SCNVector3? {
        guard tokens.count > start + 2,
              let x = Float(tokens[start]),
              let y = Float(tokens[start + 1]),
              let z = Float(tokens[start + 2]) else {
            return nil
        }
        return SCNVector3(x, y, z)
    }
}
