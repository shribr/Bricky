import SwiftUI

/// Sprint 5 / F1 — Pick a baseline saved scan to compare against `current`,
/// then show added/removed/changed pieces.
///
/// Two-step UI: list of saved scans → diff result.
struct PileDiffView: View {
    /// The scan being treated as "current" (typically just-finished or the
    /// session the user is viewing).
    let currentSession: ScanSession

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var history = ScanHistoryStore.shared

    @State private var baselineEntry: ScanHistoryStore.HistoryEntry?

    var body: some View {
        NavigationStack {
            Group {
                if let baseline = baselineEntry {
                    diffResultView(baseline: baseline)
                } else {
                    pickerView
                }
            }
            .navigationTitle(baselineEntry == nil ? "Compare Scans" : "Pile Diff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if baselineEntry != nil {
                        Button {
                            baselineEntry = nil
                        } label: {
                            Label("Pick Different Scan", systemImage: "chevron.left")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Picker

    private var pickerView: some View {
        Group {
            let candidates = history.entries.filter { $0.id != currentSession.id }
            if candidates.isEmpty {
                ContentUnavailableView(
                    "Need Two Scans",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Save another scan, then come back to compare.")
                )
            } else {
                List {
                    Section {
                        ForEach(candidates) { entry in
                            Button {
                                baselineEntry = entry
                            } label: {
                                rowLabel(entry)
                            }
                        }
                    } header: {
                        Text("Compare \(currentSession.totalPiecesFound) current pieces against:")
                            .textCase(nil)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func rowLabel(_ entry: ScanHistoryStore.HistoryEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill")
                .font(.title3)
                .foregroundStyle(Color.legoBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.placeName ?? entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.medium))
                Text("\(entry.totalPiecesFound) pieces · \(entry.uniquePieceCount) unique")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Diff result

    private func diffResultView(baseline: ScanHistoryStore.HistoryEntry) -> some View {
        let result = PileDiffService.diff(baseline: baseline.pieces,
                                          current: currentSession.pieces)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryHeader(baseline: baseline, result: result)

                if !result.added.isEmpty {
                    diffSection(title: "Added",
                                systemImage: "plus.circle.fill",
                                tint: Color.legoGreen,
                                entries: result.added,
                                showQuantityAs: .current)
                }
                if !result.removed.isEmpty {
                    diffSection(title: "Removed",
                                systemImage: "minus.circle.fill",
                                tint: .red,
                                entries: result.removed,
                                showQuantityAs: .baseline)
                }
                if !result.increased.isEmpty {
                    diffSection(title: "More than before",
                                systemImage: "arrow.up.circle.fill",
                                tint: Color.legoBlue,
                                entries: result.increased,
                                showQuantityAs: .delta)
                }
                if !result.decreased.isEmpty {
                    diffSection(title: "Fewer than before",
                                systemImage: "arrow.down.circle.fill",
                                tint: Color.legoYellow,
                                entries: result.decreased,
                                showQuantityAs: .delta)
                }
                if !result.unchanged.isEmpty {
                    DisclosureGroup {
                        diffEntryList(result.unchanged, showQuantityAs: .current)
                    } label: {
                        Label("Unchanged (\(result.unchanged.count))",
                              systemImage: "equal.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    private func summaryHeader(baseline: ScanHistoryStore.HistoryEntry,
                               result: PileDiffService.DiffResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comparing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(baseline.placeName ?? baseline.date.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline.weight(.medium))
            Text("→ \(currentSession.placeName ?? currentSession.startedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                statChip(label: "Added", value: result.totalAdded, color: Color.legoGreen)
                statChip(label: "Removed", value: result.totalRemoved, color: .red)
                statChip(label: "Net", value: result.netDelta, color: Color.legoBlue)
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
        .padding(.horizontal)
    }

    private func statChip(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value > 0 ? "+\(value)" : "\(value)")
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private enum QuantityDisplay { case current, baseline, delta }

    private func diffSection(title: String, systemImage: String, tint: Color,
                             entries: [PileDiffService.DiffEntry],
                             showQuantityAs: QuantityDisplay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(title) (\(entries.count))", systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal)
            diffEntryList(entries, showQuantityAs: showQuantityAs)
        }
    }

    private func diffEntryList(_ entries: [PileDiffService.DiffEntry],
                               showQuantityAs: QuantityDisplay) -> some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.legoColor(entry.representativePiece.color))
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.representativePiece.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text("\(entry.representativePiece.color.rawValue) · \(entry.representativePiece.dimensions.displayString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    quantityLabel(for: entry, mode: showQuantityAs)
                }
                .padding(.vertical, 6)
                .padding(.horizontal)
                Divider().padding(.leading, 52)
            }
        }
    }

    private func quantityLabel(for entry: PileDiffService.DiffEntry,
                               mode: QuantityDisplay) -> some View {
        Group {
            switch mode {
            case .current:
                Text("×\(entry.currentQuantity)")
                    .font(.subheadline.weight(.semibold))
            case .baseline:
                Text("×\(entry.baselineQuantity)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            case .delta:
                let sign = entry.delta > 0 ? "+" : ""
                Text("\(sign)\(entry.delta) (\(entry.baselineQuantity)→\(entry.currentQuantity))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(entry.delta > 0 ? Color.legoBlue : Color.legoYellow)
            }
        }
    }
}
