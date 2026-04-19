import SwiftUI

/// Sprint 2 / B2 + B3 — Picker that lets the user choose one or more saved
/// scan sessions and highlights occurrences of a specific piece type in
/// each chosen scan's pile photo.
///
/// Single-select tap → opens `PileResultsSheetView` filtered to the target piece.
/// Multi-select tap "Show Results" → opens `MultiScanFindResultsView` (grid).
struct FindInSavedScanPickerView: View {
    /// The piece the user wants to find. We match by `partNumber`.
    let targetPiece: LegoPiece

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var history = ScanHistoryStore.shared

    @State private var multiSelect = false
    @State private var selectedScanIDs: Set<UUID> = []

    @State private var singleResultSession: ScanSession?
    @State private var multiResultSessions: [ScanSession] = []
    @State private var showMultiResults = false

    /// Saved scans that contain at least one matching piece.
    private var matchingEntries: [ScanHistoryStore.HistoryEntry] {
        history.entries.filter { entry in
            entry.pieces.contains { $0.partNumber == targetPiece.partNumber }
        }
    }

    private var nonMatchingEntries: [ScanHistoryStore.HistoryEntry] {
        history.entries.filter { entry in
            !entry.pieces.contains { $0.partNumber == targetPiece.partNumber }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    ContentUnavailableView(
                        "No Saved Scans",
                        systemImage: "tray",
                        description: Text("Save a scan first, then come back to find pieces in it.")
                    )
                } else if matchingEntries.isEmpty {
                    ContentUnavailableView {
                        Label("Not Found", systemImage: "magnifyingglass")
                    } description: {
                        Text("No saved scan contains \(targetPiece.name).")
                    } actions: {
                        Button("Show All Scans Anyway") {
                            // Force-display all entries by toggling something
                            // simple — easier path: just leave list visible.
                        }
                        .buttonStyle(.bordered)
                        .disabled(true)
                    }
                } else {
                    scanList
                }
            }
            .navigationTitle("Find \(targetPiece.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                if !matchingEntries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(multiSelect ? "Done" : "Select Multiple") {
                            multiSelect.toggle()
                            if !multiSelect { selectedScanIDs.removeAll() }
                        }
                    }
                }
                if multiSelect && !selectedScanIDs.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Show Results (\(selectedScanIDs.count))") {
                            openMultiResults()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .sheet(item: $singleResultSession) { session in
                PileResultsSheetView(session: session,
                                     highlightPartNumber: targetPiece.partNumber)
            }
            .fullScreenCover(isPresented: $showMultiResults) {
                MultiScanFindResultsView(sessions: multiResultSessions,
                                         targetPiece: targetPiece)
            }
        }
    }

    // MARK: - List

    private var scanList: some View {
        List {
            Section {
                ForEach(matchingEntries) { entry in
                    scanRow(entry)
                }
            } header: {
                Text("\(matchingEntries.count) scan\(matchingEntries.count == 1 ? "" : "s") with this piece")
            }
            if !nonMatchingEntries.isEmpty {
                Section {
                    ForEach(nonMatchingEntries) { entry in
                        scanRow(entry, isMatching: false)
                    }
                } header: {
                    Text("Other saved scans (no match)")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func scanRow(_ entry: ScanHistoryStore.HistoryEntry, isMatching: Bool = true) -> some View {
        let matchingCount = entry.pieces
            .filter { $0.partNumber == targetPiece.partNumber }
            .reduce(0) { $0 + $1.quantity }
        let isSelected = selectedScanIDs.contains(entry.id)

        return Button {
            handleTap(entry)
        } label: {
            HStack(spacing: 12) {
                if multiSelect && isMatching {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .font(.title3)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.placeName ?? entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text("\(entry.totalPiecesFound) pieces")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isMatching {
                            Text("· \(matchingCount) match\(matchingCount == 1 ? "" : "es")")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.legoGreen)
                        }
                    }
                }
                Spacer()
                if isMatching && !multiSelect {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .disabled(!isMatching)
    }

    private func handleTap(_ entry: ScanHistoryStore.HistoryEntry) {
        if multiSelect {
            if selectedScanIDs.contains(entry.id) {
                selectedScanIDs.remove(entry.id)
            } else {
                selectedScanIDs.insert(entry.id)
            }
        } else {
            singleResultSession = history.toScanSession(entry)
        }
    }

    private func openMultiResults() {
        let sessions = matchingEntries
            .filter { selectedScanIDs.contains($0.id) }
            .map { history.toScanSession($0) }
        guard !sessions.isEmpty else { return }
        multiResultSessions = sessions
        showMultiResults = true
    }
}
