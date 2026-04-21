import SwiftUI
import UniformTypeIdentifiers

/// Home view with main navigation hub
struct HomeView: View {
    @StateObject private var cameraViewModel = CameraViewModel()
    @StateObject private var inventoryStore = InventoryStore.shared
    @StateObject private var scanHistory = ScanHistoryStore.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var authService = AuthenticationService.shared
    @State private var showingDemoMode = false
    @State private var selectedHistorySession: ScanSession?
    @State private var navigateToHistory = false
    @State private var showImportPicker = false
    @State private var importError: String?
    @State private var showImportError = false
    @State private var importedCount: Int = 0
    @State private var showImportSuccess = false
    @State private var showingPhotoScan = false
    /// Sprint C — geolocation. When true, scan history is filtered to entries
    /// within `ScanSettings.locationFilterRadiusKm` of the user's current
    /// location.
    @State private var nearMeEnabled = false
    @State private var nearMeOrigin: (lat: Double, lon: Double)?
    /// Sprint 5 / F2 — active tag filter (single tag at a time keeps the UI calm).
    @State private var activeTagFilter: String?
    /// Sprint 5 / F2 — history entry currently being tagged.
    @State private var taggingEntryID: UUID?
    /// Full-screen modals for the complete history / inventory lists.
    @State private var showAllScanHistory = false
    @State private var showAllInventories = false
    /// User profile sheet shown from the avatar button.
    @State private var showProfile = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero section
                heroSection

                // Quick actions
                quickActions

                // Recent session (if pieces exist)
                if !cameraViewModel.scanSession.pieces.isEmpty {
                    recentSession
                }

                // Scan history
                if !scanHistory.entries.isEmpty {
                    scanHistorySection
                }

                // Saved inventories
                if !inventoryStore.inventories.isEmpty {
                    savedInventories
                }

                // Minifigures
                minifiguresSection

                // Minifigure scan history
                if !MinifigureScanHistoryStore.shared.entries.isEmpty {
                    minifigureScanHistorySection
                }

