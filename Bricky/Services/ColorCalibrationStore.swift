import Foundation
import UIKit
import Combine

/// Sprint 5 / F6 — Persists user-captured color calibration samples.
///
/// The wizard captures one reference photo per LegoColor under the user's
/// typical lighting, extracts the dominant RGB, and stores it. The
/// classifier (or downstream review tools) can later use these samples to
/// nudge their color thresholds.
@MainActor
final class ColorCalibrationStore: ObservableObject {
    static let shared = ColorCalibrationStore()

    struct Sample: Codable, Equatable {
        let color: LegoColor
        let red: Double
        let green: Double
        let blue: Double
        let capturedAt: Date

        var uiColor: UIColor {
            UIColor(red: CGFloat(red),
                    green: CGFloat(green),
                    blue: CGFloat(blue),
                    alpha: 1)
        }
    }

    @Published private(set) var samples: [LegoColor: Sample] = [:]

    private let storageKey = "ColorCalibrationStore.samples"

    private init() {
        load()
    }

    // MARK: - API

    func sample(for color: LegoColor) -> Sample? { samples[color] }

    func recordSample(for color: LegoColor, red: Double, green: Double, blue: Double) {
        samples[color] = Sample(color: color,
                                red: red.clamped(),
                                green: green.clamped(),
                                blue: blue.clamped(),
                                capturedAt: Date())
        persist()
    }

    /// Convenience for tests: record a sample directly from a UIColor.
    func recordSample(for color: LegoColor, uiColor: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        recordSample(for: color,
                     red: Double(r),
                     green: Double(g),
                     blue: Double(b))
    }

    func clear(color: LegoColor) {
        samples.removeValue(forKey: color)
        persist()
    }

    func clearAll() {
        samples.removeAll()
        persist()
    }

    /// Whether the user has captured at least one sample (used to gate UI).
    var isCalibrated: Bool { !samples.isEmpty }

    var calibratedColorsCount: Int { samples.count }

    // MARK: - Persistence

    private func persist() {
        let array = Array(samples.values)
        guard let data = try? JSONEncoder().encode(array) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let array = try? JSONDecoder().decode([Sample].self, from: data)
        else { return }
        samples = Dictionary(uniqueKeysWithValues: array.map { ($0.color, $0) })
    }
}

private extension Double {
    func clamped() -> Double { max(0, min(1, self)) }
}
