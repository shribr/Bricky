import CoreML
import Foundation
import OSLog
import UIKit
import Vision

/// Runtime entry point for the trained face-region embedding model.
///
/// Parallel to `TorsoEmbeddingService` but operates on the face
/// band (17–35% of the figure image — below the hairline, above the
/// neck). Used by the identification cascade to boost candidates with
/// matching face prints and by the `HybridFigureAnalyzer` to detect
/// face-swapped figures.
///
/// Graceful no-op (returns `[]`) when artifacts aren't bundled.
final class FaceEmbeddingService {

    static let shared = FaceEmbeddingService()

    private static let logger = Logger(
        subsystem: "com.bricky.app",
        category: "FaceEmbeddingService"
    )

    private let visionModel: VNCoreMLModel?
    let isAvailable: Bool

    private init() {
        let model: VNCoreMLModel?
        // Try compiled model first (.mlmodelc), then fall back to runtime
        // compilation of raw .mlmodel (needed when model is inside a folder
        // reference and Xcode didn't compile it at build time).
        if let url = Bundle.main.url(
                forResource: "FaceEncoder",
                withExtension: "mlmodelc",
                subdirectory: "FaceEmbeddings"
            ) ?? Bundle.main.url(forResource: "FaceEncoder", withExtension: "mlmodelc") {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all
                let coreModel = try MLModel(contentsOf: url, configuration: config)
                model = try VNCoreMLModel(for: coreModel)
                Self.logger.info("Loaded FaceEncoder.mlmodelc")
            } catch {
                Self.logger.error("Failed to load FaceEncoder: \(error.localizedDescription)")
                model = nil
            }
        } else if let rawURL = Bundle.main.url(
                forResource: "FaceEncoder",
                withExtension: "mlmodel",
                subdirectory: "FaceEmbeddings"
            ) ?? Bundle.main.url(forResource: "FaceEncoder", withExtension: "mlmodel") {
            // Runtime-compile the raw .mlmodel → temporary .mlmodelc
            do {
                let compiledURL = try MLModel.compileModel(at: rawURL)
                let config = MLModelConfiguration()
                config.computeUnits = .all
                let coreModel = try MLModel(contentsOf: compiledURL, configuration: config)
                model = try VNCoreMLModel(for: coreModel)
                Self.logger.info("Runtime-compiled and loaded FaceEncoder.mlmodel")
            } catch {
                Self.logger.error("Failed to runtime-compile FaceEncoder: \(error.localizedDescription)")
                model = nil
            }
        } else {
            Self.logger.info("FaceEncoder model not bundled — feature disabled")
            model = nil
        }
        self.visionModel = model
        self.isAvailable = (model != nil) && FaceEmbeddingIndex.shared.isAvailable
    }

    func nearestFigures(for cgImage: CGImage, topK: Int = 16) async -> [FaceEmbeddingIndex.Hit] {
        guard isAvailable, let visionModel else { return [] }

        let embedding: [Float]? = await Task.detached(priority: .userInitiated) {
            Self.runEncoder(visionModel: visionModel, image: cgImage)
        }.value
        guard let embedding else { return [] }

        return FaceEmbeddingIndex.shared.nearestNeighbors(of: embedding, topK: topK)
    }

    /// Encode a head crop and return the raw embedding vector.
    /// Used by `HybridFigureAnalyzer` for per-region attribution.
    func encode(cgImage: CGImage) async -> [Float]? {
        guard isAvailable, let visionModel else { return nil }
        return await Task.detached(priority: .userInitiated) {
            Self.runEncoder(visionModel: visionModel, image: cgImage)
        }.value
    }

    private static func runEncoder(visionModel: VNCoreMLModel, image: CGImage) -> [Float]? {
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .centerCrop
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Self.logger.error("VNCoreMLRequest failed: \(error.localizedDescription)")
            return nil
        }

        guard let obs = (request.results?.first as? VNCoreMLFeatureValueObservation),
              let array = obs.featureValue.multiArrayValue else {
            return nil
        }

        let count = array.count
        var out = [Float](repeating: 0, count: count)

        // CoreML mlprogram models (DINOv2) output Float16; older
        // neuralnetwork models output Float32. Handle both.
        switch array.dataType {
        case .float16:
            let ptr = array.dataPointer.bindMemory(to: Float16.self, capacity: count)
            for i in 0..<count { out[i] = Float(ptr[i]) }
        default:
            let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: count)
            for i in 0..<count { out[i] = ptr[i] }
        }

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
