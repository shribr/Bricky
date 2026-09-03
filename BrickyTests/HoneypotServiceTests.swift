import XCTest
@testable import Bricky

@MainActor
final class HoneypotServiceTests: XCTestCase {

    private struct MockClient: HoneypotClient {
        let honeypots: [PublicHoneypot]
        let submitSucceeds: Bool
        let recorder: Recorder

        final class Recorder: @unchecked Sendable {
            var submitted: [HoneypotAnswer] = []
        }

        func fetchHoneypots() async -> [PublicHoneypot] { honeypots }
        func submit(_ answer: HoneypotAnswer, entitlementToken: String?) async -> Bool {
            recorder.submitted.append(answer)
            return submitSucceeds
        }
    }

    func testRefreshLoadsHoneypots() async {
        let client = MockClient(
            honeypots: [PublicHoneypot(id: "h1", imageRef: "img1"),
                        PublicHoneypot(id: "h2", imageRef: "img2")],
            submitSucceeds: true, recorder: .init()
        )
        let service = HoneypotService(client: client, tokenProvider: { nil })
        await service.refresh()
        XCTAssertEqual(service.honeypots.map(\.id), ["h1", "h2"])
    }

    func testSubmitForwardsAnswerAndReturnsSuccess() async {
        let recorder = MockClient.Recorder()
        let client = MockClient(honeypots: [], submitSucceeds: true, recorder: recorder)
        let service = HoneypotService(client: client, tokenProvider: { "tok" })
        let answer = HoneypotAnswer(honeypotId: "h1", userPartNumber: "3001", userColor: "Red")
        let ok = await service.submit(answer)
        XCTAssertTrue(ok)
        XCTAssertEqual(recorder.submitted.count, 1)
        XCTAssertEqual(recorder.submitted.first?.honeypotId, "h1")
    }

    func testSubmitReturnsFalseOnFailure() async {
        let client = MockClient(honeypots: [], submitSucceeds: false, recorder: .init())
        let service = HoneypotService(client: client, tokenProvider: { nil })
        let ok = await service.submit(HoneypotAnswer(honeypotId: "h1", userPartNumber: "3001", userColor: "Red"))
        XCTAssertFalse(ok)
    }

    func testFreshServiceHasNoHoneypots() {
        let service = HoneypotService(client: MockClient(honeypots: [], submitSucceeds: true, recorder: .init()),
                                      tokenProvider: { nil })
        XCTAssertTrue(service.honeypots.isEmpty)
    }
}
