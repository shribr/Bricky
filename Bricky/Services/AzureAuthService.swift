import Foundation
import AuthenticationServices
import CommonCrypto
import SwiftUI

/// Handles Azure AD authentication via browser-based OAuth 2.0 and
/// fetches secrets from Azure Key Vault using the obtained access token.
@MainActor
final class AzureAuthService: NSObject, ObservableObject {
    static let shared = AzureAuthService()

    // MARK: - Published state

    @Published var isSignedIn = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var userName: String?

    // MARK: - Configuration (user-provided)

    var tenantId: String {
        get { UserDefaults.standard.string(forKey: "azure_tenant_id") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "azure_tenant_id") }
    }

    var clientId: String {
        get { UserDefaults.standard.string(forKey: "azure_client_id") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "azure_client_id") }
    }

    var keyVaultName: String {
        get { UserDefaults.standard.string(forKey: "azure_keyvault_name") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "azure_keyvault_name") }
    }

    // MARK: - Token storage

    private var accessToken: String? {
        get { keychainRead(AppConfig.keychainAzureToken) }
        set {
            if let val = newValue { keychainWrite(val, service: AppConfig.keychainAzureToken) }
            else { keychainDelete(AppConfig.keychainAzureToken) }
        }
    }

    private var refreshToken: String? {
        get { keychainRead(AppConfig.keychainAzureRefresh) }
        set {
            if let val = newValue { keychainWrite(val, service: AppConfig.keychainAzureRefresh) }
            else { keychainDelete(AppConfig.keychainAzureRefresh) }
        }
    }

    private var tokenExpiry: Date? {
        get {
            let ts = UserDefaults.standard.double(forKey: "azure_token_expiry")
            return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "azure_token_expiry") }
    }

    var isConfiguredForAuth: Bool {
        !tenantId.isEmpty && !clientId.isEmpty && !keyVaultName.isEmpty
    }

    // MARK: - Init

    private override init() {
        super.init()
        // Check if we have a valid token
        if accessToken != nil {
            isSignedIn = true
            decodeUserName()
        }
    }

    // MARK: - Sign In (OAuth 2.0 Authorization Code + PKCE)

    func signIn() async {
        guard isConfiguredForAuth else {
            errorMessage = "Configure Tenant ID, Client ID, and Key Vault name first."
            return
        }

        isLoading = true
        errorMessage = nil

        // Generate PKCE
        let codeVerifier = generateCodeVerifier()
        guard let codeChallenge = generateCodeChallenge(from: codeVerifier) else {
            errorMessage = "Failed to generate PKCE challenge"
            isLoading = false
            return
        }

        let redirectURI = AppConfig.authRedirectURL
        let scope = "https://vault.azure.net/.default offline_access openid profile"
        let state = UUID().uuidString

        var components = URLComponents()
        components.scheme = "https"
        components.host = "login.microsoftonline.com"
        components.path = "/\(tenantId)/oauth2/v2.0/authorize"
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account")
        ]

        guard let authURL = components.url else {
            errorMessage = "Failed to construct authorization URL"
            isLoading = false
            return
        }

        do {
            let callbackURL = try await performWebAuth(url: authURL, callbackScheme: AppConfig.keychainAccount)

            guard let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = comps.queryItems?.first(where: { $0.name == "code" })?.value,
                  comps.queryItems?.first(where: { $0.name == "state" })?.value == state else {
                errorMessage = "Invalid authentication response"
                isLoading = false
                return
            }

            try await exchangeCodeForToken(code: code, codeVerifier: codeVerifier, redirectURI: redirectURI)

            isSignedIn = true
            decodeUserName()
            isLoading = false

        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                // User cancelled — not an error
            } else {
                errorMessage = "Authentication failed: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    func signOut() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        isSignedIn = false
        userName = nil
        errorMessage = nil
    }

    // MARK: - Key Vault Secret Retrieval

    /// Fetch secrets from Key Vault and populate AzureConfiguration
    func loadSecretsFromKeyVault() async throws {
        guard isSignedIn else { throw AzureAuthError.notSignedIn }

        let token = try await getValidToken()
        let vaultURL = "https://\(keyVaultName).vault.azure.net"

        // Secret names matching what was stored in KV
        let secretMap: [(secretName: String, keyPath: ReferenceWritableKeyPath<AzureConfiguration, String>)] = [
            ("AzureAI-ApiKey", \.aiServicesKey),
            ("AzureAI-Endpoint", \.aiServicesEndpoint),
            ("AzureOpenAI-ApiKey", \.openAIKey),
            ("AzureOpenAI-Endpoint", \.openAIEndpoint),
            ("AzureOpenAI-DeploymentName", \.openAIDeployment)
        ]

        let config = AzureConfiguration.shared
        var loaded = 0

        for (secretName, keyPath) in secretMap {
            do {
                let value = try await fetchSecret(name: secretName, vaultURL: vaultURL, token: token)
                if !value.isEmpty {
                    config[keyPath: keyPath] = value
                    loaded += 1
                }
            } catch {
                // Non-fatal — some secrets may not exist
                print("Key Vault: skipped \(secretName) — \(error.localizedDescription)")
            }
        }

        if loaded > 0 {
            config.isOnlineModeEnabled = true
            config.checkConfiguration()
        } else {
            throw AzureAuthError.noSecretsFound
        }
    }

    private func fetchSecret(name: String, vaultURL: String, token: String) async throws -> String {
        guard let url = URL(string: "\(vaultURL)/secrets/\(name)?api-version=7.4") else {
            throw AzureAuthError.invalidVaultURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AzureAuthError.networkError("Invalid response")
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AzureAuthError.vaultError(http.statusCode, body)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json["value"] as? String else {
            throw AzureAuthError.parseError
        }

        return value
    }

    // MARK: - Token Management

    private func getValidToken() async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date().addingTimeInterval(60) {
            return token
        }

        // Try refresh
        if let refresh = refreshToken {
            do {
                try await refreshAccessToken(refreshToken: refresh)
                if let token = accessToken { return token }
            } catch {
                // Refresh failed — need re-auth
            }
        }

        throw AzureAuthError.tokenExpired
    }

    private func exchangeCodeForToken(code: String, codeVerifier: String, redirectURI: String) async throws {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "login.microsoftonline.com"
        components.path = "/\(tenantId)/oauth2/v2.0/token"

        guard let url = components.url else {
            throw AzureAuthError.networkError("Invalid token URL")
        }

        let bodyParams = [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier,
            "scope": "https://vault.azure.net/.default offline_access openid profile"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown"
            throw AzureAuthError.tokenExchangeFailed(body)
        }

        try parseTokenResponse(data)
    }

    private func refreshAccessToken(refreshToken: String) async throws {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "login.microsoftonline.com"
        components.path = "/\(tenantId)/oauth2/v2.0/token"

        guard let url = components.url else { throw AzureAuthError.networkError("Invalid token URL") }

        let bodyParams = [
            "grant_type": "refresh_token",
            "client_id": clientId,
            "refresh_token": refreshToken,
            "scope": "https://vault.azure.net/.default offline_access openid profile"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AzureAuthError.tokenRefreshFailed
        }

        try parseTokenResponse(data)
    }

    private func parseTokenResponse(_ data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AzureAuthError.parseError
        }

        guard let token = json["access_token"] as? String else {
            throw AzureAuthError.parseError
        }

        accessToken = token

        if let refresh = json["refresh_token"] as? String {
            self.refreshToken = refresh
        }

        if let expiresIn = json["expires_in"] as? Int {
            tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
        }
    }

    // MARK: - PKCE

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String? {
        guard let data = verifier.data(using: .ascii) else { return nil }
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - ASWebAuthenticationSession

    private func performWebAuth(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = callbackURL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: AzureAuthError.networkError("No callback URL"))
                }
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self
            session.start()
        }
    }

    // MARK: - JWT decode (minimal — just get display name)

    private func decodeUserName() {
        guard let token = accessToken else { return }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return }

        var base64 = String(parts[1])
        while base64.count % 4 != 0 { base64 += "=" }
        base64 = base64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        userName = json["name"] as? String ?? json["preferred_username"] as? String
    }

    // MARK: - Keychain Helpers

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

    private func keychainDelete(_ service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: AppConfig.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension AzureAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}

// MARK: - Errors

enum AzureAuthError: LocalizedError {
    case notSignedIn
    case tokenExpired
    case tokenExchangeFailed(String)
    case tokenRefreshFailed
    case invalidVaultURL
    case noSecretsFound
    case networkError(String)
    case vaultError(Int, String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in to Azure. Please sign in first."
        case .tokenExpired: return "Azure session expired. Please sign in again."
        case .tokenExchangeFailed(let msg): return "Token exchange failed: \(msg)"
        case .tokenRefreshFailed: return "Failed to refresh Azure token. Please sign in again."
        case .invalidVaultURL: return "Invalid Key Vault URL."
        case .noSecretsFound: return "No secrets found in Key Vault. Check the secret names."
        case .networkError(let msg): return "Network error: \(msg)"
        case .vaultError(let code, _): return "Key Vault error (HTTP \(code))."
        case .parseError: return "Failed to parse Azure response."
        }
    }
}
