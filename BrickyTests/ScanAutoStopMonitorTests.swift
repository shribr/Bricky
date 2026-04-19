import XCTest
@testable import Bricky

/// Sprint 6 / A2 — popcorn auto-stop suggestion.
@MainActor
final class ScanAutoStopMonitorTests: XCTestCase {

    /// Helper — produce a monitor with deterministic thresholds and a fixed
    /// reset timestamp so we can advance "time" by passing dates.
    private func makeMonitor(start: Date) -> ScanAutoStopMonitor {
        let m = ScanAutoStopMonitor(
            minPiecesBeforeSuggestion: 10,
            inactivityWindow: 8.0,
            maxRateForStop: 1.0 / 3.0
        )
        m.reset(now: start)
        return m
    }

    func testNoSuggestionBeforeMinPieces() {
        let t0 = Date()
        let monitor = makeMonitor(start: t0)
        // Burst of 5 pieces over 1 second, then long gap — still under min.
        for i in 1...5 { monitor.observe(pieceCount: i, at: t0.addingTimeInterval(0.2 * Double(i))) }
        // Wait 30 s of silence.
        monitor.observe(pieceCount: 5, at: t0.addingTimeInterval(30))
        XCTAssertFalse(monitor.shouldSuggestStop, "Must not suggest before min pieces")
    }

    func testNoSuggestionDuringActiveDetection() {
        let t0 = Date()
        let monitor = makeMonitor(start: t0)
        // 20 detections at 0.5 s apart — rate is 2/sec, well above threshold.
        for i in 1...20 {
            monitor.observe(pieceCount: i, at: t0.addingTimeInterval(0.5 * Double(i)))
        }
        XCTAssertFalse(monitor.shouldSuggestStop, "Active detection must not trigger suggestion")
    }

    func testSuggestionFiresAfterInactivity() {
        let t0 = Date()
        let monitor = makeMonitor(start: t0)
        // 10 quick detections over 5 s.
        for i in 1...10 {
            monitor.observe(pieceCount: i, at: t0.addingTimeInterval(0.5 * Double(i)))
        }
        XCTAssertFalse(monitor.shouldSuggestStop)
        // Then 10 s of silence — rate goes to 0.
        let didTrigger = monitor.observe(pieceCount: 10, at: t0.addingTimeInterval(15))
        XCTAssertTrue(didTrigger)
        XCTAssertTrue(monitor.shouldSuggestStop)
    }

    func testSuggestionFiresOnlyOncePerSession() {
        let t0 = Date()
        let monitor = makeMonitor(start: t0)
        for i in 1...10 {
            monitor.observe(pieceCount: i, at: t0.addingTimeInterval(0.5 * Double(i)))
        }
        _ = monitor.observe(pieceCount: 10, at: t0.addingTimeInterval(15))
        monitor.dismissSuggestion()
        // 30 more seconds of silence.
        let triggeredAgain = monitor.observe(pieceCount: 10, at: t0.addingTimeInterval(45))
        XCTAssertFalse(triggeredAgain, "Must not re-prompt after dismissal")
        XCTAssertFalse(monitor.shouldSuggestStop)
    }

    func testResetClearsState() {
        let t0 = Date()
        let monitor = makeMonitor(start: t0)
        for i in 1...10 {
            monitor.observe(pieceCount: i, at: t0.addingTimeInterval(0.5 * Double(i)))
        }
        _ = monitor.observe(pieceCount: 10, at: t0.addingTimeInterval(15))
        XCTAssertTrue(monitor.shouldSuggestStop)

        let t1 = t0.addingTimeInterval(60)
        monitor.reset(now: t1)
        XCTAssertFalse(monitor.shouldSuggestStop)
        // Fresh session should be able to fire again.
        for i in 1...10 {
            monitor.observe(pieceCount: i, at: t1.addingTimeInterval(0.5 * Double(i)))
        }
        let didTrigger = monitor.observe(pieceCount: 10, at: t1.addingTimeInterval(15))
        XCTAssertTrue(didTrigger)
    }

    func testNoSuggestionInFirstFewSeconds() {
        let t0 = Date()
        let monitor = makeMonitor(start: t0)
        // 10 pieces all in the first 2 seconds — even though rate immediately
        // drops to 0, we shouldn't fire because the session is too young.
        for i in 1...10 {
            monitor.observe(pieceCount: i, at: t0.addingTimeInterval(0.1 * Double(i)))
        }
        let triggeredEarly = monitor.observe(pieceCount: 10, at: t0.addingTimeInterval(3))
        XCTAssertFalse(triggeredEarly, "Must wait minSessionDuration before suggesting")
    }
}
