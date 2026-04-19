import Foundation
import UIKit

/// Azure AI integration: Computer Vision image analysis + GPT-4o vision
/// for cloud-enhanced brick recognition. Falls back to offline pipeline
/// when unavailable.
final class AzureAIService {
    static let shared = AzureAIService()

    struct CloudBrickResult: Codable {
        let partNumber: String
        let name: String
        let category: String
        let color: String
        let confidence: Float
        let studsWide: Int
        let studsLong: Int
    }

    struct CloudAnalysisResponse {
        let bricks: [CloudBrickResult]
        let rawDescription: String
        let processingTime: TimeInterval
    }

    private let config = AzureConfiguration.shared
    private let catalog = LegoPartsCatalog.shared
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Analyze image with Azure Computer Vision + GPT-4o vision
    func analyzeImage(_ image: UIImage) async throws -> CloudAnalysisResponse {
        guard config.canUseOnlineMode else {
            throw AzureAIError.notConfigured
        }

        let startTime = Date()

        // Step 1: Get image description from Computer Vision
        let description = try await computerVisionAnalysis(image)

        // Step 2: Send to GPT-4o with vision for structured brick identification
        let bricks = try await gptVisionAnalysis(image, context: description)

        let elapsed = Date().timeIntervalSince(startTime)

        return CloudAnalysisResponse(
            bricks: bricks,
            rawDescription: description,
            processingTime: elapsed
        )
    }

    // MARK: - AI Build Ideas

    struct AIBuildIdea: Identifiable, Codable {
        let id: UUID
        let name: String
        let description: String
        let difficulty: String
        let category: String
        let estimatedMinutes: Int
        let requiredPieces: [AIRequiredPiece]
        let steps: [String]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = UUID()
            self.name = try container.decode(String.self, forKey: .name)
            self.description = try container.decode(String.self, forKey: .description)
            self.difficulty = try container.decode(String.self, forKey: .difficulty)
            self.category = try container.decode(String.self, forKey: .category)
            self.estimatedMinutes = try container.decode(Int.self, forKey: .estimatedMinutes)
            self.requiredPieces = try container.decode([AIRequiredPiece].self, forKey: .requiredPieces)
            self.steps = try container.decode([String].self, forKey: .steps)
        }

