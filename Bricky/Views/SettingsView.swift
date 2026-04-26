import SwiftUI

/// Settings view for app preferences
struct SettingsView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var scanSettings = ScanSettings.shared
    @State private var isRunningBenchmark = false
    @State private var showClearHistoryConfirmation = false
    @ObservedObject private var historyStore = ScanHistoryStore.shared
    @ObservedObject private var cloudSync = CloudSyncManager.shared
    @ObservedObject private var subscription = SubscriptionManager.shared
    @ObservedObject private var analytics = AnalyticsService.shared
    @ObservedObject private var communityAuth = AuthenticationService.shared
    @ObservedObject private var tipManager = TipManager.shared
    @State private var showPaywall = false
    @State private var showPrivacyPolicy = false
    @State private var showHelp = false

    /// Disk cache size for downloaded minifigure reference images.
    /// Refreshed when the Data & About section is opened.
    @State private var minifigCacheBytes: Int64 = 0
    @State private var showClearMinifigCacheConfirmation = false

    /// Number of consecutive taps on the version row. 7 reveals the hidden
    /// developer section. Resets after a brief idle window.
    @State private var versionTapCount = 0
    @State private var versionTapResetTask: Task<Void, Never>?
    @State private var showDeveloperSection = false

    // Collapsible section expansion state — persisted across launches so users
    // don't have to re-expand their preferred sections every time.
    @AppStorage("settings.expanded.appearance") private var expandedAppearance = false
    @AppStorage("settings.expanded.scanning") private var expandedScanning = false
    @AppStorage("settings.expanded.icloud") private var expandedICloud = false
    @AppStorage("settings.expanded.account") private var expandedAccount = false
    @AppStorage("settings.expanded.subscription") private var expandedSubscription = false
    @AppStorage("settings.expanded.privacy") private var expandedPrivacy = false
    @AppStorage("settings.expanded.help") private var expandedHelp = false
    @AppStorage("settings.expanded.data") private var expandedData = false
    @AppStorage("settings.expanded.about") private var expandedAbout = false

    var body: some View {
        Form {
            // MARK: - Appearance
            Section {
                DisclosureGroup(isExpanded: $expandedAppearance) {
                Picker("Appearance", selection: $themeManager.appearanceMode) {
                    ForEach(ThemeManager.AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Color Theme")
                        .font(.subheadline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ThemeManager.ColorTheme.allCases) { theme in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        themeManager.colorTheme = theme
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        HStack(spacing: 2) {
                                            ForEach(theme.previewColors, id: \.self) { color in
                                                RoundedRectangle(cornerRadius: 3)
                                                    .fill(color)
                                                    .frame(width: 18, height: 26)
                                            }
                                        }
                                        .padding(6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(.regularMaterial)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(
                                                    themeManager.colorTheme == theme ? theme.primary : .clear,
                                                    lineWidth: 2
                                                )
                                        )

                                        Text(theme.rawValue)
                                            .font(.caption2)
                                            .fontWeight(themeManager.colorTheme == theme ? .semibold : .regular)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(theme.rawValue) color theme")
                                .accessibilityAddTraits(themeManager.colorTheme == theme ? .isSelected : [])
                            }
                        }
                    }
                }
                } label: {
                    Label("Appearance", systemImage: "paintpalette.fill")
                }
            }

            // MARK: - Scanning (Scan Mode + Snapshots + Locations + Calibration)
            Section {
                DisclosureGroup(isExpanded: $expandedScanning) {
                // Scan Mode
                ForEach(ScanSettings.ScanMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scanSettings.scanMode = mode
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.iconName)
                                .font(.title3)
                                .foregroundStyle(scanSettings.scanMode == mode ? .blue : .secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(scanSettings.scanMode == mode ? .semibold : .regular)
                                    .foregroundStyle(.primary)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if scanSettings.scanMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                // Piece Location Snapshots
                Text("Piece Location Snapshots")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Toggle("Enable Location Snapshots", isOn: $scanSettings.locationSnapshotsEnabled)

                if scanSettings.locationSnapshotsEnabled {
                    Toggle("Composite Mode", isOn: $scanSettings.useCompositeMode)

                    if scanSettings.useCompositeMode {
                        Toggle("Pre-render on Scan Complete", isOn: $scanSettings.preRenderOnComplete)
                    }
                }

                Divider()

                // Scan Locations (geolocation)
                Text("Scan Locations")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Toggle("Tag Scans with Location", isOn: $scanSettings.locationCaptureEnabled)
                    .onChange(of: scanSettings.locationCaptureEnabled) { _, newValue in
                        if newValue {
                            Task { _ = await ScanLocationService.shared.requestPermission() }
                        }
                    }

                if scanSettings.locationCaptureEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\u{201C}Near Me\u{201D} Radius")
                            Spacer()
                            Text(String(format: "%.1f km", scanSettings.locationFilterRadiusKm))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $scanSettings.locationFilterRadiusKm, in: 0.1...10, step: 0.1)
                    }

                    Button(role: .destructive) {
                        ScanHistoryStore.shared.clearLocations()
                    } label: {
                        Label("Forget Locations on Saved Scans", systemImage: "mappin.slash")
                    }
                }

                Divider()

                // Color Calibration
                NavigationLink {
                    ColorCalibrationWizardView()
                } label: {
                    HStack {
                        Label("Color Calibration", systemImage: "paintpalette.fill")
                        Spacer()
                        if ColorCalibrationStore.shared.isCalibrated {
                            Text("\(ColorCalibrationStore.shared.calibratedColorsCount) colors")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                // Scanner Identification Mode
                Text("Scanner Identification Mode")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(ScanSettings.IdentificationMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scanSettings.identificationMode = mode
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.iconName)
                                .font(.title3)
                                .foregroundStyle(scanSettings.identificationMode == mode ? .blue : .secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(scanSettings.identificationMode == mode ? .semibold : .regular)
                                    .foregroundStyle(.primary)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if scanSettings.identificationMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Text("Strict Offline blocks all network-backed scan help. Offline First allows previously cached references but no new downloads during a scan. Assisted enables on-demand reference fetches and Brickognize verification.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } label: {
                    Label("Scanning", systemImage: "viewfinder")
                }
            }

            // MARK: - Account
            Section {
                DisclosureGroup(isExpanded: $expandedAccount) {
                if communityAuth.isSignedIn {
                    HStack {
                        Label("Signed In", systemImage: "checkmark.circle.fill")
                        Spacer()
                        Text(communityAuth.displayName ?? "Builder")
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink {
                        CommunityFeedView()
                    } label: {
                        Label("Community", systemImage: "person.3.fill")
                    }
                    Button(role: .destructive) {
                        communityAuth.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    Button {
                        communityAuth.signIn()
                    } label: {
                        HStack {
                            Label("Sign In with Apple", systemImage: "apple.logo")
                            Spacer()
                            if communityAuth.isLoading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(communityAuth.isLoading)
                }
                if let error = communityAuth.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                } label: {
                    Label("Account", systemImage: "person.crop.circle.fill")
                }
            }

            // MARK: - Subscription
            Section {
                DisclosureGroup(isExpanded: $expandedSubscription) {
                HStack {
                    Label("Plan", systemImage: "crown.fill")
                    Spacer()
                    Text(subscription.isPro ? "\(AppConfig.appName) Pro" : "Free")
                        .foregroundStyle(subscription.isPro ? Color.legoYellow : .secondary)
                }

                if subscription.isFamilyShared {
                    HStack {
                        Label("Family Sharing", systemImage: "person.3.fill")
                            .font(.subheadline)
                        Spacer()
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                if !subscription.isPro {
                    HStack {
                        Text("Daily Scans")
                            .font(.subheadline)
                        Spacer()
                        Text("\(subscription.dailyScanCount) / \(SubscriptionManager.freeDailyScanLimit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Label("Upgrade to Pro", systemImage: "star.fill")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(Color.legoBlue)
                }

                Button {
                    Task { await subscription.restorePurchases() }
                } label: {
                    HStack {
                        Label("Restore Purchases", systemImage: "arrow.counterclockwise")
                        Spacer()
                        if subscription.isLoading {
                            ProgressView()
                        }
                    }
                }
                .disabled(subscription.isLoading)

                if let error = subscription.purchaseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                } label: {
                    Label("Subscription", systemImage: "crown.fill")
                }
            }

            // MARK: - Privacy & Analytics
            Section {
                DisclosureGroup(isExpanded: $expandedPrivacy) {
                Toggle(isOn: $analytics.isEnabled) {
                    Label("Usage Analytics", systemImage: "chart.bar")
                }

                Button {
                    showPrivacyPolicy = true
                } label: {
                    HStack {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                } label: {
                    Label("Privacy", systemImage: "hand.raised.fill")
                }
            }

            // MARK: - Help & Support
            Section {
                DisclosureGroup(isExpanded: $expandedHelp) {
                Button {
                    showHelp = true
                } label: {
                    HStack {
                        Label("Help & FAQ", systemImage: "questionmark.circle")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Button {
                    tipManager.resetAll()
                } label: {
                    Label("Reset Feature Tips", systemImage: "lightbulb.fill")
                }
                } label: {
                    Label("Help & Support", systemImage: "questionmark.circle.fill")
                }
            }

            // MARK: - About (merged into Data & About below)

            // MARK: - Developer (hidden behind 7 taps on Version)
            if showDeveloperSection || subscription.developerProOverride {
                Section {
                    Toggle(isOn: $subscription.developerProOverride) {
                        Label("Pro Override", systemImage: "key.fill")
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Grants Pro access without a real purchase. Synced via iCloud to all your devices signed into the same Apple ID. Tap Version 7 times to hide this section again.")
                }
            }

            // MARK: - iCloud Sync
            Section {
                DisclosureGroup(isExpanded: $expandedICloud) {
                Toggle(isOn: $cloudSync.isSyncEnabled) {
                    Label("iCloud Sync", systemImage: "icloud")
                }
                .onChange(of: cloudSync.isSyncEnabled) { _, newValue in
                    if newValue { cloudSync.performFullSync() }
                }

                if cloudSync.isSyncEnabled {
                    HStack {
                        Text("Status")
                            .font(.subheadline)
                        Spacer()
                        Text(cloudSync.syncStatus.rawValue)
                            .font(.caption)
                            .foregroundStyle(cloudSync.syncStatus == .error ? .red : .secondary)
                    }

                    if let lastSync = cloudSync.lastSyncDate {
                        HStack {
                            Text("Last Sync")
                                .font(.subheadline)
                            Spacer()
                            Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        cloudSync.performFullSync()
                    } label: {
                        HStack {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if cloudSync.syncStatus == .syncing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(cloudSync.syncStatus == .syncing || !cloudSync.isCloudAvailable)
                }

                if let error = cloudSync.syncError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if !cloudSync.isCloudAvailable {
                    Text("Sign in to iCloud in Settings to enable sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                } label: {
                    Label("iCloud Sync", systemImage: "icloud.fill")
                }
            }

            // MARK: - Data & About
            Section {
                DisclosureGroup(isExpanded: $expandedData) {
                Button(role: .destructive) {
                    showClearHistoryConfirmation = true
                } label: {
                    HStack {
                        Label("Clear Scan History", systemImage: "trash")
                        Spacer()
                        if !historyStore.entries.isEmpty {
                            Text("\(historyStore.entries.count) scans")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
                .disabled(historyStore.entries.isEmpty)

                Divider()

                Button(role: .destructive) {
                    showClearMinifigCacheConfirmation = true
                } label: {
                    HStack {
                        Label("Clear Minifigure Image Cache", systemImage: "photo.stack")
                        Spacer()
                        Text(formatBytes(minifigCacheBytes))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .disabled(minifigCacheBytes == 0)

                Text("Catalog images you've viewed are saved on-device so the minifigure scanner can identify them offline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Text("About")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    handleVersionTap()
                }
                HStack {
                    Text("AI Engine")
                    Spacer()
                    Text("Core ML (On-Device)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Parts Catalog")
                    Spacer()
                    Text("\(LegoPartsCatalog.shared.pieces.count) pieces")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Bundled Reference Images")
                    Spacer()
                    Text("\(MinifigureReferenceImageStore.shared.bundledFigureCount) figures")
                        .foregroundStyle(.secondary)
                }
                } label: {
                    Label("Data & About", systemImage: "info.circle.fill")
                }
            }
            .confirmationDialog(
                "Clear All Scan History?",
                isPresented: $showClearHistoryConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All Scans", role: .destructive) {
                    historyStore.clearAll()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently remove \(historyStore.entries.count) saved scan sessions. This action cannot be undone.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshMinifigCacheSize()
        }
        .confirmationDialog(
            "Clear Minifigure Image Cache?",
            isPresented: $showClearMinifigCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Cache", role: .destructive) {
                MinifigureImageCache.shared.clear()
                refreshMinifigCacheSize()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This frees up \(formatBytes(minifigCacheBytes)) of storage. Catalog images will be re-downloaded the next time you view them, but offline minifigure scanning may be less accurate until then.")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
    }

    /// Reveal/hide the Developer section after 7 consecutive taps on Version.
    /// Taps must come within ~1.5s of each other; otherwise the counter resets.
    private func handleVersionTap() {
        versionTapCount += 1
        versionTapResetTask?.cancel()
        if versionTapCount >= 7 {
            versionTapCount = 0
            withAnimation { showDeveloperSection.toggle() }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        versionTapResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { versionTapCount = 0 }
        }
    }

    /// Read the current on-disk byte count for cached minifigure images.
    /// Performed off the main actor since it walks the cache directory.
    private func refreshMinifigCacheSize() {
        Task.detached(priority: .utility) {
            let bytes = MinifigureImageCache.shared.diskByteCount()
            await MainActor.run { self.minifigCacheBytes = bytes }
        }
    }

    /// Format a byte count for display (e.g. "12.4 MB", "843 KB").
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: max(0, bytes))
    }
}