                // How it works
                howItWorks
            }
            .padding()
        }
        .navigationTitle("\(AppConfig.appName)")
        .navigationDestination(for: UUID.self) { inventoryId in
            InventoryDetailView(inventoryId: inventoryId)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if authService.isSignedIn {
                    Button {
                        showProfile = true
                    } label: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.legoGreen)
                            .accessibilityLabel("Profile: \(authService.displayName ?? "Apple ID")")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack { UserProfileView() }
        }
        .sheet(isPresented: $showingDemoMode) {
            DemoModeView(session: cameraViewModel.scanSession)
        }
        .fullScreenCover(isPresented: $showingPhotoScan) {
            PhotoScanView()
        }
        .fullScreenCover(isPresented: $showAllScanHistory) {
            AllScanHistoryView()
        }
        .fullScreenCover(isPresented: $showAllInventories) {
            AllInventoriesView()
        }
        .navigationDestination(isPresented: $navigateToHistory) {
            if let session = selectedHistorySession {
                ScanResultsView(session: session)
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

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 16) {
            // App icon area
            ZStack {
                // Animated glow ring
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.legoRed, .legoOrange, .legoYellow, .legoGreen, .legoBlue, .legoRed],
                            center: .center
                        )
                    )
                    .frame(width: 108, height: 108)
                    .blur(radius: 6)
                    .opacity(0.6)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: themeManager.colorTheme.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "cube.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            }
            .accessibilityHidden(true)

            Text("Scan. Discover. Build.")
                .font(.title)
                .fontWeight(.bold)

            Text("Point your camera at a pile of LEGO bricks and discover amazing things you can build.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(AppConfig.appName). Scan, Discover, Build. Point your camera at LEGO bricks to discover what you can build.")
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(spacing: 12) {
            NavigationLink(destination: PreScanAnalysisView()) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 44, height: 44)
                        Image(systemName: "camera.viewfinder")
                            .font(.title2)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan Bricks")
                            .font(.headline)
                        Text("Auto-detects minifigures or brick piles")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color.legoBlue, Color.legoBlue.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.legoBlue.opacity(0.3), radius: 8, y: 4)
                )
                .foregroundStyle(.white)
            }
            .accessibilityLabel("Scan Bricks")
            .accessibilityHint("Pre-scan analysis to detect bricks or minifigures")

            Button {
                showingPhotoScan = true
            } label: {
                HStack {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 44, height: 44)
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title2)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan a Photo")
                            .font(.headline)
                        Text("Pick or take a picture and trace the area to scan")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color.legoGreen, Color.legoGreen.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.legoGreen.opacity(0.3), radius: 8, y: 4)
                )
                .foregroundStyle(.white)
            }
            .accessibilityLabel("Scan a Photo")
            .accessibilityHint("Opens the photo picker so you can scan an existing image")

            // Sprint 2 / B4 — Find a Brick hub
            NavigationLink(destination: FindABrickHubView()) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Find a Brick")
                            .font(.headline)
                        Text("Search the catalog and locate pieces in any pile")
                            .font(.caption)
                            .foregroundStyle(.black.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.black.opacity(0.6))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color.legoYellow, Color.legoYellow.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.legoYellow.opacity(0.3), radius: 8, y: 4)
                )
                .foregroundStyle(.black)
            }
            .accessibilityLabel("Find a Brick")
            .accessibilityHint("Search across the full LEGO catalog and your saved scans")

            Button {
                showingDemoMode = true
            } label: {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.legoYellow.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(Color.legoYellowLabel)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Try Demo Mode")
                            .font(.headline)
                        Text("See \(AppConfig.appName) in action with sample data")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                )
                .foregroundStyle(.primary)
            }
            .accessibilityLabel("Try Demo Mode")
            .accessibilityHint("Loads sample LEGO pieces to demonstrate the app")
            .tint(Color.primary)

            NavigationLink(destination: SetCollectionView()) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.legoGreen.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "tray.full.fill")
                            .font(.title2)
                            .foregroundStyle(Color.legoGreen)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Set Collection")
                            .font(.headline)
                        Text("Track LEGO sets and check piece completion")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                )
                .foregroundStyle(.primary)
            }
            .accessibilityLabel("Set Collection")
            .accessibilityHint("Browse LEGO sets and track which ones you own")
            .tint(Color.primary)

            NavigationLink(destination: StorageView()) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.legoOrange.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "archivebox.fill")
                            .font(.title2)
                            .foregroundStyle(Color.legoOrangeLabel)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Storage Bins")
                            .font(.headline)
                        Text("Organize pieces by physical storage location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                )
                .foregroundStyle(.primary)
            }
            .accessibilityLabel("Storage Bins")
            .accessibilityHint("Organize pieces by physical storage location")
            .tint(Color.primary)

            NavigationLink(destination: CommunityFeedView()) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.legoRed.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "person.3.fill")
                            .font(.title2)
                            .foregroundStyle(Color.legoRed)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Community")
                            .font(.headline)
                        Text("Share builds and discover creations")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                )
                .foregroundStyle(.primary)
            }
            .accessibilityLabel("Community")
            .accessibilityHint("Share builds and discover creations from other builders")
            .tint(Color.primary)

            NavigationLink(destination: PuzzleView()) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "puzzlepiece.fill")
                            .font(.title2)
                            .foregroundStyle(.purple)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Puzzles & Games")
                            .font(.headline)
                        Text("Guess builds from clues and test your knowledge")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                )
                .foregroundStyle(.primary)
            }
            .accessibilityLabel("Puzzles and Games")
            .accessibilityHint("Play build puzzles and test your LEGO knowledge")
            .tint(Color.primary)
        }
    }

    // MARK: - Recent Session

    private var recentSession: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Session")
                .font(.headline)

            HStack {
                Label("\(cameraViewModel.scanSession.totalPiecesFound) pieces", systemImage: "cube.fill")
                Spacer()
                NavigationLink("Continue") {
                    ScanResultsView(session: cameraViewModel.scanSession)
                }
                .font(.subheadline)
                .fontWeight(.semibold)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
            )
        }
    }

    // MARK: - Scan History

    /// Sprint C — geolocation. Returns either all entries or only those
    /// within `ScanSettings.locationFilterRadiusKm` of `nearMeOrigin`.
    private var visibleHistoryEntries: [ScanHistoryStore.HistoryEntry] {
        var base = scanHistory.entries
        if let tag = activeTagFilter {
            base = base.filter { entry in
                entry.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame })
            }
        }
        guard nearMeEnabled, let origin = nearMeOrigin else {
            return base
        }
        let radiusMeters = ScanSettings.shared.locationFilterRadiusKm * 1_000
        return base.filter { entry in
            guard let lat = entry.latitude, let lon = entry.longitude else { return false }
            return LocationDistance.meters(lat1: origin.lat, lon1: origin.lon,
                                           lat2: lat, lon2: lon) <= radiusMeters
        }
    }

    /// Toggle the "Near Me" filter. On enable, request a one-shot location;
    /// if it fails, leave the toggle off so the UI doesn't show an empty
    /// list with no explanation.
    private func toggleNearMe() {
        if nearMeEnabled {
            nearMeEnabled = false
            nearMeOrigin = nil
            return
        }
        Task {
            let service = ScanLocationService.shared
            if !service.authorizationAllowsCapture {
                _ = await service.requestPermission()
            }
            guard let capture = await service.requestCapture() else { return }
            await MainActor.run {
                nearMeOrigin = (capture.latitude, capture.longitude)
                nearMeEnabled = true
            }
        }
    }

    private var scanHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Scan History")
                    .font(.headline)
                Spacer()
                Button {
                    showAllScanHistory = true
                } label: {
                    Label("View All (\(scanHistory.entries.count))", systemImage: "list.bullet")
                        .font(.subheadline)
                }
            }

            // Sprint 5 / F2 — tag filter chip strip (only shown if any tags exist)
            if !scanHistory.allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        tagChip(label: "All", active: activeTagFilter == nil) {
                            activeTagFilter = nil
                        }
                        ForEach(scanHistory.allTags, id: \.self) { tag in
                            tagChip(label: tag, active: activeTagFilter == tag) {
                                activeTagFilter = (activeTagFilter == tag) ? nil : tag
                            }
                        }
                    }
                }
            }

            ForEach(visibleHistoryEntries.prefix(3)) { entry in
                Button {
                    selectedHistorySession = scanHistory.toScanSession(entry)
                    navigateToHistory = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.legoBlue.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.body)
                                .foregroundStyle(Color.legoBlue)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("\(entry.totalPiecesFound) pieces · \(entry.uniquePieceCount) unique")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                if entry.usedARMode {
                                    Text("3D")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.legoBlue))
                                }
                            }
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let place = entry.placeName, !place.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.caption2)
                                    Text(place)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(.secondary)
                            }
                            // Sprint 5 / F2 — tag pills
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

                        // Color dots preview
                        HStack(spacing: -4) {
                            ForEach(Array(Set(entry.pieces.prefix(4).map(\.color))), id: \.self) { color in
                                Circle()
                                    .fill(Color.legoColor(color))
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                            }
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.regularMaterial)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(entry.totalPiecesFound) pieces scanned on \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                .accessibilityHint("Tap to view scan results")
                .contextMenu {
                    Button {
                        taggingEntryID = entry.id
                    } label: {
                        Label(entry.tags.isEmpty ? "Add Tags" : "Edit Tags",
                              systemImage: "tag")
                    }
                }
            }
        }
        .sheet(item: Binding(
            get: { taggingEntryID.map { TaggingTarget(id: $0) } },
            set: { taggingEntryID = $0?.id }
        )) { target in
            ScanTagEditorView(sessionID: target.id)
        }
    }

    /// Tiny identifiable wrapper for sheet(item:).
    private struct TaggingTarget: Identifiable { let id: UUID }

    private func tagChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "tag").font(.caption2)
                Text(label).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(active ? Color.legoBlue.opacity(0.18) : Color.gray.opacity(0.1))
            .foregroundStyle(active ? Color.legoBlue : Color.primary)
            .clipShape(Capsule())
        }
    }

    // MARK: - Saved Inventories

    private var savedInventories: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saved Inventories")
                    .font(.headline)
                Spacer()
                Button {
                    showAllInventories = true
                } label: {
                    Label("View All (\(inventoryStore.inventories.count))", systemImage: "list.bullet")
                        .font(.subheadline)
                }
            }

            ForEach(inventoryStore.inventories.prefix(3)) { inventory in
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

                        VStack(alignment: .leading, spacing: 2) {
                            Text(inventory.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("\(inventory.totalPieces) total · \(inventory.uniquePieces) unique • \(inventory.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.regularMaterial)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Minifigures Section

    @ViewBuilder
    private var minifiguresSection: some View {
        let store = MinifigureCollectionStore.shared
        let catalog = MinifigureCatalog.shared
        let inProgress: [Minifigure] = store.collection
            .compactMap { catalog.figure(id: $0.minifigId) }
            .prefix(6)
            .map { $0 }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Minifigures")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    MinifigureCatalogView()
                } label: {
                    Text("See All →")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.colorTheme.primary)
                }
            }

            if inProgress.isEmpty {
                emptyMinifigureCard
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(inProgress) { fig in
                            NavigationLink {
                                MinifigureDetailView(figure: fig)
                            } label: {
                                miniFigCard(fig)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }

                NavigationLink {
                    MinifigureScanView()
                } label: {
                    Label("Identify by Scan", systemImage: "viewfinder.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
                }
                .buttonStyle(.plain)

                if !MinifigureScanHistoryStore.shared.entries.isEmpty {
                    NavigationLink {
                        MinifigureScanHistoryView()
                    } label: {
                        Label("Scan History", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyMinifigureCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 40))
                .foregroundStyle(themeManager.colorTheme.primary.opacity(0.5))
            Text("Start your minifigure collection")
                .font(.subheadline.weight(.semibold))
            Text("Browse 16,000+ figures or scan a torso to identify one.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                NavigationLink {
                    MinifigureCatalogView()
                } label: {
                    Text("Browse Catalog")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(themeManager.colorTheme.primary))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    MinifigureScanView()
                } label: {
                    Label("Scan", systemImage: "viewfinder")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(.regularMaterial))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
    }

    private func miniFigCard(_ fig: Minifigure) -> some View {
        let store = MinifigureCollectionStore.shared
        let pct = store.completionPercentage(for: fig, inventories: inventoryStore.inventories)
        return VStack(spacing: 6) {
            MinifigureImageView(url: fig.imageURL)
                .frame(width: 70, height: 80)

            Text(fig.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text("\(Int(pct))%")
                .font(.caption2.weight(.bold))
                .foregroundStyle(pct >= 90 ? .green : (pct >= 50 ? .orange : .red))
        }
        .frame(width: 100)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
    }

    // MARK: - Minifigure Scan History

    @ViewBuilder
    private var minifigureScanHistorySection: some View {
        let historyStore = MinifigureScanHistoryStore.shared
        let recentEntries = Array(historyStore.entries.prefix(4))

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Minifigure Scans")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    MinifigureScanHistoryView()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                        Text("View All (\(historyStore.entries.count))")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeManager.colorTheme.primary)
                }
            }

            ForEach(recentEntries) { entry in
                NavigationLink {
                    MinifigureScanHistoryView()
                } label: {
                    minifigureScanEntryRow(entry)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func minifigureScanEntryRow(_ entry: MinifigureScanHistoryStore.ScanEntry) -> some View {
        HStack(spacing: 12) {
            if let img = MinifigureScanHistoryStore.shared.capturedImage(for: entry) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 56, height: 64)
                    .overlay {
                        Image(systemName: "camera")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.minifigureName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !entry.theme.isEmpty {
                        Text(entry.theme)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !entry.reasoning.isEmpty {
                    Text(entry.reasoning)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(spacing: 2) {
                Text("\(Int(entry.confidence * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(entry.confidence >= 0.75 ? .green : entry.confidence >= 0.5 ? .orange : .red)
                Text("match")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
    }

    // MARK: - How It Works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How It Works")
                .font(.headline)

            ForEach(steps, id: \.number) { step in
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: themeManager.colorTheme.gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                        Text("\(step.number)")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .shadow(color: themeManager.colorTheme.primary.opacity(0.3), radius: 4, y: 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(step.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
    }

    private var steps: [(number: Int, title: String, description: String)] {
        [
            (1, "Scan Your Pieces", "Point your camera at your LEGO collection and tap to capture."),
            (2, "AI Identifies Them", "Our recognition engine detects brick types, sizes, and colors."),
            (3, "See Your Inventory", "Review the complete catalog of identified pieces."),
            (4, "Discover Builds", "Get personalized suggestions for amazing things to build!"),
        ]
    }
}

