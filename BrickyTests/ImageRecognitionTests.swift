import XCTest
@testable import Bricky

/// Tests for the cloud, Pro-gated AI subject recognition feature: the network
/// client mapping, the view model state machine, and the `SubscriptionManager`
/// monthly quota accounting. Only the network boundary is mocked
/// (`RecognitionHTTPClient`); everything else exercises real code.
@MainActor
final class ImageRecognitionTests: XCTestCase {

    // MARK: - Helpers

    /// A stub HTTP client returning a canned response or throwing.
    private struct StubHTTPClient: RecognitionHTTPClient {
        let result: Result<(Data, URLResponse), Error>
        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            try result.get()
        }
    }

    private func httpResponse(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/api/recognizeImage")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func okBody(subjects: [[String: Any]], remaining: Int = 99) -> Data {
        let json: [String: Any] = ["subjects": subjects, "remainingQuota": remaining]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func client(
        result: Result<(Data, URLResponse), Error>,
        endpoint: URL? = URL(string: "https://example.com/api/recognizeImage")
    ) -> AzureOpenAIRecognitionClient {
        AzureOpenAIRecognitionClient(
            endpoint: endpoint,
            httpClient: StubHTTPClient(result: result)
        )
    }

    private var sampleImage: UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        return renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
    }

    // MARK: - Client mapping

    func testClientDecodesSuccessfulResult() async throws {
        let data = okBody(subjects: [[
            "name": "Eiffel Tower",
            "category": "landmark",
            "confidence": 0.93,
            "summary": "Tower in Paris.",
            "location": "Paris, France"
        ]])
        let svc = client(result: .success((data, httpResponse(200))))
        let result = try await svc.recognize(in: sampleImage, entitlementToken: "jws")
        XCTAssertEqual(result.subjects.count, 1)
        XCTAssertEqual(result.subjects.first?.name, "Eiffel Tower")
        XCTAssertEqual(result.subjects.first?.category, .landmark)
        XCTAssertEqual(result.remainingQuota, 99)
    }

    func testClientMaps429ToQuotaExceeded() async {
        let svc = client(result: .success((Data("{}".utf8), httpResponse(429))))
        await assertThrows(svc) { error in
            XCTAssertEqual(error, .quotaExceeded)
        }
    }

    func testClientMaps401ToNotEntitled() async {
        let svc = client(result: .success((Data("{}".utf8), httpResponse(401))))
        await assertThrows(svc) { error in
            XCTAssertEqual(error, .notEntitled)
        }
    }

    func testClientMaps403ToNotEntitled() async {
        let svc = client(result: .success((Data("{}".utf8), httpResponse(403))))
        await assertThrows(svc) { error in
            XCTAssertEqual(error, .notEntitled)
        }
    }

    func testClientMapsOfflineURLError() async {
        let svc = client(result: .failure(URLError(.notConnectedToInternet)))
        await assertThrows(svc) { error in
            XCTAssertEqual(error, .offline)
        }
    }

    func testClientEmptySubjectsThrowsNoSubjectsFound() async {
        let svc = client(result: .success((okBody(subjects: []), httpResponse(200))))
        await assertThrows(svc) { error in
            XCTAssertEqual(error, .noSubjectsFound)
        }
    }

    func testClientNotConfiguredWhenEndpointNil() async {
        let svc = client(
            result: .success((okBody(subjects: []), httpResponse(200))),
            endpoint: nil
        )
        await assertThrows(svc) { error in
            XCTAssertEqual(error, .notConfigured)
        }
    }

    private func assertThrows(
        _ svc: AzureOpenAIRecognitionClient,
        _ check: (ImageRecognitionError) -> Void
    ) async {
        do {
            _ = try await svc.recognize(in: sampleImage, entitlementToken: "jws")
            XCTFail("Expected ImageRecognitionError to be thrown")
        } catch let error as ImageRecognitionError {
            check(error)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Model decoding leniency

    func testRecognizedSubjectDecodesLeniently() throws {
        let json = Data("""
        {"name":"Mystery","confidence":2.0}
        """.utf8)
        let subject = try JSONDecoder().decode(RecognizedSubject.self, from: json)
        XCTAssertEqual(subject.category, .unknown)
        XCTAssertEqual(subject.confidence, 1.0, accuracy: 0.0001) // clamped
    }
}

/// View-model state-machine tests. These drive the real `SubscriptionManager`
/// singleton (only entitlement state is toggled via the developer override),
/// proving the Pro-gating and honest-failure paths without any StoreKit
/// receipt.
@MainActor
final class ImageRecognitionViewModelTests: XCTestCase {

    private var savedOverride = false

    override func setUp() {
        super.setUp()
        savedOverride = SubscriptionManager.shared.developerProOverride
    }

    override func tearDown() {
        SubscriptionManager.shared.developerProOverride = savedOverride
        super.tearDown()
    }

    private struct NeverCalledService: ImageRecognitionService {
        func recognize(in image: UIImage, entitlementToken: String) async throws -> RecognitionResult {
            XCTFail("Service must not be called when entitlement/quota gating blocks the request")
            return RecognitionResult(subjects: [], remainingQuota: nil)
        }
    }

    /// Captures the entitlement token the view model sends and returns a canned
    /// result so we can assert the developer-bypass path actually calls through.
    private actor TokenCapturingService: ImageRecognitionService {
        private(set) var capturedToken: String?
        private let result: RecognitionResult
        init(result: RecognitionResult) { self.result = result }
        func recognize(in image: UIImage, entitlementToken: String) async throws -> RecognitionResult {
            capturedToken = entitlementToken
            return result
        }
        func token() -> String? { capturedToken }
    }

    private var sampleImage: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.systemRed.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    func testFreeUserGetsUpsell() async {
        SubscriptionManager.shared.developerProOverride = false
        let vm = ImageRecognitionViewModel(service: NeverCalledService())
        vm.setImage(sampleImage)
        await vm.recognize()
        XCTAssertEqual(vm.phase, .upsell)
        XCTAssertTrue(vm.requiresUpgrade)
    }

    func testDeveloperOverrideSendsDevBypassTokenAndCallsService() async {
        // The developer override is the ONLY way to unlock cloud AI. It produces
        // no StoreKit receipt, so the VM sends the developer-bypass token and
        // calls the proxy. The proxy (not the app) decides whether to honor it.
        SubscriptionManager.shared.developerProOverride = true
        guard SubscriptionManager.shared.aiRecognitionsRemaining > 0 else {
            // Monthly quota already exhausted in this environment — skip.
            return
        }
        let subject = RecognizedSubject(
            name: "Eiffel Tower", category: .landmark,
            confidence: 0.9, summary: "Tower in Paris.", location: "Paris"
        )
        let service = TokenCapturingService(
            result: RecognitionResult(subjects: [subject], remainingQuota: 50)
        )
        let vm = ImageRecognitionViewModel(service: service)
        vm.setImage(sampleImage)
        await vm.recognize()
        let captured = await service.token()
        XCTAssertEqual(captured, AppConfig.aiRecognitionDevBypassToken)
        if case .results(let subjects) = vm.phase {
            XCTAssertEqual(subjects.first?.name, "Eiffel Tower")
        } else {
            XCTFail("Expected .results, got \(vm.phase)")
        }
    }

    func testRecognizeNoOpsWithoutImage() async {
        let vm = ImageRecognitionViewModel(service: NeverCalledService())
        await vm.recognize()
        XCTAssertEqual(vm.phase, .idle)
    }
}

/// Quota-accounting tests on the real `SubscriptionManager`. Measured as deltas
/// so they don't depend on the starting count.
@MainActor
final class SubscriptionManagerAIQuotaTests: XCTestCase {

    private var savedOverride = false

    override func setUp() {
        super.setUp()
        savedOverride = SubscriptionManager.shared.developerProOverride
    }

    override func tearDown() {
        SubscriptionManager.shared.developerProOverride = savedOverride
        super.tearDown()
    }

    func testNonProHasZeroRemaining() {
        SubscriptionManager.shared.developerProOverride = false
        XCTAssertEqual(SubscriptionManager.shared.aiRecognitionsRemaining, 0)
        XCTAssertFalse(SubscriptionManager.shared.canUseAIRecognition)
    }

    func testRecordDecrementsRemainingForProUser() {
        let mgr = SubscriptionManager.shared
        mgr.developerProOverride = true
        let before = mgr.aiRecognitionsRemaining
        XCTAssertGreaterThan(before, 0)
        mgr.recordAIRecognition()
        XCTAssertEqual(mgr.aiRecognitionsRemaining, before - 1)
    }

    func testRemainingNeverExceedsMonthlyLimit() {
        let mgr = SubscriptionManager.shared
        mgr.developerProOverride = true
        XCTAssertLessThanOrEqual(
            mgr.aiRecognitionsRemaining,
            AppConfig.proMonthlyAIRecognitionLimit
        )
    }

    /// The developer override always yields the shared dev-bypass token,
    /// regardless of its configured value.
    func testEntitlementTokenIsDevBypassWhenOverrideOn() async {
        let mgr = SubscriptionManager.shared
        mgr.developerProOverride = true
        let token = await mgr.recognitionEntitlementToken()
        XCTAssertEqual(token, AppConfig.aiRecognitionDevBypassToken)
    }

    /// Free, non-developer users must never receive a cloud token, so callers
    /// fall back to the on-device pipeline.
    func testEntitlementTokenIsNilForFreeUser() async {
        let mgr = SubscriptionManager.shared
        mgr.developerProOverride = false
        // Only assert the free-user contract when StoreKit granted no Pro
        // entitlement in this test environment.
        if !mgr.isPro {
            let token = await mgr.recognitionEntitlementToken()
            XCTAssertNil(token, "Free, non-developer users must not get a cloud token.")
        }
    }
}
