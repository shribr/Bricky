import SwiftUI
import UniformTypeIdentifiers

/// Full-screen modal listing every saved inventory.
/// Hosts the Import action (moved out of HomeView).
struct AllInventoriesView: View {
    @StateObject private var inventoryStore = InventoryStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showImportPicker = false
    @State private var importError: String?
    @State private var showImportError = false
    @State private var importedCount: Int = 0
    @State private var showImportSuccess = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedInventories) { inventory in
                    NavigationLink(value: inventory.id) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.legoOrange.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "tray.full.fill")
                                    .font(.body)
                                    .foregroundStyle(Color.legoOrange)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(inventory.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("\(inventory.totalPieces) total · \(inventory.uniquePieces) unique")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Updated \(inventory.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved Inventories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showImportPicker = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import inventory")
                }
            }
            .navigationDestination(for: UUID.self) { inventoryId in
                InventoryDetailView(inventoryId: inventoryId)
            }
            .overlay {
                if inventoryStore.inventories.isEmpty {
                    ContentUnavailableView(
                        "No Saved Inventories",
                        systemImage: "tray",
                        description: Text("Imported and saved inventories will appear here.")
                    )
                }
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.commaSeparatedText, .xml],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let didAccess = url.startAccessingSecurityScopedResource()
                    defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let pieces = try InventoryImporter.importFile(at: url)
                        let name = url.deletingPathExtension().lastPathComponent
                        let invId = inventoryStore.createInventory(name: name)
                        inventoryStore.addPieces(pieces, to: invId)
                        importedCount = pieces.count
                        showImportSuccess = true
                    } catch {
                        importError = error.localizedDescription
                        showImportError = true
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                    showImportError = true
                }
            }
            .alert("Import Failed", isPresented: $showImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "Unknown error")
            }
            .alert("Import Successful", isPresented: $showImportSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Imported \(importedCount) pieces into a new inventory.")
            }
        }
    }

    private var sortedInventories: [InventoryStore.Inventory] {
        inventoryStore.inventories.sorted { $0.updatedAt > $1.updatedAt }
    }
}
