import SwiftUI

/// Full-screen modal listing every scan history entry.
/// Includes Near Me filter and Map toolbar items (moved out of HomeView).
struct AllScanHistoryView: View {
    @StateObject private var scanHistory = ScanHistoryStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSession: ScanSession?
    @State private var navigate = false
    @State private var nearMeEnabled = false
    @State private var nearMeOrigin: (lat: Double, lon: Double)?

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleEntries) { entry in
                    Button {
                        selectedSession = scanHistory.toScanSession(entry)
                        navigate = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.legoBlue.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.legoBlue)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(entry.totalPiecesFound) pieces · \(entry.uniquePieceCount) unique")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let place = entry.placeName, !place.isEmpty {
                                    Label(place, systemImage: "mappin.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if !entry.tags.isEmpty {
                                    HStack(spacing: 4) {
                                        ForEach(entry.tags.prefix(3), id: \.self) { tag in
                                            Text(tag)
                                                .font(.caption2.weight(.medium))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Color.legoBlue.opacity(0.15)))
                                                .foregroundStyle(Color.legoBlue)
                                        }
                                        if entry.tags.count > 3 {
                                            Text("+\(entry.tags.count - 3)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Scan History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if scanHistory.entries.contains(where: { $0.hasLocation }) {
                        Button {
                            toggleNearMe()
                        } label: {
                            Image(systemName: nearMeEnabled ? "location.fill" : "location")
                        }
                        .accessibilityLabel(nearMeEnabled ? "Near Me on" : "Near Me off")

                        NavigationLink(destination: ScanMapView()) {
                            Image(systemName: "map")
                        }
                        .accessibilityLabel("Open scan map")
                    }
                }
            }
            .navigationDestination(isPresented: $navigate) {
                if let session = selectedSession {
                    ScanResultsView(session: session)
                }
            }
            .overlay {
                if scanHistory.entries.isEmpty {
                    ContentUnavailableView(
                        "No Scans Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Your scan history will appear here.")
                    )
                }
            }
        }
    }

    private var visibleEntries: [ScanHistoryStore.HistoryEntry] {
        let sorted = scanHistory.entries.sorted { $0.date > $1.date }
        guard nearMeEnabled, let origin = nearMeOrigin else { return sorted }
        let radiusMeters = ScanSettings.shared.locationFilterRadiusKm * 1_000
        return sorted.filter { entry in
            guard let lat = entry.latitude, let lon = entry.longitude else { return false }
            return LocationDistance.meters(lat1: origin.lat, lon1: origin.lon,
                                           lat2: lat, lon2: lon) <= radiusMeters
        }
    }

    private func toggleNearMe() {
        if nearMeEnabled {
            nearMeEnabled = false
            nearMeOrigin = nil
            return
        }
        Task {
            guard let capture = await ScanLocationService.shared.requestCapture() else { return }
            await MainActor.run {
                nearMeOrigin = (capture.latitude, capture.longitude)
                nearMeEnabled = true
            }
        }
    }
}
