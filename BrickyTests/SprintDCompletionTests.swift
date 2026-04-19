import XCTest
@testable import Bricky

final class PerformanceMonitorTests: XCTestCase {

    var monitor: PerformanceMonitor!

    override func setUp() {
        super.setUp()
        monitor = PerformanceMonitor.shared
        monitor.reset()
    }

    override func tearDown() {
        monitor.reset()
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialFPSIsZero() {
        XCTAssertEqual(monitor.currentFPS, 0)
    }

    func testInitialLatencyIsZero() {
        XCTAssertEqual(monitor.averageRecognitionLatency, 0)
    }

    func testInitialDropRateIsZero() {
        XCTAssertEqual(monitor.frameDropRate, 0)
    }

    // MARK: - Targets

    func testTargetFPSIs30() {
        XCTAssertEqual(PerformanceMonitor.targetFPS, 30.0)
    }

    func testMaxRecognitionLatencyIs500ms() {
        XCTAssertEqual(PerformanceMonitor.maxRecognitionLatency, 0.5)
    }

    // MARK: - Recording

    func testRecordFrameDoesNotCrash() {
        for _ in 0..<100 {
            monitor.recordFrame()
        }
        // Just verify no crash
    }

    func testRecordDroppedFrameDoesNotCrash() {
        monitor.recordDroppedFrame()
    }

    func testRecordRecognitionLatency() {
        let start = monitor.startTiming()
        // Simulate some work
        _ = (0..<1000).reduce(0, +)
        monitor.recordRecognitionLatency(startedAt: start)

        let expectation = expectation(description: "Latency recorded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertGreaterThan(self.monitor.lastRecognitionLatency, 0)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Status Checks

    func testIsFPSOnTargetWhenZero() {
        XCTAssertFalse(monitor.isFPSOnTarget)
    }

    func testIsLatencyOnTargetWhenZero() {
        // Zero latency is within target
        XCTAssertTrue(monitor.isLatencyOnTarget)
    }

    // MARK: - Diagnostics

    func testDiagnosticSummaryFormat() {
        let summary = monitor.diagnosticSummary
        XCTAssertTrue(summary.contains("FPS:"))
        XCTAssertTrue(summary.contains("Avg latency:"))
        XCTAssertTrue(summary.contains("Peak:"))
        XCTAssertTrue(summary.contains("Drop rate:"))
    }

    func testResetClearsMetrics() {
        monitor.recordFrame()
        monitor.recordDroppedFrame()
        monitor.reset()

        let expectation = expectation(description: "Reset complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.monitor.frameDropRate, 0)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
}
