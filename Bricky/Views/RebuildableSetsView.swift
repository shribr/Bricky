import SwiftUI

/// **Sets You Can Rebuild** — Tier A of the pile→sets vision (no ML). For each
/// set the user owns, shows how much of it their scanned inventory covers and
/// which parts are missing, powered by `SetCompletionEngine` + real Rebrickable
/// BOMs. Honest: sets whose parts can't be fetched are simply omitted.
struct RebuildableSetsView: View {
    @StateObject private var viewModel = RebuildableSetsViewModel()
    @ObservedObject private var collectionStore = SetCollectionStore.shared
    @ObservedObject private var inventoryStore = InventoryStore.shared

    @State private var selected: RebuildableSetsViewModel.Row?

    private let contentMaxWidth: CGFloat = 640

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading, .idle:
                ProgressView("Checking your sets…")
            case .notConfigured:
                message(
                    icon: "key",
                    title: "Add a Rebrickable Key",
                    detail: "Add a Rebrickable API key in Settings to fetch set parts and compute what you can build."
                )
            case .empty:
                message(
                    icon: "shippingbox",
                    title: "No Owned Sets Yet",
                    detail: "Add sets to your collection, then come back to see which ones you can rebuild."
                )
            case .failed(let detail):
                message(icon: "wifi.slash", title: "Couldn't Load Sets", detail: detail)
            case .loaded:
                list
            }
        }
        .navigationTitle("Sets You Can Rebuild")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .sheet(item: $selected) { row in
            MissingPartsSheet(row: row)
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("\(viewModel.fullyBuildableCount) of \(viewModel.evaluatedSetCount) owned sets fully buildable")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(viewModel.rows) { row in
                    Button { selected = row } label: { RebuildRow(row: row) }
                        .buttonStyle(.plain)
                }
            }
            .padding()
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private func message(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: contentMaxWidth)
    }

    private func reload() async {
        let owned = collectionStore.collection.filter(\.owned).map(\.setNumber)
        let counts = RebuildableSetsViewModel.ownedCounts(from: inventoryStore.inventories)
        await viewModel.load(ownedSetNumbers: owned, ownedCounts: counts)
    }
}

private struct RebuildRow: View {
    let row: RebuildableSetsViewModel.Row

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("#\(row.setNumber)")
                    .font(.caption).foregroundStyle(.secondary)
                ProgressView(value: row.completion.coverage)
                    .tint(row.completion.isComplete ? .green : Color.legoBlue)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.completion.percentText)
                    .font(.headline)
                    .foregroundStyle(row.completion.isComplete ? .green : Color.legoBlue)
                if !row.completion.isComplete {
                    Text("\(row.completion.missingPieceCount) missing")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Fixed-header/footer sheet listing the parts still missing for a set.
private struct MissingPartsSheet: View {
    let row: RebuildableSetsViewModel.Row
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if row.completion.missing.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.largeTitle).foregroundStyle(.green)
                        Text("You can build this set!").font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(row.completion.missing, id: \.self) { piece in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("#\(piece.partNumber)")
                                    .font(.subheadline.weight(.semibold))
                                Text(piece.color.capitalized)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Need \(piece.shortBy)")
                                .font(.subheadline)
                                .foregroundStyle(Color.legoBlue)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .navigationTitle(row.completion.percentText + " • " + row.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
