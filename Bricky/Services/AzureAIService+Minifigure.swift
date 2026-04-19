import Foundation
import UIKit

// MARK: - Minifigure identification

extension AzureAIService {

    struct MinifigureCandidate: Codable {
        let figId: String
        let name: String
        let confidence: Double
        let reasoning: String
    }

    /// Identify a minifigure from a torso image using the configured cloud
    /// vision model. Returns up to 3 ranked candidates.
    ///
    /// The model is asked to return the Rebrickable / BrickLink fig id where
    /// known; the local catalog resolver then maps the result to a `Minifigure`.
    func identifyMinifigure(torsoImage: UIImage) async throws -> [MinifigureCandidate] {
        guard AzureConfiguration.shared.canUseOnlineMode else {
            throw AzureAIError.notConfigured
        }

        let endpoint = AzureConfiguration.shared.openAIEndpoint
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let deployment = AzureConfiguration.shared.openAIDeployment
        guard let url = URL(string: "\(endpoint)/openai/deployments/\(deployment)/chat/completions?api-version=2024-10-21") else {
            throw AzureAIError.invalidEndpoint
        }

        guard let imageData = compressImageForUpload(torsoImage) else {
            throw AzureAIError.imageProcessingFailed
        }
        let base64 = imageData.base64EncodedString()

        let systemPrompt = """
        You are an expert on LEGO minifigures. The user has uploaded a photo
        of a single LEGO minifigure torso. Identify which minifigure it
        belongs to.

        Return up to 3 candidates ranked by confidence. Respond with ONLY a
        JSON object in this shape — no markdown fences, no explanation:

        {
          "candidates": [
            {
              "figId": "fig-001234",
              "name": "Classic Spaceman, White",
              "confidence": 0.0..1.0,
              "reasoning": "short reason"
            }
          ]
        }

        Use Rebrickable / BrickLink fig ids when you know them
        (e.g. "fig-001234", "sw0001a", "cas123"). If you don't know the id,
        leave figId empty and provide the most descriptive minifigure name
        you can. Always include confidence and reasoning. If you cannot
        identify it at all, return an empty candidates array.
        """

        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    ["type": "text", "text": "Identify this minifigure from its torso. Return JSON."],
                    ["type": "image_url", "image_url": [
                        "url": "data:image/jpeg;base64,\(base64)",
                        // "low" detail uses a 512x512 tile (1 tile = 85 tokens)
                        // instead of the ~765 tokens/tile a "high" image uses.
                        // Roughly 3-4x faster at acceptable accuracy for torso ID.
                        "detail": "low"
                    ]]
                ]]
            ],
            "max_tokens": 600,
            "temperature": 0.2
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw AzureAIError.parseError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AzureConfiguration.shared.openAIKey, forHTTPHeaderField: "api-key")
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AzureAIError.networkError("Invalid response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AzureAIError.apiError(http.statusCode, body)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AzureAIError.parseError
        }

        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        struct Envelope: Decodable {
            let candidates: [MinifigureCandidate]
        }

        guard let payload = cleaned.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: payload) else {
            throw AzureAIError.parseError
        }

        return envelope.candidates
    }

    /// Local image-prep helper (mirrors the private one in the main file).
    private func compressImageForUpload(_ image: UIImage, maxBytes: Int = 1_500_000) -> Data? {
        let maxDimension: CGFloat = 1024
        var target = image
        if max(image.size.width, image.size.height) > maxDimension {
            let scale = maxDimension / max(image.size.width, image.size.height)
            let newSize = CGSize(width: image.size.width * scale,
                                  height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            target = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
        for quality in stride(from: 0.9, through: 0.1, by: -0.1) {
            if let data = target.jpegData(compressionQuality: quality),
               data.count <= maxBytes {
                return data
            }
        }
        return target.jpegData(compressionQuality: 0.1)
    }
}
