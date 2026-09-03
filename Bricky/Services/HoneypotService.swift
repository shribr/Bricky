import Foundation

/// A client-safe honeypot item (no ground-truth labels — the server keeps those
/// and grades submissions). `imageRef` is what the quiz shows the user.
struct PublicHoneypot: Codable, Identifiable {
    let id: String
    let imageRef: String
}

/// A user's answer to a honeypot, graded server-side against the secret truth.
struct HoneypotAnswer: Codable {
    let honeypotId: String
    let userPartNumber: String
    let userColor: String
}

/// Networking seam for honeypots (injectable for tests).
protocol HoneypotClient: Sendable {
    func fetchHoneypots() async -> [PublicHoneypot]
    func submit(_ answer: HoneypotAnswer, entitlementToken: String?) async -> Bool
}

/// Fetches known-answer honeypot items and submits the user's answers. Powers a
/// "help train the scanner" quiz whose grading is a collusion-proof trust signal
/// for the crowdsourced-accuracy pipeline. Answers are graded on the server.
@MainActor
final class HoneypotService: ObservableObject {
    static let shared = HoneypotService()

    @Published private(set) var honeypots: [PublicHoneypot] = []

    private let client: HoneypotClient
    private let tokenProvider: @MainActor () async -> String?

    init(
        client: HoneypotClient = URLSessionHoneypotClient(),
        tokenProvider: @escaping @MainActor () async -> String? = { await SubscriptionManager.shared.recognitionEntitlementToken() }
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    /// Load the current honeypot items to quiz the user with.
    func refresh() async {
        honeypots = await client.fetchHoneypots()
    }

    /// Submit one answer; returns true when the server accepted it.
    @discardableResult
    func submit(_ answer: HoneypotAnswer) async -> Bool {
        let token = await tokenProvider()
        return await client.submit(answer, entitlementToken: token)
    }
}

/// Default client — GET honeypots, POST an answer with the entitlement token.
struct URLSessionHoneypotClient: HoneypotClient {
    func fetchHoneypots() async -> [PublicHoneypot] {
        guard let url = AppConfig.honeypotsEndpoint else { return [] }
        struct Response: Decodable { let honeypots: [PublicHoneypot] }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else { return [] }
            return (try? JSONDecoder().decode(Response.self, from: data))?.honeypots ?? []
        } catch {
            return []
        }
    }

    func submit(_ answer: HoneypotAnswer, entitlementToken: String?) async -> Bool {
        guard let url = AppConfig.submitHoneypotEndpoint else { return false }
        struct Body: Encodable {
            let honeypotId: String
            let userPartNumber: String
            let userColor: String
            let entitlementToken: String?
        }
        let body = Body(
            honeypotId: answer.honeypotId,
            userPartNumber: answer.userPartNumber,
            userColor: answer.userColor,
            entitlementToken: entitlementToken
        )
        guard let data = try? JSONEncoder().encode(body) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }
}
