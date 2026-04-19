import SwiftUI
import MapKit

/// Sprint C — geolocation. Map of all saved scans that captured a location.
/// Each saved scan becomes a Marker; tapping opens that scan's results.
struct ScanMapView: View {
    @StateObject private var history = ScanHistoryStore.shared
    @State private var selectedSession: ScanSession?
    @State private var navigateToResults = false

    private var locatedEntries: [ScanHistoryStore.HistoryEntry] {
        history.entries.filter { $0.hasLocation }
    }

    /// Initial camera region — frames all located entries, or falls back to
    /// a US-centered span when there's nothing to show.
    private var initialPosition: MapCameraPosition {
        guard !locatedEntries.isEmpty else {
            return .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 40)
            ))
        }
        let lats = locatedEntries.compactMap { $0.latitude }
        let lons = locatedEntries.compactMap { $0.longitude }
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        // Pad span so markers aren't on the edge; min span keeps single-marker
        // case from being absurdly zoomed in.
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (maxLat - minLat) * 1.5),
            longitudeDelta: max(0.02, (maxLon - minLon) * 1.5)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    var body: some View {
        ZStack {
            Map(initialPosition: initialPosition) {
                ForEach(locatedEntries) { entry in
                    if let lat = entry.latitude, let lon = entry.longitude {
                        Annotation(entry.placeName ?? "Scan",
                                   coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                            scanMarker(for: entry)
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)

            if locatedEntries.isEmpty {
                emptyState
            }
        }
        .navigationTitle("Scan Map")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToResults) {
            if let session = selectedSession {
                ScanResultsView(session: session)
            }
        }
    }

    private func scanMarker(for entry: ScanHistoryStore.HistoryEntry) -> some View {
        Button {
            selectedSession = history.toScanSession(entry)
            navigateToResults = true
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 40, height: 40)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    Text("\(entry.totalPiecesFound)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(.ultraThinMaterial)
                    )
            }
        }
        .accessibilityLabel("Scan from \(entry.placeName ?? "captured location"), \(entry.totalPiecesFound) pieces")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mappin.slash.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No located scans yet")
                .font(.headline)
            Text("Enable \u{201C}Tag Scans with Location\u{201D} in Settings, then your scans will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
        .padding()
    }
}

#Preview {
    NavigationStack { ScanMapView() }
}
