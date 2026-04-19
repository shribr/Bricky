import AuthenticationServices
import Foundation
import SwiftUI

/// Manages Sign in with Apple authentication and local user state
final class AuthenticationService: NSObject, ObservableObject {
    static let shared = AuthenticationService()

    @Published var isSignedIn: Bool = false
    @Published var userIdentifier: String?
    @Published var displayName: String?
    @Published var email: String?
    @Published var isLoading: Bool = false
    @Published var authError: String?

    private let userIdKey = "appleUserIdentifier"
    private let displayNameKey = "appleDisplayName"

    override private init() {
        super.init()
        restoreSession()
    }

    // MARK: - Session Persistence

    private func restoreSession() {
        guard let storedId = UserDefaults.standard.string(forKey: userIdKey) else { return }
        userIdentifier = storedId
        displayName = UserDefaults.standard.string(forKey: displayNameKey)
        isSignedIn = true
        checkCredentialState()
    }

    private func checkCredentialState() {
        guard let userId = userIdentifier else { return }
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: userId) { [weak self] state, _ in
            Task { @MainActor in
                switch state {
                case .authorized:
                    self?.isSignedIn = true
                case .revoked, .notFound:
                    self?.signOut()
                default:
                    break
                }
            }
        }
    }

    // MARK: - Sign In

    func signIn() {
        isLoading = true
        authError = nil
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: - Sign Out

    func signOut() {
        isSignedIn = false
        userIdentifier = nil
        displayName = nil
        email = nil
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: displayNameKey)
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthenticationService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthenticationService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            Task { @MainActor in
                isLoading = false
                authError = "Unexpected credential type"
            }
            return
        }

        let userId = credential.user
        // Apple only provides name/email on first sign-in
        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")

        Task { @MainActor in
            userIdentifier = userId
            if !name.isEmpty {
                displayName = name
                UserDefaults.standard.set(name, forKey: displayNameKey)
            }
            if let credentialEmail = credential.email {
                email = credentialEmail
            }
            UserDefaults.standard.set(userId, forKey: userIdKey)
            isSignedIn = true
            isLoading = false
            authError = nil
            AnalyticsService.shared.track(.appLaunched) // track sign-in
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            isLoading = false
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                self.authError = nil // user cancelled, not an error
            } else {
                self.authError = error.localizedDescription
            }
        }
    }
}
