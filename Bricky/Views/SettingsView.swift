import SwiftUI

/// Settings view for Azure configuration and app preferences
struct SettingsView: View {
    @ObservedObject private var config = AzureConfiguration.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var authService = AzureAuthService.shared
    @ObservedObject private var providerRegistry = AIProviderRegistry.shared
    @ObservedObject private var scanSettings = ScanSettings.shared
    @State private var aiEndpoint: String = ""
    @State private var oaiEndpoint: String = ""
    @State private var oaiDeployment: String = ""
    @State private var aiKey: String = ""
    @State private var oaiKey: String = ""
    @State private var showSaved = false
    @State private var showAddProvider = false
    @State private var editingProvider: AIProvider?
    @State private var kvTenantId: String = ""
    @State private var kvClientId: String = ""
    @State private var kvVaultName: String = ""
    @State private var kvLoading = false
    @State private var kvMessage: String?
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

    /// Number of consecutive taps on the version row. 7 reveals the hidden
    /// developer section. Resets after a brief idle window.
    @State private var versionTapCount = 0
    @State private var versionTapResetTask: Task<Void, Never>?
    @State private var showDeveloperSection = false

    // Collapsible section expansion state — persisted across launches so users
    // don't have to re-expand their preferred sections every time.
    @AppStorage("settings.expanded.appearance") private var expandedAppearance = false
    @AppStorage("settings.expanded.scanning") private var expandedScanning = false
    @AppStorage("settings.expanded.aiCloud") private var expandedAICloud = false
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
                } label: {
                    Label("Scanning", systemImage: "viewfinder")
                }
            }

            // MARK: - AI & Cloud (Analysis Mode + Azure + Providers)
            Section {
                DisclosureGroup(isExpanded: $expandedAICloud) {
                Toggle("Enable Cloud AI", isOn: $config.isOnlineModeEnabled)
                Text("When enabled, \(AppConfig.appName) uses Azure AI for enhanced piece identification. Offline Vision-based detection is always available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if config.isOnlineModeEnabled {
                    Divider()
                    Text("Azure AI Services")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Endpoint URL", text: $aiEndpoint)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    SecureField("API Key", text: $aiKey)
                        .textContentType(.password)

                    connectionStatusRow(
                        status: aiServicesStatus,
                        testAction: {
                            aiServicesStatus = .testing
                            Task {
                                let ok = await AzureAIService.shared.checkAIServicesConnectivity()
                                aiServicesStatus = ok ? .success : .failed
                            }
                        }
                    )

                    Divider()
                    Text("Azure OpenAI")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Endpoint URL", text: $oaiEndpoint)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Deployment Name", text: $oaiDeployment)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    SecureField("API Key", text: $oaiKey)
                        .textContentType(.password)

                    connectionStatusRow(
                        status: openAIStatus,
                        testAction: {
                            openAIStatus = .testing
                            Task {
                                let ok = await AzureAIService.shared.checkOpenAIConnectivity()
                                openAIStatus = ok ? .success : .failed
                            }
                        }
                    )

                    Divider()

                    Button {
                        saveConfiguration()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save Configuration")
                        }
                    }

                    if showSaved {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Configuration saved")
                                .foregroundStyle(.green)
                        }
                    }

                    Button {
                        testAllConnections()
                    } label: {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Test All Connections")
                        }
                    }
                    .disabled(aiServicesStatus == .testing || openAIStatus == .testing)

                    Divider()

                    DisclosureGroup("Additional AI Providers (Advanced)") {
                        if providerRegistry.providers.isEmpty {
                            Text("No additional providers configured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(providerRegistry.providers) { provider in
                                Button {
                                    editingProvider = provider
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: provider.providerType.iconName)
                                            .font(.title3)
                                            .foregroundStyle(provider.isEnabled ? .blue : .secondary)
                                            .frame(width: 28)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(provider.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundStyle(.primary)
                                            Text(provider.providerType.rawValue)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if provider.isEnabled && !provider.apiKey.isEmpty {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                                .font(.caption)
                                        } else {
                                            Image(systemName: "exclamationmark.circle")
                                                .foregroundStyle(.orange)
                                                .font(.caption)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                providerRegistry.removeProvider(at: offsets)
                            }
                        }

                        Button {
                            showAddProvider = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add AI Provider")
                            }
                        }
                    }
                }
                } label: {
                    Label("AI & Cloud", systemImage: "brain")
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
                    Text("Offline Engine")
                    Spacer()
                    Text("Vision Framework")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Cloud Engine")
                    Spacer()
                    Text("Azure AI + GPT-4o")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Parts Catalog")
                    Spacer()
                    Text("\(LegoPartsCatalog.shared.pieces.count) pieces")
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
            loadConfiguration()
            kvTenantId = authService.tenantId
            kvClientId = authService.clientId
            kvVaultName = authService.keyVaultName
        }
        .sheet(isPresented: $showAddProvider) {
            AIProviderEditorView(provider: nil) { newProvider in
                providerRegistry.addProvider(newProvider)
            }
        }
        .sheet(item: $editingProvider) { provider in
            AIProviderEditorView(provider: provider) { updated in
                providerRegistry.updateProvider(updated)
            }
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

    private func loadConfiguration() {
        aiEndpoint = config.aiServicesEndpoint
        oaiEndpoint = config.openAIEndpoint
        oaiDeployment = config.openAIDeployment
        aiKey = config.aiServicesKey
        oaiKey = config.openAIKey
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

    private func saveConfiguration() {
        config.aiServicesEndpoint = aiEndpoint
        config.openAIEndpoint = oaiEndpoint
        config.openAIDeployment = oaiDeployment
        config.aiServicesKey = aiKey
        config.openAIKey = oaiKey

        withAnimation {
            showSaved = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSaved = false }
        }
    }

    @State private var isTestingConnection = false
    @State private var connectionSucceeded: Bool?

    // Per-service connection status
    @State private var aiServicesStatus: ConnectionTestStatus = .idle
    @State private var openAIStatus: ConnectionTestStatus = .idle

    private enum ConnectionTestStatus {
        case idle, testing, success, failed
    }

    private func testAllConnections() {
        aiServicesStatus = .testing
        openAIStatus = .testing
        Task {
            let aiOk = await AzureAIService.shared.checkAIServicesConnectivity()
            aiServicesStatus = aiOk ? .success : .failed
            let oaiOk = await AzureAIService.shared.checkOpenAIConnectivity()
            openAIStatus = oaiOk ? .success : .failed
        }
    }

    @ViewBuilder
    private func connectionStatusRow(status: ConnectionTestStatus, testAction: @escaping () -> Void) -> some View {
        HStack {
            switch status {
            case .idle:
                Button("Test Connection") { testAction() }
                    .font(.caption)
            case .testing:
                ProgressView()
                    .scaleEffect(0.8)
                Text("Testing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.green)
                Spacer()
                Button("Retest") { testAction() }
                    .font(.caption)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Connection failed")
                    .font(.caption)
                    .foregroundStyle(.red)
                Spacer()
                Button("Retry") { testAction() }
                    .font(.caption)
            }
        }
    }
}

// MARK: - AI Provider Editor

struct AIProviderEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var providerType: AIProvider.ProviderType
    @State private var endpointURL: String
    @State private var apiKey: String
    @State private var modelName: String
    @State private var isEnabled: Bool

    private let existingId: UUID?
    private let onSave: (AIProvider) -> Void

    init(provider: AIProvider?, onSave: @escaping (AIProvider) -> Void) {
        self.existingId = provider?.id
        self.onSave = onSave
        _name = State(initialValue: provider?.name ?? "")
        _providerType = State(initialValue: provider?.providerType ?? .openAI)
        _endpointURL = State(initialValue: provider?.endpointURL ?? "")
        _apiKey = State(initialValue: provider?.apiKey ?? "")
        _modelName = State(initialValue: provider?.modelName ?? "")
        _isEnabled = State(initialValue: provider?.isEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    Picker("Type", selection: $providerType) {
                        ForEach(AIProvider.ProviderType.allCases) { type in
                            Label(type.rawValue, systemImage: type.iconName).tag(type)
                        }
                    }
                    .onChange(of: providerType) { _, newValue in
                        if name.isEmpty || AIProvider.ProviderType.allCases.map(\.rawValue).contains(name) {
                            name = newValue.rawValue
                        }
                        if endpointURL.isEmpty {
                            endpointURL = newValue.defaultEndpointPlaceholder
                        }
                        if modelName.isEmpty {
                            modelName = newValue.defaultModel
                        }
                    }

                    TextField("Display Name", text: $name)
                }

                Section("Connection") {
                    TextField("Endpoint URL", text: $endpointURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)

                    if providerType.requiresModel {
                        TextField("Model / Deployment Name", text: $modelName)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                }

                Section {
                    Toggle("Enabled", isOn: $isEnabled)
                }
            }
            .navigationTitle(existingId == nil ? "Add Provider" : "Edit Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let resultId = existingId ?? UUID()
                        let result = AIProvider(
                            existingId: resultId,
                            name: name,
                            providerType: providerType,
                            endpointURL: endpointURL,
                            apiKey: apiKey,
                            isEnabled: isEnabled,
                            modelName: modelName
                        )
                        onSave(result)
                        dismiss()
                    }
                    .disabled(name.isEmpty || endpointURL.isEmpty || apiKey.isEmpty)
                }
            }
        }
    }
}
