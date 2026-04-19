import Foundation

/// Represents a third-party AI image recognition provider that can be configured
/// alongside Azure AI for cloud-enhanced brick identification.
struct AIProvider: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var providerType: ProviderType
    var endpointURL: String
    var apiKey: String
    var isEnabled: Bool
    var modelName: String

    enum ProviderType: String, Codable, CaseIterable, Identifiable {
        case azureAI = "Azure AI"
        case azureOpenAI = "Azure OpenAI"
        case openAI = "OpenAI"
        case googleCloud = "Google Cloud Vision"
        case awsRekognition = "AWS Rekognition"
        case clarifai = "Clarifai"
        case custom = "Custom REST API"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .azureAI, .azureOpenAI: return "cloud.fill"
            case .openAI: return "brain"
            case .googleCloud: return "magnifyingglass.circle.fill"
            case .awsRekognition: return "eye.circle.fill"
            case .clarifai: return "sparkles"
            case .custom: return "server.rack"
            }
        }

        var defaultEndpointPlaceholder: String {
            switch self {
            case .azureAI: return "https://<resource>.cognitiveservices.azure.com/"
            case .azureOpenAI: return "https://<resource>.openai.azure.com/"
            case .openAI: return "https://api.openai.com/v1"
            case .googleCloud: return "https://vision.googleapis.com/v1"
            case .awsRekognition: return "https://rekognition.<region>.amazonaws.com"
            case .clarifai: return "https://api.clarifai.com/v2"
            case .custom: return "https://your-api.example.com/analyze"
            }
        }

        var requiresModel: Bool {
            switch self {
            case .azureOpenAI, .openAI: return true
            default: return false
            }
        }

        var defaultModel: String {
            switch self {
            case .azureOpenAI: return "gpt-4o"
            case .openAI: return "gpt-4o"
            default: return ""
            }
        }

        var apiKeyHeaderName: String {
            switch self {
            case .azureAI: return "Ocp-Apim-Subscription-Key"
            case .azureOpenAI: return "api-key"
            case .openAI: return "Authorization"
            case .googleCloud: return "x-goog-api-key"
            case .awsRekognition: return "X-Amz-Security-Token"
            case .clarifai: return "Authorization"
            case .custom: return "Authorization"
            }
        }

        var formattedKeyValue: (_ key: String) -> String {
            switch self {
            case .openAI, .clarifai, .custom:
                return { "Bearer \($0)" }
            default:
                return { $0 }
            }
        }
    }

    init(providerType: ProviderType) {
        self.id = UUID()
        self.name = providerType.rawValue
        self.providerType = providerType
        self.endpointURL = ""
        self.apiKey = ""
        self.isEnabled = false
        self.modelName = providerType.defaultModel
    }

    init(existingId: UUID, name: String, providerType: ProviderType, endpointURL: String, apiKey: String, isEnabled: Bool, modelName: String) {
        self.id = existingId
        self.name = name
        self.providerType = providerType
        self.endpointURL = endpointURL
        self.apiKey = apiKey
        self.isEnabled = isEnabled
        self.modelName = modelName
    }
}

// MARK: - Provider Registry

/// Manages the collection of configured AI providers with JSON persistence.
final class AIProviderRegistry: ObservableObject {
    static let shared = AIProviderRegistry()

    @Published var providers: [AIProvider] = []

    private let storageURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ai_providers.json")
    }()

    private init() {
        loadProviders()
    }

    var enabledProviders: [AIProvider] {
        providers.filter { $0.isEnabled && !$0.apiKey.isEmpty && !$0.endpointURL.isEmpty }
    }

    var hasEnabledProvider: Bool {
        !enabledProviders.isEmpty
    }

    // MARK: - CRUD

    func addProvider(_ provider: AIProvider) {
        providers.append(provider)
        saveProviders()
    }

    func updateProvider(_ provider: AIProvider) {
        if let idx = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[idx] = provider
            saveProviders()
        }
    }

    func removeProvider(at offsets: IndexSet) {
        providers.remove(atOffsets: offsets)
        saveProviders()
    }

    func removeProvider(id: UUID) {
        providers.removeAll { $0.id == id }
        saveProviders()
    }

    // MARK: - Persistence

    private func saveProviders() {
        // Separate keys for Keychain storage
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        // Save providers with keys redacted in JSON (keys stored separately in Keychain)
        var redacted = providers
        for i in redacted.indices {
            let keyService = AppConfig.keychainPrefix + ".provider-\(redacted[i].id.uuidString)"
            keychainWrite(redacted[i].apiKey, service: keyService)
            redacted[i].apiKey = "" // Don't persist keys in JSON
        }

        if let data = try? encoder.encode(redacted) {
            try? data.write(to: storageURL)
        }
    }

    private func loadProviders() {
        guard let data = try? Data(contentsOf: storageURL),
              var loaded = try? JSONDecoder().decode([AIProvider].self, from: data) else {
            return
        }

        // Restore keys from Keychain
        for i in loaded.indices {
            let keyService = AppConfig.keychainPrefix + ".provider-\(loaded[i].id.uuidString)"
            loaded[i].apiKey = keychainRead(keyService) ?? ""
        }

        providers = loaded
    }

    // MARK: - Keychain

    private func keychainWrite(_ value: String, service: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(AppConfig.keychainAccount)-provider"
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func keychainRead(_ service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(AppConfig.keychainAccount)-provider",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
