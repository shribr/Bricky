import Foundation
import CoreLocation
import Combine

/// One-shot location capture for `ScanSession`. Designed for the *moment* a
/// scan starts, not for continuous tracking — we ask for a single fix,
/// reverse-geocode it, then stop.
///
/// ## Privacy posture
/// - Permission is requested **only after** the user has explicitly enabled
///   `ScanSettings.locationCaptureEnabled`. Until then the service does
///   nothing.
/// - Coordinates are rounded to 4 decimals (~11 m precision) before being
///   handed back to the caller, so we never persist a pin tight enough to
///   identify a specific building.
/// - The user can disable capture in Settings at any time, which immediately
///   stops future captures and offers a "Forget locations on existing scans"
///   action via `ScanHistoryStore.clearLocations()`.
@MainActor
final class ScanLocationService: NSObject, ObservableObject {
    static let shared = ScanLocationService()

    /// Result returned to callers — coordinates are pre-rounded.
    struct Capture: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
        let placeName: String?
        let capturedAt: Date
    }

    /// `CLLocationManager` is heavy; lazily create on first use so the app
    /// launch path stays clean for users who never enable location capture.
    private lazy var locationManager: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return m
    }()

    private let geocoder = CLGeocoder()

    /// In-flight continuation for the current `requestCapture()` call.
    /// Captures are one-shot — only one outstanding request at a time.
    private var pendingContinuation: CheckedContinuation<Capture?, Never>?
    /// Watchdog that completes the capture with `nil` if neither the
    /// permission callback nor a location fix arrives in time.
    private var watchdog: Task<Void, Never>?

    /// Capture timeout. Reverse-geocoding is best-effort and runs *after*
    /// we've returned the coordinate, so this only governs the GPS fix.
    private static let captureTimeout: TimeInterval = 6.0

    private override init() { super.init() }

    /// Whether the OS-level permission allows us to capture a location.
    var authorizationAllowsCapture: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }

    /// Whether we should prompt the user for permission (i.e., we've never
    /// asked before).
    var needsPermissionPrompt: Bool {
        locationManager.authorizationStatus == .notDetermined
    }

    /// Request a single location fix + reverse geocode. Returns nil if
    /// permission is denied, the device can't get a fix, or the timeout
    /// elapses. Safe to call repeatedly — second calls while the first is
    /// in flight return nil immediately.
    func requestCapture() async -> Capture? {
        guard pendingContinuation == nil else { return nil }
        guard authorizationAllowsCapture else { return nil }

        return await withCheckedContinuation { (cont: CheckedContinuation<Capture?, Never>) in
            self.pendingContinuation = cont
            locationManager.requestLocation()
            // Watchdog so we never hang forever.
            watchdog = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.captureTimeout * 1_000_000_000))
                await MainActor.run {
                    self?.completeIfPending(with: nil)
                }
            }
        }
    }

    /// Ask the OS for permission. Resolves with the user's choice — `true`
    /// means we got `.authorizedWhenInUse` (or higher).
    func requestPermission() async -> Bool {
        guard needsPermissionPrompt else { return authorizationAllowsCapture }
        locationManager.requestWhenInUseAuthorization()
        // Wait briefly for the system prompt → delegate → status change.
        for _ in 0..<30 { // ~3 s
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !needsPermissionPrompt { break }
        }
        return authorizationAllowsCapture
    }

    // MARK: - Internal

    private func completeIfPending(with capture: Capture?) {
        guard let cont = pendingContinuation else { return }
        pendingContinuation = nil
        watchdog?.cancel()
        watchdog = nil
        cont.resume(returning: capture)
    }

    /// Round to 4 decimals (~11 m precision).
    nonisolated private static func roundCoord(_ v: Double) -> Double {
        (v * 10_000).rounded() / 10_000
    }

    /// Best-effort reverse-geocode. Updates `ScanHistoryStore` if the entry
    /// for `sessionID` already exists. Runs detached because we don't want
    /// to block the scan-start path.
    func backfillPlaceName(for sessionID: UUID,
                           latitude: Double,
                           longitude: Double) {
        Task { [weak self] in
            guard let self else { return }
            let location = CLLocation(latitude: latitude, longitude: longitude)
            let name: String? = await self.reverseGeocode(location: location)
            guard let name else { return }
            await MainActor.run {
                ScanHistoryStore.shared.updatePlaceName(sessionID: sessionID, placeName: name)
            }
        }
    }

    private func reverseGeocode(location: CLLocation) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                let name = placemarks?.first.flatMap { Self.formatPlacemark($0) }
                cont.resume(returning: name)
            }
        }
    }

    /// Format a placemark as "City, State" / "City, Country" — never the
    /// street address, in keeping with our privacy posture.
    nonisolated static func formatPlacemark(_ p: CLPlacemark) -> String? {
        let city = p.locality ?? p.subAdministrativeArea
        let region = p.administrativeArea ?? p.country
        switch (city, region) {
        case (let c?, let r?): return "\(c), \(r)"
        case (let c?, nil):    return c
        case (nil, let r?):    return r
        default:               return nil
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension ScanLocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let lat = Self.roundCoord(loc.coordinate.latitude)
        let lon = Self.roundCoord(loc.coordinate.longitude)
        let capture = Capture(
            latitude: lat,
            longitude: lon,
            placeName: nil,           // filled in async via backfillPlaceName
            capturedAt: Date()
        )
        Task { @MainActor in
            self.completeIfPending(with: capture)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            self.completeIfPending(with: nil)
        }
    }
}

// MARK: - Distance helper (Haversine)

enum LocationDistance {
    /// Great-circle distance in meters between two coordinate pairs.
    /// Used by the "near me" inventory filter.
    static func meters(lat1: Double, lon1: Double,
                       lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0 // Earth radius in meters
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }
}
