import AVFoundation
import UIKit
import Combine

/// Monitors camera environment conditions (lighting, exposure, white balance)
/// and provides actionable guidance to improve scan quality.
final class EnvironmentMonitor: ObservableObject {
    static let shared = EnvironmentMonitor()

    @Published var assessment: EnvironmentAssessment = .unknown
    @Published var brightnessLevel: Float = 0.5
    @Published var isEnvironmentSuitable: Bool = true

    struct EnvironmentAssessment: Equatable {
        let lighting: LightingCondition
        let suggestion: String?
        let confidence: Float

        static let unknown = EnvironmentAssessment(lighting: .unknown, suggestion: nil, confidence: 0)

        static func == (lhs: EnvironmentAssessment, rhs: EnvironmentAssessment) -> Bool {
            lhs.lighting == rhs.lighting && lhs.suggestion == rhs.suggestion
        }
    }

    enum LightingCondition: String {
        case tooDark = "Too Dark"
        case dark = "Dim"
        case good = "Good"
        case bright = "Bright"
        case tooBright = "Too Bright"
        case unknown = "Unknown"
    }

    // Thresholds for brightness assessment (0.0–1.0 normalized from ISO/exposure)
    private static let tooDarkThreshold: Float = 0.15
    private static let darkThreshold: Float = 0.30
    private static let brightThreshold: Float = 0.80
    private static let tooBrightThreshold: Float = 0.92

    private var recentBrightness: [Float] = []
    private let bufferSize = 15
    private let queue = DispatchQueue(label: AppConfig.environmentMonitorQueue)

    private init() {}

    /// Analyze a camera frame's brightness via pixel luminance sampling
    func analyzeFrame(_ pixelBuffer: CVPixelBuffer) {
        queue.async { [weak self] in
            guard let self else { return }
            let brightness = self.sampleBrightness(pixelBuffer)
            self.recentBrightness.append(brightness)
            if self.recentBrightness.count > self.bufferSize {
                self.recentBrightness.removeFirst()
            }

            let avgBrightness = self.recentBrightness.reduce(0, +) / Float(self.recentBrightness.count)
            let newAssessment = self.assess(brightness: avgBrightness)

            DispatchQueue.main.async {
                self.brightnessLevel = avgBrightness
                self.assessment = newAssessment
                self.isEnvironmentSuitable = newAssessment.lighting == .good || newAssessment.lighting == .bright
            }
        }
    }

    /// Analyze device exposure metadata from capture device
    func analyzeDevice(_ device: AVCaptureDevice) {
        let iso = device.iso
        let exposureDuration = device.exposureDuration
        let exposureSeconds = CMTimeGetSeconds(exposureDuration)

        // Normalize: low ISO + short exposure = bright; high ISO + long exposure = dark
        let maxISO = device.activeFormat.maxISO
        let normalizedISO = iso / maxISO
        let normalizedExposure = Float(min(exposureSeconds / 0.033, 1.0)) // relative to 30fps frame

        // Combined brightness estimate (inverse — high ISO/exposure = dark environment)
        let brightness = 1.0 - (normalizedISO * 0.6 + normalizedExposure * 0.4)
        let clamped = max(0, min(1, brightness))

        let assessment = assess(brightness: clamped)
        DispatchQueue.main.async { [weak self] in
            self?.brightnessLevel = clamped
            self?.assessment = assessment
            self?.isEnvironmentSuitable = assessment.lighting == .good || assessment.lighting == .bright
        }
    }

    /// Reset monitoring state
    func reset() {
        recentBrightness.removeAll()
        DispatchQueue.main.async { [weak self] in
            self?.assessment = .unknown
            self?.brightnessLevel = 0.5
            self?.isEnvironmentSuitable = true
        }
    }

    // MARK: - Internal

    private func assess(brightness: Float) -> EnvironmentAssessment {
        let condition: LightingCondition
        let suggestion: String?

        switch brightness {
        case ..<Self.tooDarkThreshold:
            condition = .tooDark
            suggestion = "Very low light — move to a brighter area or turn on lights"
        case ..<Self.darkThreshold:
            condition = .dark
            suggestion = "Dim lighting — results may be less accurate"
        case Self.tooBrightThreshold...:
            condition = .tooBright
            suggestion = "Very bright — reduce glare or move away from direct light"
        case Self.brightThreshold...:
            condition = .bright
            suggestion = nil
        default:
            condition = .good
            suggestion = nil
        }

        // Confidence is higher in good lighting
        let confidence: Float = condition == .good || condition == .bright ? 1.0 : 0.6

        return EnvironmentAssessment(lighting: condition, suggestion: suggestion, confidence: confidence)
    }

    /// Sample brightness from pixel buffer by averaging luminance of sparse grid points
    private func sampleBrightness(_ pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0.5 }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)

        // Sample 10×10 grid of points for speed
        let gridSize = 10
        var totalLuminance: Float = 0
        var sampleCount = 0

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let x = (col * width) / gridSize
                let y = (row * height) / gridSize
                let offset = y * bytesPerRow + x * 4 // BGRA format

                let b = Float(pointer[offset]) / 255.0
                let g = Float(pointer[offset + 1]) / 255.0
                let r = Float(pointer[offset + 2]) / 255.0

                // Relative luminance (BT.709)
                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                totalLuminance += luminance
                sampleCount += 1
            }
        }

        return sampleCount > 0 ? totalLuminance / Float(sampleCount) : 0.5
    }
}
