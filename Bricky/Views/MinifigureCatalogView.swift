import SwiftUI

/// Browses the full minifigure catalog (~16K figures) with search, filter,
/// and an adaptive grid (2 cols portrait / 4 cols landscape on iPhone, more
/// on iPad).
struct MinifigureCatalogView: View {
    @StateObject private var catalog = MinifigureCatalog.shared
    @StateObject private var collectionStore = MinifigureCollectionStore.shared
    @StateObject private var inventoryStore = InventoryStore.shared

    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var selectedThemes: Set<String> = []
    @State private var selectedYearRange: ClosedRange<Int>?
    @State private var ownershipFilter: MinifigureCatalog.OwnershipFilter = .all
    @State private var imageFilter: MinifigureCatalog.ImageFilter = .all
    @State private var sort: MinifigureCatalog.SortOrder = .nameAsc
    @State private var showFilters = false
    @State private var showScan = false
    @State private var searchTask: Task<Void, Never>?
    /// Set by the .minifigureScanCompleted notification to push the catalog
    /// straight into the detail view of the figure the user just scanned.
    @State private var pushedFigure: Minifigure?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        Group {
            if !catalog.isLoaded {
                loadingView
            } else {
                contentView
            }
        }
        .navigationTitle("Minifigures")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    Button { showScan = true } label: {
                        Image(systemName: "viewfinder.circle.fill")
                            .accessibilityLabel("Identify by Scan")
                    }
                    Button { showFilters = true } label: {
                        Image(systemName: filtersActive
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                            .accessibilityLabel("Filters")
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search by name, theme, or fig ID")
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                debouncedSearch = newValue
            }
        }
        .sheet(isPresented: $showFilters) {
            filterSheet
        }
        .fullScreenCover(isPresented: $showScan) {
            MinifigureScanView()
        }
        .navigationDestination(item: $pushedFigure) { fig in
            MinifigureDetailView(figure: fig)
        }
        .onReceive(NotificationCenter.default.publisher(for: .minifigureScanCompleted)) { note in
            guard let id = note.userInfo?["minifigId"] as? String else { return }
            // Catalog must be loaded for figure(id:) to resolve.
            Task {
                await catalog.load()
                if let fig = catalog.figure(id: id) {
                    pushedFigure = fig
                }
            }
        }
        .task {
            await catalog.load()
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading minifigure catalog…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let err = catalog.loadError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private var contentView: some View {
        let figures = filteredFigures
        return ScrollView {
            VStack(spacing: 12) {
                if figures.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(figures) { fig in
                            NavigationLink {
                                MinifigureDetailView(figure: fig)
                            } label: {
                                tile(fig)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Text("\(figures.count) figures")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Minifigures",
            systemImage: "person.fill.questionmark",
            description: Text("Try adjusting your filters or search.")
        )
        .padding(.top, 60)
    }

    // MARK: - Tile

    private func tile(_ fig: Minifigure) -> some View {
        let completion = collectionStore.completionPercentage(for: fig,
                                                              inventories: inventoryStore.inventories)
        let isOwned = collectionStore.isOwned(fig.id)
        let isScanned = collectionStore.isScanned(fig.id)
        let isComplete = collectionStore.isScanComplete(fig)

        return VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                MinifigureImageView(url: fig.imageURL)
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .trailing, spacing: 4) {
                    if isComplete {
                        badge(text: "Complete", icon: "checkmark.circle.fill", color: .green)
                    } else if isScanned {
                        badge(text: "Scanned", icon: "viewfinder", color: Color.legoBlue)
                    }
                    if isOwned && !isScanned {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .background(Circle().fill(.background))
                    }
                }
                .padding(6)
            }

            Text(fig.name)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(spacing: 4) {
                Text(fig.theme)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if fig.year > 0 {
                    Text("· \(String(fig.year))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            // Mini completion bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule()
                        .fill(completionColor(completion))
                        .frame(width: geo.size.width * CGFloat(completion / 100))
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 4)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
    }


    private func completionColor(_ pct: Double) -> Color {
        if pct >= 90 { return .green }
        if pct >= 50 { return .orange }
        if pct > 0 { return .yellow }
        return .secondary
    }

    private func badge(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(color))
        .foregroundStyle(.white)
    }

    // MARK: - Filtering

    private var filtersActive: Bool {
        !selectedThemes.isEmpty
            || selectedYearRange != nil
            || ownershipFilter != .all
            || imageFilter != .all
            || sort != .nameAsc
    }

    private var filteredFigures: [Minifigure] {
        var results = catalog.search(query: debouncedSearch,
                                     themes: selectedThemes,
                                     yearRange: selectedYearRange,
                                     sort: sort)

        if ownershipFilter != .all {
            results = results.filter { fig in
                let owned = collectionStore.isOwned(fig.id)
                let completion = collectionStore.completionPercentage(
                    for: fig,
                    inventories: inventoryStore.inventories
                )
                switch ownershipFilter {
                case .all: return true
                case .owned: return owned
                case .complete: return completion >= 100
                case .inProgress: return completion > 0 && completion < 100
                case .notStarted: return completion == 0 && !owned
                }
            }
        }

        switch imageFilter {
        case .all: break
        case .withImages:
            results = results.filter { $0.imageURL != nil }
        case .missingImages:
            results = results.filter { $0.imageURL == nil }
        }

        if sort == .completionDesc {
            results.sort { lhs, rhs in
                let l = collectionStore.completionPercentage(for: lhs,
                                                             inventories: inventoryStore.inventories)
                let r = collectionStore.completionPercentage(for: rhs,
                                                             inventories: inventoryStore.inventories)
                return l > r
            }
        }
        return results
    }

    // MARK: - Filter sheet

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Sort") {
                    Picker("Sort by", selection: $sort) {
                        ForEach(MinifigureCatalog.SortOrder.allCases, id: \.self) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Ownership") {
                    Picker("Show", selection: $ownershipFilter) {
                        ForEach(MinifigureCatalog.OwnershipFilter.allCases, id: \.self) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Images") {
                    Picker("Show", selection: $imageFilter) {
                        ForEach(MinifigureCatalog.ImageFilter.allCases, id: \.self) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Year range") {
                    Toggle("Filter by year", isOn: Binding(
                        get: { selectedYearRange != nil },
                        set: { newValue in
                            selectedYearRange = newValue ? catalog.yearRange : nil
                        }
                    ))

                    if let range = selectedYearRange {
                        VStack(alignment: .leading) {
                            Text("\(range.lowerBound) – \(range.upperBound)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            // Two-thumb sliders are noisy in stock SwiftUI;
                            // use steppers for a calm UX.
                            Stepper("From: \(range.lowerBound)",
                                    value: Binding(
                                        get: { range.lowerBound },
                                        set: { newLower in
                                            let upper = max(newLower, range.upperBound)
                                            selectedYearRange = newLower...upper
                                        }
                                    ),
                                    in: catalog.yearRange.lowerBound...range.upperBound)
                            Stepper("To: \(range.upperBound)",
                                    value: Binding(
                                        get: { range.upperBound },
                                        set: { newUpper in
                                            let lower = min(range.lowerBound, newUpper)
                                            selectedYearRange = lower...newUpper
                                        }
                                    ),
                                    in: range.lowerBound...catalog.yearRange.upperBound)
                        }
                    }
                }

                Section("Themes (\(selectedThemes.count) selected)") {
                    ForEach(catalog.themes, id: \.self) { theme in
                        Button {
                            if selectedThemes.contains(theme) {
                                selectedThemes.remove(theme)
                            } else {
                                selectedThemes.insert(theme)
                            }
                        } label: {
                            HStack {
                                Text(theme)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedThemes.contains(theme) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Reset Filters", role: .destructive) {
                        selectedThemes.removeAll()
                        selectedYearRange = nil
                        ownershipFilter = .all
                        imageFilter = .all
                        sort = .nameAsc
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFilters = false }
                }
            }
        }
        .presentationDetents([.large])
    }
}
