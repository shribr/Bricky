import Foundation
import UIKit
import SwiftUI

/// Manages Azure service configuration: endpoints, API keys, and online/offline mode.
/// Keys can be set directly or loaded from Keychain.
final class AzureConfiguration: ObservableObject {
    static let shared = AzureConfiguration()

    // MARK: - Published state

    @Published var isOnlineModeEnabled: Bool {
        didSet { UserDefaults.standard.set(isOnlineModeEnabled, forKey: "azure_online_mode") }
    }
    @Published var isConfigured: Bool = false

    // MARK: - Endpoints

    var aiServicesEndpoint: String {
        get { stored("azure_ai_endpoint") ?? "https://ai-brickvision-dev.cognitiveservices.azure.com/" }
        set { store(newValue, key: "azure_ai_endpoint"); checkConfiguration() }
    }

    var openAIEndpoint: String {
        get { stored("azure_oai_endpoint") ?? "https://oai-brickvision-dev.openai.azure.com/" }
        set { store(newValue, key: "azure_oai_endpoint"); checkConfiguration() }
    }

    var openAIDeployment: String {
        get { stored("azure_oai_deployment") ?? "gpt-4o" }
        set { store(newValue, key: "azure_oai_deployment") }
    }

    // MARK: - API Keys (Keychain-backed)

    var aiServicesKey: String {
        get { keychainRead(AppConfig.keychainAIKey) ?? "" }
        set { keychainWrite(newValue, service: AppConfig.keychainAIKey); checkConfiguration() }
    }

    var openAIKey: String {
        get { keychainRead(AppConfig.keychainOAIKey) ?? "" }
        set { keychainWrite(newValue, service: AppConfig.keychainOAIKey); checkConfiguration() }
    }

    // MARK: - Init

    private init() {
        self.isOnlineModeEnabled = UserDefaults.standard.bool(forKey: "azure_online_mode")
        checkConfiguration()
    }

    func checkConfiguration() {
        let configured = !aiServicesKey.isEmpty && !openAIKey.isEmpty &&
                         !aiServicesEndpoint.isEmpty && !openAIEndpoint.isEmpty
        DispatchQueue.main.async {
            self.isConfigured = configured
        }
    }

    var canUseOnlineMode: Bool {
        isOnlineModeEnabled && isConfigured
    }

    // MARK: - UserDefaults helpers

    private func stored(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    private func store(_ value: String, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: - Keychain

    private func keychainWrite(_ value: String, service: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: AppConfig.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func keychainRead(_ service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: AppConfig.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
