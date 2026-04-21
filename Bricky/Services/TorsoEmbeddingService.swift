import CoreML
import Foundation
import OSLog
import UIKit
import Vision

/// Runtime entry point for the trained torso-embedding model.
///
/// At scan time the cascade calls `TorsoEmbeddingService.shared
/// .nearestFigures(for: torsoBandImage)` to get a ranked list of
/// catalog figure IDs whose torso prints are visually closest to what
/// the camera sees. The result is then merged with the color cascade's
/// candidates so Phase 2 can confirm them.
///
/// Failure modes (each becomes a graceful no-op returning `[]`):
///   • `TorsoEncoder.mlmodel` not bundled (training pipeline not run yet).
///   • `TorsoEmbeddingIndex` not bundled.
///   • Vision request fails for the image.
///
/// All paths log once and then stay quiet so a missing model doesn't
/// spam the console during normal use.
final class TorsoEmbeddingService {

    static let shared = TorsoEmbeddingService()

    private static let logger = Logger(
        subsystem: "com.bricky.app",
        category: "TorsoEmbeddingService"
    )

    /// Lazy-loaded CoreML model. `nil` if the bundle doesn't ship one.
    private let visionModel: VNCoreMLModel?

    /// True when the encoder model AND the bundled vector index are
    /// both available. Other values (only one of them present) also
    /// resolve to `false` since cosine-NN needs both halves.
    let isAvailable: Bool

    private init() {
        let model: VNCoreMLModel?
        if let url = Bundle.main.url(
                forResource: "TorsoEncoder",
                withExtension: "mlmodelc",
                subdirectory: "TorsoEmbeddings"
            ) ?? Bundle.main.url(forResource: "TorsoEncoder", withExtension: "mlmodelc") {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all
                let coreModel = try MLModel(contentsOf: url, configuration: config)
                model = try VNCoreMLModel(for: coreModel)
                Self.logger.info("Loaded TorsoEncoder.mlmodelc")
            } catch {
                Self.logger.error("Failed to load TorsoEncoder: \(error.localizedDescription)")
                model = nil
            }
        } else {
            Self.logger.info("TorsoEncoder.mlmodelc not bundled — feature disabled")
            model = nil
        }
        self.visionModel = model
        self.isAvailable = (model != nil) && TorsoEmbeddingIndex.shared.isAvailable
    }

    /// Embed the torso-band crop and return the top-K nearest catalog
    /// figures by cosine similarity. Returns `[]` if the feature is
    /// disabled or the encoder fails — caller MUST handle that path
    /// without surfacing an error to the user.
    func nearestFigures(for cgImage: CGImage, topK: Int = 16) async -> [TorsoEmbeddingIndex.Hit] {
        guard isAvailable, let visionModel else { return [] }

        let embedding: [Float]? = await Task.detached(priority: .userInitiated) {
            Self.runEncoder(visionModel: visionModel, image: cgImage)
        }.value
        guard let embedding else { return [] }

        return TorsoEmbeddingIndex.shared.nearestNeighbors(of: embedding, topK: topK)
    }

    /// Synchronous body of the encoder pass — separated so the public
    /// API stays `async` while the actual Vision call runs on a
    /// detached task.
    private static func runEncoder(visionModel: VNCoreMLModel, image: CGImage) -> [Float]? {
        let request = VNCoreMLRequest(model: visionModel)
        // The encoder was trained on letterboxed 224×224 inputs, but
        // the iOS-side preprocessing uses Vision's image cropping which
        // is `centerCrop` by default. `scaleFill` matches the Python
        // padding more closely on near-square torso bands.
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Self.logger.error("VNCoreMLRequest failed: \(error.localizedDescription)")
            return nil
        }

        // The exported model has a single tensor output named
        // "embedding" (see convert-torso-encoder-coreml.py). Vision
        // surfaces it as a `VNCoreMLFeatureValueObservation`.
        guard let obs = (request.results?.first as? VNCoreMLFeatureValueObservation),
              let array = obs.featureValue.multiArrayValue else {
            return nil
        }

        let count = array.count
        var out = [Float](repeating: 0, count: count)
        let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: count)
        for i in 0..<count { out[i] = ptr[i] }

        // Safety re-normalization: if the CoreML output isn't quite
        // unit-length (float precision, neuralnetwork-format rounding),
        // force it back to the unit sphere so dot-product == cosine.
        var norm: Float = 0
        for v in out { norm += v * v }
        norm = max(sqrt(norm), 1e-8)
        if abs(norm - 1.0) > 1e-3 {
            for i in 0..<count { out[i] /= norm }
        }
        return out
    }
}
