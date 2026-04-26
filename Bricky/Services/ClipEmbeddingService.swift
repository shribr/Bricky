import Accelerate
import CoreML
import Foundation
import OSLog
import UIKit
import Vision

/// Runtime entry point for the LEGO-specific CLIP vision encoder.
///
/// Model: `Armaggheddon/clip-vit-base-patch32_lego-minifigure`
///   - Fine-tuned CLIP ViT-B/32 on 12,966 LEGO minifigure images
///   - 512-D L2-normalized embeddings
///
/// At scan time the pipeline calls `ClipEmbeddingService.shared
/// .nearestFigures(for: cgImage)` to get a ranked list of catalog
/// figure IDs whose CLIP embeddings are closest to the scanned image.
///
/// The CLIP model is LEGO-domain-specific (unlike DINOv2 which was
/// trained on ImageNet), so it produces embeddings with much better
/// discrimination between visually similar minifigures.
///
/// Failure modes (each becomes a graceful no-op returning `[]`):
///   - `LegoClipVision.mlmodelc` not bundled.
///   - `ClipEmbeddingIndex` not bundled.
///   - Vision request fails for the image.
final class ClipEmbeddingService {

    static let shared = ClipEmbeddingService()

    private static let logger = Logger(
        subsystem: "com.bricky.app",
        category: "ClipEmbeddingService"
    )

    private let visionModel: VNCoreMLModel?
    let isAvailable: Bool

    private init() {
        let model: VNCoreMLModel?

        // Try compiled model first (.mlmodelc), then mlpackage at runtime.
        if let url = Bundle.main.url(
                forResource: "LegoClipVision",
                withExtension: "mlmodelc"
            ) ?? Bundle.main.url(
                forResource: "LegoClipVision",
                withExtension: "mlmodelc",
                subdirectory: "LegoClipVision.mlpackage"
            ) {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all
                let coreModel = try MLModel(contentsOf: url, configuration: config)
                model = try VNCoreMLModel(for: coreModel)
                Self.logger.info("Loaded LegoClipVision.mlmodelc")
            } catch {
                Self.logger.error("Failed to load LegoClipVision: \(error.localizedDescription)")
                model = nil
            }
        } else if let rawURL = Bundle.main.url(
                forResource: "LegoClipVision",
                withExtension: "mlpackage"
            ) {
            // Runtime-compile the mlpackage
            do {
                let compiledURL = try MLModel.compileModel(at: rawURL)
                let config = MLModelConfiguration()
                config.computeUnits = .all
                let coreModel = try MLModel(contentsOf: compiledURL, configuration: config)
                model = try VNCoreMLModel(for: coreModel)
                Self.logger.info("Runtime-compiled and loaded LegoClipVision.mlpackage")
            } catch {
                Self.logger.error("Failed to runtime-compile LegoClipVision: \(error.localizedDescription)")
                model = nil
            }
        } else {
            Self.logger.info("LegoClipVision model not bundled — CLIP feature disabled")
            model = nil
        }

        self.visionModel = model
        self.isAvailable = (model != nil) && ClipEmbeddingIndex.shared.isAvailable
    }

    /// Embed the image and return the top-K nearest catalog figures.
    /// Returns `[]` if the feature is disabled or inference fails.
    func nearestFigures(for cgImage: CGImage, topK: Int = 16) async -> [ClipEmbeddingIndex.Hit] {
        await nearestFigures(for: [cgImage], topK: topK)
    }

    /// Embed multiple query crops and merge nearest-neighbor hits by each
    /// figure's best cosine. This is designed for live camera photos, where a
    /// single saliency crop can be too loose, too tight, or torso-only.
    func nearestFigures(for cgImages: [CGImage], topK: Int = 16) async -> [ClipEmbeddingIndex.Hit] {
        guard isAvailable, let visionModel else { return [] }
        let images = Array(cgImages.prefix(5))
        guard !images.isEmpty else { return [] }

        let embeddings: [[Float]] = await withTaskGroup(of: [Float]?.self) { group in
            for image in images {
                group.addTask(priority: .userInitiated) {
                    Self.runEncoder(visionModel: visionModel, image: image)
                }
            }

            var values: [[Float]] = []
            for await embedding in group {
                if let embedding { values.append(embedding) }
            }
            return values
        }

        let hitBatches = embeddings.map {
            ClipEmbeddingIndex.shared.nearestNeighbors(of: $0, topK: topK)
        }
        return Self.mergeHits(hitBatches, topK: topK)
    }

    static func mergeHits(
        _ hitBatches: [[ClipEmbeddingIndex.Hit]],
        topK: Int
    ) -> [ClipEmbeddingIndex.Hit] {
        guard topK > 0 else { return [] }
        var bestByFigure: [String: Float] = [:]
        for batch in hitBatches {
            for hit in batch {
                bestByFigure[hit.figureId] = max(bestByFigure[hit.figureId] ?? -.greatestFiniteMagnitude, hit.cosine)
            }
        }
        return bestByFigure
            .map { ClipEmbeddingIndex.Hit(figureId: $0.key, cosine: $0.value) }
            .sorted { $0.cosine > $1.cosine }
            .prefix(topK)
            .map { $0 }
    }

    /// Run the CLIP vision encoder and return the L2-normalized 512-D embedding.
    private static func runEncoder(visionModel: VNCoreMLModel, image: CGImage) -> [Float]? {
        let request = VNCoreMLRequest(model: visionModel)
        // CLIP expects 224×224 center-cropped input.
        request.imageCropAndScaleOption = .centerCrop
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Self.logger.error("CLIP VNCoreMLRequest failed: \(error.localizedDescription)")
            return nil
        }

        guard let obs = (request.results?.first as? VNCoreMLFeatureValueObservation),
              let array = obs.featureValue.multiArrayValue else {
            return nil
        }

        let count = array.count
        var out = [Float](repeating: 0, count: count)

        switch array.dataType {
        case .float16:
            let ptr = array.dataPointer.bindMemory(to: Float16.self, capacity: count)
            for i in 0..<count { out[i] = Float(ptr[i]) }
        default:
            let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: count)
            for i in 0..<count { out[i] = ptr[i] }
        }

        // Safety re-normalization to unit sphere.
        var norm: Float = 0
        vDSP_dotpr(out, 1, out, 1, &norm, vDSP_Length(count))
        norm = max(sqrt(norm), 1e-8)
        if abs(norm - 1.0) > 1e-3 {
            var scale = 1.0 / norm
            vDSP_vsmul(out, 1, &scale, &out, 1, vDSP_Length(count))
        }
        return out
    }
}
