import SceneKit
import ModelIO
import SceneKit.ModelIO
import Foundation

/// Exports SceneKit nodes to STL files for 3D printing.
/// Uses ModelIO framework to convert SCNScene to binary STL format.
final class STLExporter {

    enum ExportError: LocalizedError {
        case emptyScene
        case exportFailed(String)
        case fileWriteFailed

        var errorDescription: String? {
            switch self {
            case .emptyScene:
                return "Cannot export an empty scene."
            case .exportFailed(let reason):
                return "STL export failed: \(reason)"
            case .fileWriteFailed:
                return "Failed to write STL file to disk."
            }
        }
    }

    // MARK: - Public API

    /// Export a SceneKit node to an STL file
    /// - Parameters:
    ///   - node: The root SCNNode containing the 3D model
    ///   - fileName: Base filename (without extension)
    ///   - scale: Scale factor (default 1.0 = millimeters, matching BrickGeometryGenerator)
    /// - Returns: URL of the exported STL file in the Documents directory
    static func exportToSTL(
        node: SCNNode,
        fileName: String,
        scale: Float = 1.0
    ) throws -> URL {
        guard node.childNodes.count > 0 || node.geometry != nil else {
            throw ExportError.emptyScene
        }

        // Create a temporary scene containing the node
        let scene = SCNScene()
        let clonedNode = node.clone()

        // Apply scale if needed
        if scale != 1.0 {
            clonedNode.scale = SCNVector3(scale, scale, scale)
        }

        scene.rootNode.addChildNode(clonedNode)

        // Convert to MDLAsset via ModelIO
        let asset = MDLAsset(scnScene: scene)

        // Generate output URL
        let outputURL = documentsURL(for: fileName, extension: "stl")

        // Export as STL
        do {
            try asset.export(to: outputURL)
        } catch {
            throw ExportError.exportFailed(error.localizedDescription)
        }

        // Verify the file was written
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ExportError.fileWriteFailed
        }

        return outputURL
    }

    /// Export multiple parts as separate STL files (for multi-part prints)
    /// - Parameters:
    ///   - nodes: Array of (node, partName) tuples
    ///   - baseName: Base name for the file group
    ///   - scale: Scale factor
    /// - Returns: Array of URLs of exported STL files
    static func exportMultiPart(
        nodes: [(SCNNode, String)],
        baseName: String,
        scale: Float = 1.0
    ) throws -> [URL] {
        var urls: [URL] = []
        for (node, partName) in nodes {
            let fileName = "\(baseName)_\(partName)"
            let url = try exportToSTL(node: node, fileName: fileName, scale: scale)
            urls.append(url)
        }
        return urls
    }

    /// Get the file size of an exported STL in a human-readable format
    static func fileSizeString(for url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return "Unknown"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Estimate the STL file size for a brick (rough approximation)
    /// Each triangle in STL binary = 50 bytes. A brick with studs has roughly:
    /// - Body: ~12 triangles per box face = ~12 per face × 6 faces = 72
    /// - Per stud: ~48 triangles (cylinder)
    /// - Per tube: ~96 triangles (two cylinders)
    static func estimatedFileSize(
        studsWide: Int,
        studsLong: Int,
        heightUnits: Int,
        hollow: Bool
    ) -> Int {
        let studCount = studsWide * studsLong
        let tubeCount = max(0, (studsWide - 1) * (studsLong - 1))

        let bodyTriangles = hollow ? 72 * 6 : 12 // 6 boxes for hollow shell vs 1 solid
        let studTriangles = studCount * 48
        let tubeTriangles = tubeCount * 96

        let totalTriangles = bodyTriangles + studTriangles + tubeTriangles
        let headerBytes = 84 // STL binary header
        let triangleBytes = totalTriangles * 50

        return headerBytes + triangleBytes
    }

    // MARK: - Print Settings

    /// Recommended 3D print settings for LEGO-scale pieces
    struct PrintSettings {
        let layerHeight: String
        let infill: String
        let supports: Bool
        let material: String
        let notes: String
    }

    /// Get recommended print settings based on piece characteristics
    static func recommendedSettings(
        studsWide: Int,
        studsLong: Int,
        heightUnits: Int
    ) -> PrintSettings {
        let isSmall = studsWide <= 2 && studsLong <= 2
        let isTall = heightUnits > 3

        return PrintSettings(
            layerHeight: isSmall ? "0.12mm" : "0.16mm",
            infill: "20%",
            supports: isTall,
            material: "PLA or ABS",
            notes: isSmall
                ? "Use fine layer height for stud detail. Ensure bed adhesion for small footprint."
                : isTall
                    ? "Enable supports for overhangs. Consider printing in orientation with largest face down."
                    : "Standard settings work well. Orient with studs facing up for best quality."
        )
    }

    // MARK: - Helpers

    private static func documentsURL(for fileName: String, extension ext: String) -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let stlDir = documentsDir.appendingPathComponent("STL Exports", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: stlDir, withIntermediateDirectories: true)

        // Sanitize filename
        let sanitized = fileName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return stlDir.appendingPathComponent("\(sanitized).\(ext)")
    }

    /// List all previously exported STL files
    static func listExports() -> [URL] {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let stlDir = documentsDir.appendingPathComponent("STL Exports", isDirectory: true)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: stlDir,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return files.filter { $0.pathExtension.lowercased() == "stl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Delete an exported STL file
    static func deleteExport(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
