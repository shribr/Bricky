import SwiftUI
import PhotosUI

/// Detail view for a single minifigure: silhouette layout with owned/missing
/// slots, missing-parts list, BrickLink deep links, and ownership toggle.
struct MinifigureDetailView: View {
    let figure: Minifigure
    /// Inventories used for completion calculations (defaults to all).
    var inventories: [InventoryStore.Inventory] = []

    @StateObject private var collectionStore = MinifigureCollectionStore.shared
    @StateObject private var inventoryStore = InventoryStore.shared
    @State private var selectedSlot: MinifigureCollectionStore.SlotStatus?
    @State private var showWantedListShare = false
    @State private var wantedListURL: URL?
    @State private var showZoomImage = false
    @State private var photoPickerItem: PhotosPickerItem?
    @Environment(\.openURL) private var openURL

    private var resolvedInventories: [InventoryStore.Inventory] {
        inventories.isEmpty ? inventoryStore.inventories : inventories
    }

    private var slotStatuses: [MinifigureCollectionStore.SlotStatus] {
        collectionStore.slotStatuses(for: figure, inventories: resolvedInventories)
    }

    private var missingParts: [MinifigurePartRequirement] {
        collectionStore.missingParts(for: figure, inventories: resolvedInventories)
    }

    private var completion: Double {
        collectionStore.completionPercentage(for: figure, inventories: resolvedInventories)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerCard
                silhouetteCard
                if !missingParts.isEmpty {
                    missingPartsCard
                }
                actionsCard
            }
            .padding()
        }
        .navigationTitle(figure.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedSlot) { status in
            slotDetailSheet(status)
        }
        .sheet(isPresented: $showWantedListShare) {
            if let url = wantedListURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showZoomImage) {
            ZoomableImageView(url: figure.imageURL, title: figure.name)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 12) {
            Button {
                showZoomImage = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    MinifigureImageView(url: figure.imageURL)
                        .frame(height: 160)
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .padding(6)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(figure.name) image full screen")

            scanStatusBadge

            Text(figure.name)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = figure.name
                    } label: {
                        Label("Copy Name", systemImage: "doc.on.doc")
                    }
                    Button {
                        let query = "LEGO figurine image of \(figure.name)"
                            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "https://www.google.com/search?tbm=isch&q=\(query)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Search Images", systemImage: "safari")
                    }
                }

            HStack(spacing: 12) {
                tag(figure.theme, icon: "tag.fill")
                if figure.year > 0 { tag("\(figure.year)", icon: "calendar") }
                tag("\(figure.partCount) parts", icon: "cube.fill")
            }

            completionBar
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        )
    }

    @ViewBuilder
    private var scanStatusBadge: some View {
        if collectionStore.isScanComplete(figure) {
            Label("Complete — all parts scanned", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.green))
                .foregroundStyle(.white)
        } else if collectionStore.isScanned(figure.id) {
            let scanned = collectionStore.scannedSlots(for: figure.id).count
            let total = figure.requiredParts.count
            Label("Scanned — \(scanned) / \(total) parts", systemImage: "viewfinder")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.legoBlue))
                .foregroundStyle(.white)
        }
    }

    private var completionBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Completion")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(completion))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(completionColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule()
                        .fill(completionColor)
                        .frame(width: geo.size.width * CGFloat(completion / 100))
                }
            }
            .frame(height: 8)
        }
    }

    private var completionColor: Color {
        if completion >= 90 { return .green }
        if completion >= 50 { return .orange }
        return .red
    }

    private func tag(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
            .foregroundStyle(.secondary)
    }

    // MARK: - Silhouette

    private var silhouetteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Silhouette")
                .font(.headline)

            // Group by anatomical row (displayOrder) and lay out each row.
            let grouped = Dictionary(grouping: slotStatuses, by: { $0.slot.displayOrder })
            let orderedRows = grouped.keys.sorted()

            VStack(spacing: 12) {
                ForEach(orderedRows, id: \.self) { rowKey in
                    if let row = grouped[rowKey] {
                        HStack(spacing: 10) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, status in
                                slotTile(status)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }

    private func slotTile(_ status: MinifigureCollectionStore.SlotStatus) -> some View {
        Button {
            selectedSlot = status
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if status.isOwned {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.legoColor(status.requirement.legoColor))
                        Image(systemName: status.slot.systemImage)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.bestForegroundOn(Color.legoColor(status.requirement.legoColor)))
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.10))
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                            .foregroundStyle(.secondary)
                        Image(systemName: status.slot.systemImage)
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.secondary.opacity(0.55))
                    }
                }
                .frame(width: 56, height: 56)

                Text(status.slot.displayName)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .opacity(status.isOwned ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(status.slot.displayName), \(status.isOwned ? "owned" : "missing")")
    }

    // MARK: - Missing parts

    private var missingPartsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Missing Parts")
                    .font(.headline)
                Spacer()
                Text("\(missingParts.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            }

            ForEach(missingParts, id: \.self) { req in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.legoColor(req.legoColor))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: req.slot.systemImage)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.bestForegroundOn(Color.legoColor(req.legoColor)))
                        )
                        .opacity(0.55)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(req.displayName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text("\(req.color) · part \(req.partNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        // Use search-by-part rather than the direct catalogitem.page —
                        // many minifig parts (printed torsos, decorated heads) have
                        // compound part numbers that don't resolve as a single
                        // catalog page. Search always returns hits.
                        if let url = BrickLinkService.partSearchURL(req.partNumber) {
                            openURL(url)
                        }
                    } label: {
                        Image(systemName: "link")
                            .font(.caption)
                            .padding(8)
                            .background(Capsule().fill(Color.legoBlue.opacity(0.15)))
                            .foregroundStyle(Color.legoBlue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search BrickLink for \(req.displayName)")
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
    }

    // MARK: - Actions

    private var actionsCard: some View {
        VStack(spacing: 10) {
            Button {
                if let url = BrickLinkService.rebrickableMinifigureURL(figure.id) {
                    openURL(url)
                }
            } label: {
                Label("View on Rebrickable", systemImage: "link")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.legoBlue, Color.legoBlue.opacity(0.8)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button {
                if let url = BrickLinkService.brickLinkMinifigureSearchURL(name: figure.name) {
                    openURL(url)
                }
            } label: {
                Label("Search on BrickLink", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
            }

            if !missingParts.isEmpty {
                Button {
                    exportWantedList()
                } label: {
                    Label("Export Missing as Wanted List", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
                }
            }

            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                Label(figure.imageURL == nil ? "Add Photo" : "Change Photo",
                      systemImage: "photo.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
            }
            .onChange(of: photoPickerItem) { _, newItem in
                Task { await loadAndSavePickedPhoto(newItem) }
            }

            Button {
                collectionStore.toggleOwned(figure.id)
            } label: {
                Label(collectionStore.isOwned(figure.id) ? "Remove from Collection" : "Mark as Owned",
                      systemImage: collectionStore.isOwned(figure.id) ? "checkmark.seal.fill" : "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
                    .foregroundStyle(collectionStore.isOwned(figure.id) ? Color.green : .primary)
            }
        }
    }

    // MARK: - Slot detail sheet

    private func slotDetailSheet(_ status: MinifigureCollectionStore.SlotStatus) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.legoColor(status.requirement.legoColor))
                        .opacity(status.isOwned ? 1 : 0.35)
                        .frame(width: 120, height: 120)
                    Image(systemName: status.slot.systemImage)
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundStyle(Color.bestForegroundOn(Color.legoColor(status.requirement.legoColor)))
                        .opacity(status.isOwned ? 1 : 0.55)
                }

                VStack(spacing: 4) {
                    Text(status.requirement.displayName)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("Slot · \(status.slot.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    detailStat(label: "Part", value: status.requirement.partNumber)
                    detailStat(label: "Color", value: status.requirement.color)
                    detailStat(label: status.isOwned ? "Owned" : "Missing",
                               value: "\(status.haveQuantity)/\(status.requirement.quantity)")
                }

                VStack(spacing: 10) {
                    Button {
                        if let url = BrickLinkService.partSearchURL(status.requirement.partNumber) {
                            openURL(url)
                        }
                    } label: {
                        Label("Find on BrickLink", systemImage: "link")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [Color.legoBlue, Color.legoBlue.opacity(0.8)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        if let url = BrickLinkService.partSearchURL(status.requirement.partNumber) {
                            openURL(url)
                        }
                    } label: {
                        Label("Check Price", systemImage: "dollarsign.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
                    }
                }
                .padding(.top, 8)

                Spacer()
            }
            .padding()
            .navigationTitle(status.slot.displayName)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func detailStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
    }

    // MARK: - Wanted-list export

    private func exportWantedList() {
        // Convert missing parts → InventoryStore.InventoryPiece, then reuse
        // InventoryExporter.brickLinkXMLFileURL.
        let pieces = missingParts.map { req in
            InventoryStore.InventoryPiece(
                partNumber: req.partNumber,
                name: req.displayName,
                category: .minifigure,
                color: req.legoColor,
                quantity: req.quantity,
                dimensions: PieceDimensions(studsWide: 1, studsLong: 1, heightUnits: 1)
            )
        }
        let inv = InventoryStore.Inventory(
            id: UUID(),
            name: "\(figure.name) — Missing Parts",
            pieces: pieces,
            createdAt: Date(),
            updatedAt: Date()
        )
        wantedListURL = InventoryExporter.brickLinkXMLFileURL(from: inv)
        if wantedListURL != nil {
            showWantedListShare = true
        }
    }

    private func loadAndSavePickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpegData = image.jpegData(compressionQuality: 0.85) else { return }

            let fm = FileManager.default
            let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("UserMinifigureImages", isDirectory: true)
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let filename = "\(figure.id.replacingOccurrences(of: "/", with: "_"))_\(UUID().uuidString.prefix(8)).jpg"
            let fileURL = dir.appendingPathComponent(filename)
            try jpegData.write(to: fileURL, options: .atomic)

            // Update catalog with the local file URL
            MinifigureCatalog.shared.updateFigureImage(
                id: figure.id,
                imageURL: fileURL.absoluteString
            )
            // Clear any cached images so the new one loads
            if figure.imageURL != nil {
                MinifigureImageCache.shared.clear()
            }
        } catch {
            // Silently fail — user can try again
        }
    }
}
