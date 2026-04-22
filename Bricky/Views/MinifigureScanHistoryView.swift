import SwiftUI

/// Displays the user's minifigure scan history with the original captured images.
///
/// Features:
/// - Enhanced subject photo thumbnail per row
/// - Multi-select edit mode with select all / deselect all + bulk delete
/// - Swipe-to-delete individual entries
/// - Re-scan: re-run identification from a saved image
struct MinifigureScanHistoryView: View {
    @StateObject private var store = MinifigureScanHistoryStore.shared
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var selectedEntry: MinifigureScanHistoryStore.ScanEntry?
    @State private var isEditing = false
    @State private var selectedIds: Set<UUID> = []
    @State private var rescanEntry: MinifigureScanHistoryStore.ScanEntry?
    @State private var showDeleteConfirmation = false

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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(isEditing ? "Done" : "Edit") {
                        withAnimation {
                            isEditing.toggle()
                            if !isEditing { selectedIds.removeAll() }
                        }
                    }
                }
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
            MinifigureScanHistoryDetailSheet(
                entry: entry,
                onRescan: { rescanEntry = $0 }
            )
        }
        .fullScreenCover(item: $rescanEntry) { entry in
            if let image = store.capturedImage(for: entry) {
                NavigationStack {
                    MinifigureScanView(preCapturedImage: image, skipEnhancement: true)
                }
            }
        }
        .confirmationDialog(
            "Delete \(selectedIds.count) scan\(selectedIds.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                store.delete(selectedIds)
                selectedIds.removeAll()
                if store.entries.isEmpty { isEditing = false }
            }
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
        VStack(spacing: 0) {
            if isEditing {
                editBar
            }
            List {
                ForEach(store.entries) { entry in
                    HStack(spacing: 10) {
                        if isEditing {
                            Image(systemName: selectedIds.contains(entry.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIds.contains(entry.id) ? .blue : .secondary)
                                .font(.title3)
                                .onTapGesture { toggleSelection(entry.id) }
                        }
                        Button {
                            if isEditing {
                                toggleSelection(entry.id)
                            } else {
                                selectedEntry = entry
                            }
                        } label: {
                            scanEntryRow(entry)
                        }
                        .buttonStyle(.plain)
                    }
                    .swipeActions(edge: .trailing) {
                        if !isEditing {
                            Button(role: .destructive) {
                                store.delete(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if !isEditing {
                            Button {
                                rescanEntry = entry
                            } label: {
                                Label("Re-scan", systemImage: "arrow.trianglehead.2.counterclockwise.rotate.90")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable {
                store.reload()
            }
        }
    }

    // MARK: - Edit bar (select all / delete selected)

    private var editBar: some View {
        HStack {
            Button {
                if selectedIds.count == store.entries.count {
                    selectedIds.removeAll()
                } else {
                    selectedIds = Set(store.entries.map(\.id))
                }
            } label: {
                let allSelected = selectedIds.count == store.entries.count
                Text(allSelected ? "Deselect All" : "Select All")
                    .font(.subheadline.weight(.semibold))
            }

            Spacer()

            if !selectedIds.isEmpty {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete (\(selectedIds.count))", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    // MARK: - Row

    private func scanEntryRow(_ entry: MinifigureScanHistoryStore.ScanEntry) -> some View {
        HStack(spacing: 12) {
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

                Text(entry.date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                VStack(spacing: 2) {
                    Text("\(Int(entry.confidence * 100))%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(confidenceColor(entry.confidence))
                    Text("match")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

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

            if !isEditing {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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
    var onRescan: ((MinifigureScanHistoryStore.ScanEntry) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var showFullScreenImage = false

    private var hasCapturedImage: Bool {
        MinifigureScanHistoryStore.shared.capturedImage(for: entry) != nil
    }

    private var capturedImage: UIImage? {
        MinifigureScanHistoryStore.shared.capturedImage(for: entry)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Analysis-style banner with embedded scan photo
                    analysisBanner

                    // Side-by-side images
                    HStack(alignment: .top, spacing: 12) {
                        imageTile(title: "Your Scan") {
                            if let image = capturedImage {
                                Button {
                                    showFullScreenImage = true
                                } label: {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .clipped()
                                }
                                .buttonStyle(.plain)
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

                        if !entry.reasoning.isEmpty {
                            Text(entry.reasoning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Spacer()
                            if entry.confirmed {
                                Label("Added to collection", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Label("Not confirmed", systemImage: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.footnote)

                        Text(entry.date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.tertiary)


                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))

                    // Re-scan button
                    if hasCapturedImage {
                        Button {
                            dismiss()
                            // Small delay so the sheet dismisses before the
                            // fullScreenCover is presented.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                onRescan?(entry)
                            }
                        } label: {
                            Label("Re-scan This Image", systemImage: "arrow.trianglehead.2.counterclockwise.rotate.90")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
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
        .fullScreenCover(isPresented: $showFullScreenImage) {
            SubjectFullScreenView(image: capturedImage)
        }
    }

    // MARK: - Analysis banner

    private var analysisBanner: some View {
        Button {
            if capturedImage != nil {
                showFullScreenImage = true
            }
        } label: {
            HStack(spacing: 12) {
                if let img = capturedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 70, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        )
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(displaySummary)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    Text(displayDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Use the rich analysis summary if available, otherwise fall back to the entry name.
    private var displaySummary: String {
        if !entry.analysisSummary.isEmpty {
            return entry.analysisSummary
        }
        return entry.minifigureName
    }

    /// Use the rich analysis detail if available, otherwise fall back to reasoning.
    private var displayDetail: String {
        if !entry.analysisDetail.isEmpty {
            return entry.analysisDetail
        }
        return entry.reasoning
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
