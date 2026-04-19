import Foundation
import os.log
import QuartzCore

/// Lightweight performance monitor for camera frame rate and recognition latency.
/// Tracks metrics in-memory and exposes them for display or logging.
final class PerformanceMonitor: ObservableObject {

    static let shared = PerformanceMonitor()

    // MARK: - Published Metrics

    @Published private(set) var currentFPS: Double = 0
    @Published private(set) var averageRecognitionLatency: TimeInterval = 0
    @Published private(set) var lastRecognitionLatency: TimeInterval = 0
    @Published private(set) var peakRecognitionLatency: TimeInterval = 0
    @Published private(set) var frameDropRate: Double = 0

    // MARK: - Targets

    /// Target camera frame rate (frames per second)
    static let targetFPS: Double = 30.0
    /// Maximum acceptable recognition latency in seconds
    static let maxRecognitionLatency: TimeInterval = 0.5

    // MARK: - Internal State

    private var frameTimestamps: [CFTimeInterval] = []
    private var recognitionLatencies: [TimeInterval] = []
    private var droppedFrames: Int = 0
    private var totalFrames: Int = 0

    private let metricsQueue = DispatchQueue(label: AppConfig.performanceQueue, qos: .utility)
    private let logger = Logger(subsystem: AppConfig.bundleId, category: "Performance")
    private let maxSamples = 120 // ~4 seconds at 30fps

    private init() {}

    // MARK: - Frame Tracking

    /// Call when a camera frame is delivered
    func recordFrame() {
        let now = CACurrentMediaTime()
        metricsQueue.async { [weak self] in
            guard let self else { return }
            self.totalFrames += 1
            self.frameTimestamps.append(now)

            // Keep only recent timestamps
            let cutoff = now - 2.0 // 2-second window
            self.frameTimestamps.removeAll { $0 < cutoff }

            let fps = self.frameTimestamps.count > 1
                ? Double(self.frameTimestamps.count - 1) / (now - self.frameTimestamps.first!)
                : 0

            DispatchQueue.main.async {
                self.currentFPS = fps
            }
        }
    }

    /// Call when a frame is dropped (late/discarded)
    func recordDroppedFrame() {
        metricsQueue.async { [weak self] in
            guard let self else { return }
            self.droppedFrames += 1
            let rate = self.totalFrames > 0
                ? Double(self.droppedFrames) / Double(self.totalFrames)
                : 0
            DispatchQueue.main.async {
                self.frameDropRate = rate
            }
        }
    }

    // MARK: - Recognition Latency

    /// Returns the current time for use as a start marker
    func startTiming() -> CFTimeInterval {
        CACurrentMediaTime()
    }

    /// Record a completed recognition operation
    func recordRecognitionLatency(startedAt: CFTimeInterval) {
        let elapsed = CACurrentMediaTime() - startedAt
        metricsQueue.async { [weak self] in
            guard let self else { return }
            self.recognitionLatencies.append(elapsed)
            if self.recognitionLatencies.count > self.maxSamples {
                self.recognitionLatencies.removeFirst()
            }

            let avg = self.recognitionLatencies.reduce(0, +) / Double(self.recognitionLatencies.count)
            let peak = self.recognitionLatencies.max() ?? 0

            if elapsed > Self.maxRecognitionLatency {
                self.logger.warning("Recognition latency \(String(format: "%.0fms", elapsed * 1000)) exceeds \(String(format: "%.0fms", Self.maxRecognitionLatency * 1000)) target")
            }

            DispatchQueue.main.async {
                self.lastRecognitionLatency = elapsed
                self.averageRecognitionLatency = avg
                self.peakRecognitionLatency = peak
            }
        }
    }

    // MARK: - Status

    /// Whether the camera is meeting the 30fps target
    var isFPSOnTarget: Bool {
        currentFPS >= Self.targetFPS * 0.9 // Allow 10% margin
    }

    /// Whether recognition latency is within the 500ms target
    var isLatencyOnTarget: Bool {
        averageRecognitionLatency <= Self.maxRecognitionLatency
    }

    /// Summary string for diagnostics
    var diagnosticSummary: String {
        let fpsStr = String(format: "%.1f", currentFPS)
        let avgStr = String(format: "%.0fms", averageRecognitionLatency * 1000)
        let peakStr = String(format: "%.0fms", peakRecognitionLatency * 1000)
        let dropStr = String(format: "%.1f%%", frameDropRate * 100)
        return "FPS: \(fpsStr) | Avg latency: \(avgStr) | Peak: \(peakStr) | Drop rate: \(dropStr)"
    }

    /// Log current metrics
    func logMetrics() {
        logger.info("\(self.diagnosticSummary)")
    }

    /// Reset all tracked metrics
    func reset() {
        metricsQueue.async { [weak self] in
            guard let self else { return }
            self.frameTimestamps.removeAll()
            self.recognitionLatencies.removeAll()
            self.droppedFrames = 0
            self.totalFrames = 0
            DispatchQueue.main.async {
                self.currentFPS = 0
                self.averageRecognitionLatency = 0
                self.lastRecognitionLatency = 0
                self.peakRecognitionLatency = 0
                self.frameDropRate = 0
            }
        }
    }
}