        enum CodingKeys: String, CodingKey {
            case name, description, difficulty, category, estimatedMinutes, requiredPieces, steps
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(description, forKey: .description)
            try container.encode(difficulty, forKey: .difficulty)
            try container.encode(category, forKey: .category)
            try container.encode(estimatedMinutes, forKey: .estimatedMinutes)
            try container.encode(requiredPieces, forKey: .requiredPieces)
            try container.encode(steps, forKey: .steps)
        }
    }

    struct AIRequiredPiece: Codable {
        let name: String
        let category: String
        let color: String
        let quantity: Int
    }

    /// Generate creative build ideas from the user's inventory using GPT-4o
    func generateBuildIdeas(from pieces: [LegoPiece], count: Int = 3) async throws -> [AIBuildIdea] {
        guard config.canUseOnlineMode else {
            throw AzureAIError.notConfigured
        }

        let inventorySummary = pieces.map { piece in
            "\(piece.quantity)× \(piece.color.rawValue) \(piece.category.rawValue) \(piece.dimensions.displayString) (part \(piece.partNumber))"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are a creative LEGO master builder. Given a user's brick inventory, suggest \(count) unique, fun build ideas that can be made ENTIRELY from their available pieces.

        Rules:
        - Only use pieces the user actually has (respect quantities and colors)
        - Each build should use a meaningful subset of available pieces
        - Vary difficulty levels across suggestions
        - Vary categories (vehicles, animals, buildings, art, etc.)
        - Provide clear step-by-step instructions (3-8 steps)
        - Be creative and fun — think like a LEGO designer

        For difficulty, use one of: beginner, easy, medium, hard, expert
        For category, use one of: vehicle, building, animal, robot, spaceship, art, nature, gadget, game, character, furniture, decoration

        Respond with ONLY a JSON array. No markdown fences, no explanation.
        Each object must have: name, description, difficulty, category, estimatedMinutes, requiredPieces (array of {name, category, color, quantity}), steps (array of instruction strings).
        """

        let endpoint = config.openAIEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let deployment = config.openAIDeployment
        guard let url = URL(string: "\(endpoint)/openai/deployments/\(deployment)/chat/completions?api-version=2024-10-21") else {
            throw AzureAIError.invalidEndpoint
        }

        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Here is my LEGO inventory:\n\(inventorySummary)\n\nSuggest \(count) builds I can make."]
            ],
            "max_tokens": 4000,
            "temperature": 0.8
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw AzureAIError.parseError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.openAIKey, forHTTPHeaderField: "api-key")
        request.httpBody = jsonData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AzureAIError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AzureAIError.apiError(httpResponse.statusCode, responseBody)
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

        guard let resultData = cleaned.data(using: .utf8) else {
            throw AzureAIError.parseError
        }

        let decoder = JSONDecoder()
        return try decoder.decode([AIBuildIdea].self, from: resultData)
    }

    /// Quick check if Azure is reachable
    func checkConnectivity() async -> Bool {
        guard config.canUseOnlineMode else { return false }
        let ai = await checkAIServicesConnectivity()
        let oai = await checkOpenAIConnectivity()
        return ai && oai
    }

    /// Check Azure AI Services (Computer Vision) connectivity
    func checkAIServicesConnectivity() async -> Bool {
        let endpoint = config.aiServicesEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !endpoint.isEmpty, !config.aiServicesKey.isEmpty,
              let url = URL(string: "\(endpoint)/vision/v3.2/models") else { return false }
        var request = URLRequest(url: url)
        request.setValue(config.aiServicesKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.timeoutInterval = 5
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Check Azure OpenAI connectivity
    func checkOpenAIConnectivity() async -> Bool {
        let endpoint = config.openAIEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let deployment = config.openAIDeployment
        guard !endpoint.isEmpty, !config.openAIKey.isEmpty, !deployment.isEmpty,
              let url = URL(string: "\(endpoint)/openai/deployments/\(deployment)?api-version=2024-02-01") else { return false }
        var request = URLRequest(url: url)
        request.setValue(config.openAIKey, forHTTPHeaderField: "api-key")
        request.timeoutInterval = 5
        do {
            let (_, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return code == 200 || code == 404 // 404 means deployment found but endpoint valid
        } catch {
            return false
        }
    }

    // MARK: - Computer Vision

    private func computerVisionAnalysis(_ image: UIImage) async throws -> String {
        let endpoint = config.aiServicesEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(endpoint)/computervision/imageanalysis:analyze?api-version=2024-02-01&features=caption,tags,objects") else {
            throw AzureAIError.invalidEndpoint
        }

        guard let imageData = compressImage(image, maxBytes: 4_000_000) else {
            throw AzureAIError.imageProcessingFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(config.aiServicesKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.httpBody = imageData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AzureAIError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AzureAIError.apiError(httpResponse.statusCode, body)
        }

        // Parse the response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AzureAIError.parseError
        }

        var parts: [String] = []

        if let caption = (json["captionResult"] as? [String: Any])?["text"] as? String {
            parts.append("Caption: \(caption)")
        }

        if let tags = (json["tagsResult"] as? [String: Any])?["values"] as? [[String: Any]] {
            let tagNames = tags.compactMap { $0["name"] as? String }
            parts.append("Tags: \(tagNames.joined(separator: ", "))")
        }

        if let objects = (json["objectsResult"] as? [String: Any])?["values"] as? [[String: Any]] {
            let objectNames = objects.compactMap {
                ($0["tags"] as? [[String: Any]])?.first?["name"] as? String
            }
            parts.append("Objects: \(objectNames.joined(separator: ", "))")
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - GPT-4o Vision

    private func gptVisionAnalysis(_ image: UIImage, context: String) async throws -> [CloudBrickResult] {
        let endpoint = config.openAIEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let deployment = config.openAIDeployment
        guard let url = URL(string: "\(endpoint)/openai/deployments/\(deployment)/chat/completions?api-version=2024-10-21") else {
            throw AzureAIError.invalidEndpoint
        }

        guard let imageData = compressImage(image, maxBytes: 2_000_000) else {
            throw AzureAIError.imageProcessingFailed
        }
        let base64 = imageData.base64EncodedString()

        let systemPrompt = """
        You are a LEGO brick identification expert. Analyze images of LEGO bricks and identify each visible piece.
        For each brick, provide:
        - partNumber: BrickLink part number (e.g., "3001" for Brick 2×4)
        - name: Standard LEGO name
        - category: One of: brick, plate, tile, slope, round, arch, technic, wheel, connector, bracket, hinge, wedge, window, minifigure, specialty
        - color: One of: red, blue, yellow, green, black, white, gray, darkGray, orange, brown, tan, purple, pink, lime, lightBlue, darkRed, darkGreen, darkBlue, transparent, transparentBlue, transparentRed
        - confidence: 0.0-1.0
        - studsWide: integer
        - studsLong: integer

        Computer Vision context:
        \(context)

        Respond with ONLY a JSON array of objects. No markdown, no explanation.
        """

        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    ["type": "text", "text": "Identify all LEGO bricks visible in this image. Return a JSON array."],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)", "detail": "high"]]
                ]]
            ],
            "max_tokens": 4000,
            "temperature": 0.1
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw AzureAIError.parseError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.openAIKey, forHTTPHeaderField: "api-key")
        request.httpBody = jsonData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AzureAIError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AzureAIError.apiError(httpResponse.statusCode, body)
        }

        // Parse GPT response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AzureAIError.parseError
        }

        // Extract JSON array from response (might have markdown fences)
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let resultData = cleaned.data(using: .utf8) else {
            throw AzureAIError.parseError
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode([CloudBrickResult].self, from: resultData)
        } catch {
            // Try to salvage partial results
            if let array = try? JSONSerialization.jsonObject(with: resultData) as? [[String: Any]] {
                return array.compactMap { dict in
                    guard let name = dict["name"] as? String else { return nil }
                    return CloudBrickResult(
                        partNumber: dict["partNumber"] as? String ?? "unknown",
                        name: name,
                        category: dict["category"] as? String ?? "brick",
                        color: dict["color"] as? String ?? "gray",
                        confidence: (dict["confidence"] as? NSNumber)?.floatValue ?? 0.5,
                        studsWide: (dict["studsWide"] as? NSNumber)?.intValue ?? 2,
                        studsLong: (dict["studsLong"] as? NSNumber)?.intValue ?? 2
                    )
                }
            }
            throw AzureAIError.parseError
        }
    }

    // MARK: - Helpers

    private func compressImage(_ image: UIImage, maxBytes: Int) -> Data? {
        // Scale down if needed
        let maxDimension: CGFloat = 2048
        var targetImage = image
        if max(image.size.width, image.size.height) > maxDimension {
            let scale = maxDimension / max(image.size.width, image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            targetImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }

        // Compress with decreasing quality until under limit
        for quality in stride(from: 0.9, through: 0.1, by: -0.1) {
            if let data = targetImage.jpegData(compressionQuality: quality),
               data.count <= maxBytes {
                return data
            }
        }
        return targetImage.jpegData(compressionQuality: 0.1)
    }
}

// MARK: - Errors

enum AzureAIError: LocalizedError {
    case notConfigured
    case invalidEndpoint
    case imageProcessingFailed
    case networkError(String)
    case apiError(Int, String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Azure AI is not configured. Add your API keys in Settings."
        case .invalidEndpoint: return "Invalid Azure endpoint URL."
        case .imageProcessingFailed: return "Failed to process image for upload."
        case .networkError(let msg): return "Network error: \(msg)"
        case .apiError(let code, let msg): return "Azure API error (\(code)): \(msg)"
        case .parseError: return "Failed to parse Azure AI response."
        }
    }
}
