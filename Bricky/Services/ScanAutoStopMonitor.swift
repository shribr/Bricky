import Foundation
import Combine

/// Sprint 6 / A2 — "Popcorn" auto-stop suggestion.
///
/// Watches the `pieces.count` rate during an active scan. When new pieces
/// stop arriving for long enough — and we've already found enough pieces to
/// be useful — emit a single suggestion to stop. Suggestion is non-blocking
/// (the user can dismiss it and keep scanning).
///
/// ## Heuristic
/// Default thresholds match the spec:
///  • Wait until at least `minPiecesBeforeSuggestion` (10) have been found.
///  • Look at the trailing `inactivityWindow` (8 s) of detection events.
///  • If the rate is below `maxRateForStop` (1 piece per 3 s), suggest stop.
///  • Suppression: only ever suggest once per scan session — once dismissed
///    or once the user actually stops, don't nag again.
@MainActor
final class ScanAutoStopMonitor: ObservableObject {
    /// Whether the suggestion banner should currently be shown.
    @Published private(set) var shouldSuggestStop: Bool = false

    // Thresholds — tuned for typical desk-pile scans.
    private let minPiecesBeforeSuggestion: Int
    private let inactivityWindow: TimeInterval
    private let maxRateForStop: Double // pieces per second

    /// Sliding window of recent detection timestamps. Trimmed to
    /// `inactivityWindow` on every update so memory stays bounded.
    private var recentDetections: [Date] = []
    private var lastObservedCount: Int = 0
    private var hasSuggestedThisSession = false
    /// When the scan started — we don't want to fire the heuristic in the
    /// first few seconds when detections naturally cluster.
    private var sessionStart: Date = .distantPast

    /// Minimum elapsed scan time before we're allowed to suggest. Prevents
    /// "auto-stop fired before user even pointed at the pile" false positives.
    private let minSessionDuration: TimeInterval = 6.0

    init(minPiecesBeforeSuggestion: Int = 10,
         inactivityWindow: TimeInterval = 8.0,
         maxRateForStop: Double = 1.0 / 3.0) {
        self.minPiecesBeforeSuggestion = minPiecesBeforeSuggestion
        self.inactivityWindow = inactivityWindow
        self.maxRateForStop = maxRateForStop
    }

    /// Reset all state. Call when a fresh scan begins.
    func reset(now: Date = Date()) {
        recentDetections.removeAll()
        lastObservedCount = 0
        hasSuggestedThisSession = false
        shouldSuggestStop = false
        sessionStart = now
    }

    /// Dismiss the current suggestion. The monitor will not fire again until
    /// the next `reset()`.
    func dismissSuggestion() {
        shouldSuggestStop = false
        // hasSuggestedThisSession remains true — never re-prompt this scan.
    }

    /// Feed the current piece count + a timestamp. Call this whenever
    /// `scanSession.pieces.count` changes (typically from a Combine
    /// subscription in the view).
    ///
    /// Returns true if this call newly triggered a suggestion.
    @discardableResult
    func observe(pieceCount: Int, at now: Date = Date()) -> Bool {
        defer { lastObservedCount = pieceCount }

        // Record one timestamp per *new* piece since last observation.
        if pieceCount > lastObservedCount {
            let added = pieceCount - lastObservedCount
            for _ in 0..<added { recentDetections.append(now) }
        }

        // Prune anything older than the inactivity window.
        let cutoff = now.addingTimeInterval(-inactivityWindow)
        recentDetections.removeAll { $0 < cutoff }

        guard !hasSuggestedThisSession,
              pieceCount >= minPiecesBeforeSuggestion,
              now.timeIntervalSince(sessionStart) >= minSessionDuration else {
            return false
        }

        // Rate over the recent window. Empty window means "no detections in
        // the last `inactivityWindow` seconds" → 0/sec → trigger.
        let rate = Double(recentDetections.count) / inactivityWindow
        if rate <= maxRateForStop {
            hasSuggestedThisSession = true
            shouldSuggestStop = true
            return true
        }
        return false
    }
}
