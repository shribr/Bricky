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
            NavigationLink(destination: CameraScanView()) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 44, height: 44)
                        Image(systemName: "camera.viewfinder")
                            .font(.title2)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan Pieces")
                            .font(.headline)
                        Text("Use your camera to identify LEGO bricks")
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
            .accessibilityLabel("Scan Pieces")
            .accessibilityHint("Opens camera to identify LEGO bricks")

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

// MARK: - Demo Mode

struct DemoModeView: View {
    @ObservedObject var session: ScanSession
    @Environment(\.dismiss) private var dismiss
    @State private var demoPhase: DemoPhase = .intro
    @State private var navigateToResults = false
    @State private var animatedBoxes: [DemoBox] = []
    @State private var capturedPieceNames: [String] = []
    @State private var showCaptureFlash = false
    @State private var phaseExplanation = ""

    private enum DemoPhase {
        case intro, phase1, transition, phase2, done
    }

    private struct DemoBox: Identifiable {
        let id = UUID()
        var rect: CGRect
        var label: String
        var color: Color
        var opacity: Double = 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch demoPhase {
                case .intro:
                    introView
                case .phase1:
                    phase1View
                case .transition:
                    transitionView
                case .phase2:
                    phase2View
                case .done:
                    doneView
                }
            }
            .navigationTitle("Demo Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $navigateToResults) {
                ScanResultsView(session: session)
            }
        }
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.legoBlue)

            Text("Interactive Demo")
                .font(.title)
                .fontWeight(.bold)

            Text("Watch how \(AppConfig.appName) scans and identifies LEGO pieces in two phases.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 12) {
                demoStepRow(number: 1, title: "Live Preview", description: "Camera detects bricks in real time", icon: "video.fill", color: .blue)
                demoStepRow(number: 2, title: "Capture & Identify", description: "Tap to photograph and catalog pieces", icon: "camera.fill", color: .red)
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)

            Spacer()

            Button {
                withAnimation { demoPhase = .phase1 }
                startPhase1Animation()
            } label: {
                Text("Start Demo")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Phase 1: Live Preview

    private var phase1View: some View {
        VStack(spacing: 16) {
            // Phase badge
            phaseBadge(number: 1, title: "Live Preview", icon: "video.fill", color: .blue)

            // Simulated camera view
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.9))
                    .aspectRatio(4/3, contentMode: .fit)
                    .overlay {
                        demoBrickPile
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                // Simulated bounding boxes
                GeometryReader { geo in
                    ForEach(animatedBoxes) { box in
                        let rect = CGRect(
                            x: box.rect.origin.x * geo.size.width,
                            y: box.rect.origin.y * geo.size.height,
                            width: box.rect.width * geo.size.width,
                            height: box.rect.height * geo.size.height
                        )
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(box.color, lineWidth: 2)
                            .frame(width: rect.width, height: rect.height)
                            .overlay(alignment: .topLeading) {
                                Text(box.label)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(box.color.opacity(0.8))
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                    .offset(y: -14)
                            }
                            .position(x: rect.midX, y: rect.midY)
                            .opacity(box.opacity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // "Scanning" indicator
                VStack {
                    HStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("LIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.red)
                    }
                    .padding(8)
                    .background(.black.opacity(0.6))
                    .clipShape(Capsule())
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)

            // Explanation
            Text(phaseExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .frame(minHeight: 40)
                .animation(.easeInOut(duration: 0.3), value: phaseExplanation)

            Spacer()

            Button {
                withAnimation { demoPhase = .transition }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { demoPhase = .phase2 }
                    startPhase2Animation()
                }
            } label: {
                Text("Next: Capture Phase")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Transition

    private var transitionView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.legoYellow)
            Text("Switching to Capture Mode...")
                .font(.title3)
                .fontWeight(.semibold)
            Text("The button turns red — each tap captures and catalogs pieces")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Phase 2: Capture

    private var phase2View: some View {
        VStack(spacing: 16) {
            phaseBadge(number: 2, title: "Capture & Identify", icon: "camera.fill", color: .red)

            // Simulated camera with capture flash
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.9))
                    .aspectRatio(4/3, contentMode: .fit)
                    .overlay {
                        demoBrickPile
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                // Bounding boxes (from phase 1)
                GeometryReader { geo in
                    ForEach(animatedBoxes) { box in
                        let rect = CGRect(
                            x: box.rect.origin.x * geo.size.width,
                            y: box.rect.origin.y * geo.size.height,
                            width: box.rect.width * geo.size.width,
                            height: box.rect.height * geo.size.height
                        )
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(box.color, lineWidth: 2)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .opacity(box.opacity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Flash overlay
                if showCaptureFlash {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 24)

            // Captured pieces list
            if !capturedPieceNames.isEmpty {
                VStack(spacing: 4) {
                    ForEach(capturedPieceNames, id: \.self) { name in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text(name)
                                .font(.caption)
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 32)
            }

            Text(phaseExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .frame(minHeight: 40)

            Spacer()
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Demo Complete!")
                .font(.title2)
                .fontWeight(.bold)

            Text("\(session.totalPiecesFound) sample pieces identified across \(session.pieces.count) unique types")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                navigateToResults = true
            } label: {
                Text("View Results")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Helpers

    private func phaseBadge(number: Int, title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text("Phase \(number): \(title)")
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(color)
        .clipShape(Capsule())
    }

    private func demoStepRow(number: Int, title: String, description: String, icon: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Phase \(number): \(title)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Demo Brick Pile

    /// Simulated pile of LEGO bricks rendered with SwiftUI shapes to make the demo camera view look realistic
    private var demoBrickPile: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Surface / table
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.18), Color(white: 0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Scattered bricks — positioned to align roughly with the bounding box areas
            Group {
                // Large red 2x4 brick (top-left area)
                demoBrick(width: w * 0.22, height: w * 0.11, color: .red, studsX: 4, studsY: 2)
                    .rotationEffect(.degrees(-8))
                    .position(x: w * 0.22, y: h * 0.25)

                // Green 2x2 plate (top-right area)
                demoBrick(width: w * 0.12, height: w * 0.12, color: .green, studsX: 2, studsY: 2)
                    .rotationEffect(.degrees(5))
                    .position(x: w * 0.62, y: h * 0.20)

                // Orange slope (center area)
                demoSlope(width: w * 0.16, height: w * 0.14, color: .orange)
                    .rotationEffect(.degrees(-3))
                    .position(x: w * 0.42, y: h * 0.62)

                // Blue 1x2 brick (right-center)
                demoBrick(width: w * 0.12, height: w * 0.07, color: .blue, studsX: 2, studsY: 1)
                    .rotationEffect(.degrees(12))
                    .position(x: w * 0.72, y: h * 0.58)

                // Cyan tile (bottom-left)
                demoBrick(width: w * 0.10, height: w * 0.10, color: .cyan, studsX: 1, studsY: 1)
                    .rotationEffect(.degrees(-15))
                    .position(x: w * 0.18, y: h * 0.75)

                // Extra scattered pieces for realism
                demoBrick(width: w * 0.14, height: w * 0.07, color: .yellow, studsX: 2, studsY: 1)
                    .rotationEffect(.degrees(22))
                    .position(x: w * 0.50, y: h * 0.38)

                demoBrick(width: w * 0.10, height: w * 0.10, color: Color(white: 0.35), studsX: 2, studsY: 2)
                    .rotationEffect(.degrees(-6))
                    .position(x: w * 0.82, y: h * 0.32)

                demoBrick(width: w * 0.16, height: w * 0.08, color: .white, studsX: 3, studsY: 1)
                    .rotationEffect(.degrees(10))
                    .position(x: w * 0.30, y: h * 0.45)

                demoBrick(width: w * 0.08, height: w * 0.08, color: .purple, studsX: 1, studsY: 1)
                    .rotationEffect(.degrees(-20))
                    .position(x: w * 0.60, y: h * 0.80)

                demoSlope(width: w * 0.12, height: w * 0.10, color: .red.opacity(0.8))
                    .rotationEffect(.degrees(30))
                    .position(x: w * 0.85, y: h * 0.75)
            }
        }
    }

    /// A single LEGO brick shape with studs
    private func demoBrick(width: CGFloat, height: CGFloat, color: Color, studsX: Int, studsY: Int) -> some View {
        ZStack {
            // Brick body
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: width, height: height)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 2)

            // Darker edge for 3D effect
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width, height: height)

            // Studs grid
            let studSize = min(width / CGFloat(studsX + 1), height / CGFloat(studsY + 1)) * 0.5
            let spacingX = width / CGFloat(studsX + 1)
            let spacingY = height / CGFloat(studsY + 1)

            ForEach(0..<studsY, id: \.self) { row in
                ForEach(0..<studsX, id: \.self) { col in
                    Circle()
                        .fill(color.opacity(0.85))
                        .frame(width: studSize, height: studSize)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 0.5, x: 0, y: 1)
                        .position(
                            x: spacingX * CGFloat(col + 1) - width / 2,
                            y: spacingY * CGFloat(row + 1) - height / 2
                        )
                }
            }
            .frame(width: width, height: height)
        }
    }

    /// A slope brick shape
    private func demoSlope(width: CGFloat, height: CGFloat, color: Color) -> some View {
        ZStack {
            // Slope body — trapezoid approximation
            Path { path in
                path.move(to: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: 0, y: height * 0.3))
                path.addLine(to: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: width, y: height))
                path.closeSubpath()
            }
            .fill(color)
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 2)

            // Stud on top flat portion
            Circle()
                .fill(color.opacity(0.85))
                .frame(width: width * 0.18, height: width * 0.18)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                }
                .position(x: width * 0.2, y: height * 0.55)
        }
        .frame(width: width, height: height)
    }

    // MARK: - Demo Source Image Generation

    /// Renders the brick pile as a UIImage for use as a source image in piece location snapshots
    @MainActor
    private func generateDemoPileImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let w = size.width
            let h = size.height

            // Dark background
            let bgGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor(white: 0.18, alpha: 1).cgColor, UIColor(white: 0.10, alpha: 1).cgColor] as CFArray,
                locations: [0, 1]
            )!
            ctx.cgContext.drawLinearGradient(bgGradient, start: .zero, end: CGPoint(x: 0, y: h), options: [])

            // Draw brick shapes
            let bricks: [(CGRect, UIColor)] = [
                (CGRect(x: w * 0.11, y: h * 0.19, width: w * 0.22, height: w * 0.11), .red),
                (CGRect(x: w * 0.56, y: h * 0.14, width: w * 0.12, height: w * 0.12), .green),
                (CGRect(x: w * 0.34, y: h * 0.55, width: w * 0.16, height: w * 0.14), .orange),
                (CGRect(x: w * 0.66, y: h * 0.52, width: w * 0.12, height: w * 0.07), .blue),
                (CGRect(x: w * 0.12, y: h * 0.68, width: w * 0.10, height: w * 0.10), .cyan),
                (CGRect(x: w * 0.43, y: h * 0.32, width: w * 0.14, height: w * 0.07), .yellow),
                (CGRect(x: w * 0.76, y: h * 0.26, width: w * 0.10, height: w * 0.10), UIColor(white: 0.35, alpha: 1)),
                (CGRect(x: w * 0.22, y: h * 0.41, width: w * 0.16, height: w * 0.08), .white),
                (CGRect(x: w * 0.54, y: h * 0.74, width: w * 0.08, height: w * 0.08), .purple),
                (CGRect(x: w * 0.79, y: h * 0.69, width: w * 0.12, height: w * 0.10), UIColor.red.withAlphaComponent(0.8)),
            ]

            for (rect, color) in bricks {
                // Brick body with shadow
                ctx.cgContext.saveGState()
                ctx.cgContext.setShadow(offset: CGSize(width: 1, height: 2), blur: 3, color: UIColor.black.withAlphaComponent(0.5).cgColor)
                ctx.cgContext.setFillColor(color.cgColor)
                let brickPath = UIBezierPath(roundedRect: rect, cornerRadius: 2)
                brickPath.fill()
                ctx.cgContext.restoreGState()

                // Studs (2x2 grid per brick)
                let studSize = min(rect.width, rect.height) * 0.18
                for row in 0..<2 {
                    for col in 0..<2 {
                        let cx = rect.minX + rect.width * CGFloat(col + 1) / 3.0
                        let cy = rect.minY + rect.height * CGFloat(row + 1) / 3.0
                        let studRect = CGRect(x: cx - studSize / 2, y: cy - studSize / 2, width: studSize, height: studSize)
                        ctx.cgContext.setFillColor(color.withAlphaComponent(0.85).cgColor)
                        ctx.cgContext.fillEllipse(in: studRect)
                        ctx.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
                        ctx.cgContext.setLineWidth(0.5)
                        ctx.cgContext.strokeEllipse(in: studRect)
                    }
                }
            }
        }
    }

    // MARK: - Animation Logic

    private func startPhase1Animation() {
        let demoBoxes: [(CGRect, String, Color)] = [
            (CGRect(x: 0.1, y: 0.15, width: 0.25, height: 0.2), "Brick 2x4", .red),
            (CGRect(x: 0.55, y: 0.1, width: 0.2, height: 0.18), "Plate 2x2", .green),
            (CGRect(x: 0.3, y: 0.55, width: 0.22, height: 0.2), "Slope 45°", .orange),
            (CGRect(x: 0.65, y: 0.5, width: 0.18, height: 0.22), "Brick 1x2", .blue),
            (CGRect(x: 0.1, y: 0.65, width: 0.2, height: 0.15), "Tile 1x1", .cyan),
        ]

        phaseExplanation = "The camera scans for LEGO bricks in real time..."

        for (index, (rect, label, color)) in demoBoxes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.8) {
                let box = DemoBox(rect: rect, label: label, color: color, opacity: 0)
                animatedBoxes.append(box)
                if let lastIndex = animatedBoxes.indices.last {
                    withAnimation(.easeIn(duration: 0.4)) {
                        animatedBoxes[lastIndex].opacity = 1.0
                    }
                }

                if index == 1 {
                    phaseExplanation = "Bounding boxes appear as pieces are detected — but nothing is recorded yet."
                }
                if index == 3 {
                    phaseExplanation = "When you see the pieces highlighted, you're ready to capture!"
                }
            }
        }
    }

    private func startPhase2Animation() {
        phaseExplanation = "Tap the capture button to identify pieces..."

        // Generate a source image from the brick pile for piece location snapshots
        let sourceImage = generateDemoPileImage(size: CGSize(width: 800, height: 600))
        let captureIdx = session.recordSourceImage(sourceImage)

        // Bounding boxes for each demo piece (normalized 0-1 coordinates matching brick positions)
        let demoBoundingBoxes: [CGRect] = [
            CGRect(x: 0.11, y: 0.19, width: 0.22, height: 0.12),  // Brick 2x4 red
            CGRect(x: 0.56, y: 0.14, width: 0.12, height: 0.12),  // Brick 2x2 blue (near green plate position)
            CGRect(x: 0.43, y: 0.32, width: 0.14, height: 0.08),  // Brick 1x2 yellow
            CGRect(x: 0.22, y: 0.39, width: 0.16, height: 0.08),  // Brick 1x4 green (near white brick)
            CGRect(x: 0.76, y: 0.26, width: 0.10, height: 0.10),  // Brick 1x1 black (near gray brick)
            CGRect(x: 0.11, y: 0.19, width: 0.22, height: 0.12),  // Plate 2x4 red (same area as red brick)
            CGRect(x: 0.56, y: 0.14, width: 0.12, height: 0.12),  // Plate 2x2 green
            CGRect(x: 0.54, y: 0.74, width: 0.08, height: 0.08),  // Tile 2x2 black (near purple)
            CGRect(x: 0.34, y: 0.55, width: 0.16, height: 0.14),  // Slope 45° red (orange slope area)
            CGRect(x: 0.12, y: 0.68, width: 0.10, height: 0.10),  // Wheel black (near cyan tile)
        ]

        let demoPieces: [(String, String, PieceCategory, LegoColor, Int, Int, Int, Int)] = [
            ("3001", "Brick 2x4", .brick, .red, 2, 4, 3, 8),
            ("3003", "Brick 2x2", .brick, .blue, 2, 2, 3, 12),
            ("3004", "Brick 1x2", .brick, .yellow, 1, 2, 3, 10),
            ("3010", "Brick 1x4", .brick, .green, 1, 4, 3, 6),
            ("3005", "Brick 1x1", .brick, .black, 1, 1, 3, 8),
            ("3020", "Plate 2x4", .plate, .red, 2, 4, 1, 6),
            ("3022", "Plate 2x2", .plate, .green, 2, 2, 1, 8),
            ("3068", "Tile 2x2", .tile, .black, 2, 2, 1, 4),
            ("3039", "Slope 45° 2x2", .slope, .red, 2, 2, 3, 6),
            ("4624", "Wheel Small", .wheel, .black, 1, 1, 3, 4),
        ]

        // Simulate 3 capture taps
        let captureGroups = [
            Array(demoPieces[0..<4]),
            Array(demoPieces[4..<7]),
            Array(demoPieces[7..<10])
        ]

        for (groupIndex, group) in captureGroups.enumerated() {
            let delay = Double(groupIndex) * 2.5 + 0.5

            // Flash
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeIn(duration: 0.1)) { showCaptureFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeOut(duration: 0.2)) { showCaptureFlash = false }
                }
                phaseExplanation = "Capture \(groupIndex + 1) of 3 — analyzing pieces..."
            }

            // Add pieces
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.8) {
                for (pieceIndex, (partNum, name, cat, color, w, l, h, qty)) in group.enumerated() {
                    // Find the global index for this piece's bounding box
                    let globalIndex = captureGroups[0..<groupIndex].reduce(0) { $0 + $1.count } + pieceIndex
                    let bbox = globalIndex < demoBoundingBoxes.count ? demoBoundingBoxes[globalIndex] : nil
                    let piece = LegoPiece(
                        partNumber: partNum,
                        name: name,
                        category: cat,
                        color: color,
                        dimensions: PieceDimensions(studsWide: w, studsLong: l, heightUnits: h),
                        confidence: Double.random(in: 0.7...0.98),
                        quantity: qty,
                        boundingBox: bbox,
                        captureIndex: captureIdx
                    )
                    session.pieces.append(piece)
                    session.totalPiecesFound += qty
                    withAnimation(.easeInOut(duration: 0.3)) {
                        capturedPieceNames.append("\(name) (\(color.rawValue)) x\(qty)")
                    }
                }
                let totalAdded = group.reduce(0) { $0 + $1.7 }
                phaseExplanation = "+\(totalAdded) pieces added to inventory"
            }
        }

        // Done
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            withAnimation { demoPhase = .done }
        }
    }
}
