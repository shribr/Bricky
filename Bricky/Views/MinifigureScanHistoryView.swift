import SwiftUI

/// Displays the user's minifigure scan history with the original captured images.
struct MinifigureScanHistoryView: View {
    @StateObject private var store = MinifigureScanHistoryStore.shared
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var selectedEntry: MinifigureScanHistoryStore.ScanEntry?

    var body: some View {
        Group {
            if store.entries.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        .navigationTitle("Scan History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.entries.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            store.deleteAll()
                        } label: {
                            Label("Clear All History", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            MinifigureScanHistoryDetailSheet(entry: entry)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "No Scan History",
            systemImage: "clock.arrow.circlepath",
            description: Text("Your minifigure scan results will appear here.")
        )
    }

    // MARK: - List

    private var historyList: some View {
        List {
            ForEach(store.entries) { entry in
                Button {
                    selectedEntry = entry
                } label: {
                    scanEntryRow(entry)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.delete(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func scanEntryRow(_ entry: MinifigureScanHistoryStore.ScanEntry) -> some View {
        HStack(spacing: 12) {
            // Captured scan thumbnail
            scanThumbnail(for: entry)
                .frame(width: 56, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.minifigureName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if !entry.theme.isEmpty {
                        Text(entry.theme)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if entry.year > 0 {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(entry.year)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Text(entry.date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if entry.confirmed {
                        Label("Confirmed", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Label("Rejected", systemImage: "xmark.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(spacing: 2) {
                Text("\(Int(entry.confidence * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(confidenceColor(entry.confidence))
                Text("match")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func scanThumbnail(for entry: MinifigureScanHistoryStore.ScanEntry) -> some View {
        if let image = store.capturedImage(for: entry) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.15))
                .overlay {
                    Image(systemName: "camera")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func confidenceColor(_ c: Double) -> Color {
        if c >= 0.75 { return .green }
        if c >= 0.5 { return .orange }
        return .red
    }
}

// MARK: - Detail sheet

/// Shows the full captured image alongside the catalog match for a past scan.
private struct MinifigureScanHistoryDetailSheet: View {
    let entry: MinifigureScanHistoryStore.ScanEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Side-by-side images
                    HStack(alignment: .top, spacing: 12) {
                        imageTile(title: "Your Scan") {
                            if let image = MinifigureScanHistoryStore.shared.capturedImage(for: entry) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            } else {
                                Image(systemName: "camera")
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        imageTile(title: "Catalog") {
                            if let url = entry.imageURL {
                                MinifigureImageView(url: url)
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            } else {
                                Image(systemName: "person.fill.questionmark")
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Details
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.minifigureName)
                            .font(.title3.weight(.semibold))

                        HStack(spacing: 8) {
                            if !entry.theme.isEmpty {
                                Label(entry.theme, systemImage: "tag.fill")
                            }
                            if entry.year > 0 {
                                Label("\(entry.year)", systemImage: "calendar")
                            }
                            Label("\(Int(entry.confidence * 100))% match",
                                  systemImage: "checkmark.seal.fill")
                                .foregroundStyle(entry.confidence >= 0.75 ? .green : entry.confidence >= 0.5 ? .orange : .red)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            if entry.confirmed {
                                Label("Added to collection", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Label("Not confirmed", systemImage: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.footnote)

                        Text(entry.date, format: .dateTime.month().day().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        if !entry.reasoning.isEmpty {
                            Text(entry.reasoning)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Scan Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private func imageTile<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity)
    }
}
