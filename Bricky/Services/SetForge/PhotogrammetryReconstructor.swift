import Foundation
import UIKit

#if canImport(RealityKit) && !targetEnvironment(simulator)
import RealityKit
#endif

/// Reconstructs a `.usdz` 3D model from a set of angle photos using on-device
/// **PhotogrammetrySession**, so a multi-angle / walk-around scan becomes a
/// genuine 3D mesh (fed to `MeshVoxelizer`) instead of a flat single-photo
/// relief. Device-only: PhotogrammetrySession isn't in the simulator SDK and
/// needs a capable device, so unsupported environments return `nil` and callers
/// fall back to the relief path.
enum PhotogrammetryReconstructor {

    /// Whether on-device photogrammetry can run here.
    static var isSupported: Bool {
        #if canImport(RealityKit) && !targetEnvironment(simulator)
        if #available(iOS 17.0, *) { return PhotogrammetrySession.isSupported }
        #endif
        return false
    }

    /// Reconstruct a model from the given photos. Returns the output `.usdz` URL,
    /// or `nil` when unsupported, given too few images, or reconstruction fails.
    static func reconstruct(images: [UIImage]) async -> URL? {
        // Photogrammetry needs several overlapping views; below this it will
        // never produce a usable mesh, so don't bother spinning it up.
        guard images.count >= 3 else { return nil }
        #if canImport(RealityKit) && !targetEnvironment(simulator)
        if #available(iOS 17.0, *), PhotogrammetrySession.isSupported {
            return await reconstructOnDevice(images: images)
        }
        #endif
        return nil
    }

    #if canImport(RealityKit) && !targetEnvironment(simulator)
    @available(iOS 17.0, *)
    private static func reconstructOnDevice(images: [UIImage]) async -> URL? {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("photogrammetry_\(UUID().uuidString)", isDirectory: true)
        let imagesDir = root.appendingPathComponent("images", isDirectory: true)
        let output = root.appendingPathComponent("model.usdz")
        do {
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            for (index, image) in images.enumerated() {
                guard let data = image.jpegData(compressionQuality: 0.9) else { continue }
                try data.write(to: imagesDir.appendingPathComponent(String(format: "img_%03d.jpg", index)))
            }
            let session = try PhotogrammetrySession(input: imagesDir)
            try session.process(requests: [.modelFile(url: output, detail: .reduced)])
            for try await result in session.outputs {
                switch result {
                case .processingComplete:
                    return FileManager.default.fileExists(atPath: output.path) ? output : nil
                case .requestError, .processingCancelled:
                    return nil
                default:
                    continue
                }
            }
            return nil
        } catch {
            return nil
        }
    }
    #endif
}
