import Foundation
import Combine

/// Manages iCloud synchronization for inventories and settings.
/// Uses NSUbiquitousKeyValueStore for lightweight settings and
/// iCloud Documents for inventory data files.
final class CloudSyncManager: ObservableObject {

    static let shared = CloudSyncManager()

    @Published var isSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(isSyncEnabled, forKey: "iCloudSyncEnabled") }
    }
    @Published var lastSyncDate: Date?
    @Published var syncStatus: SyncStatus = .idle
    @Published var syncError: String?

    enum SyncStatus: String {
        case idle = "Idle"
        case syncing = "Syncing…"
        case synced = "Synced"
        case error = "Error"
        case unavailable = "iCloud Unavailable"
    }

    private let kvStore = NSUbiquitousKeyValueStore.default
    private var cancellables = Set<AnyCancellable>()

    var isCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var cloudDocumentsURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
    }

    private init() {
        isSyncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        setupKVStoreObserver()
        syncSettingsFromCloud()
    }

    // MARK: - Settings Sync (NSUbiquitousKeyValueStore)

    /// Sync lightweight settings (scan preferences, theme, etc.) to iCloud KV store.
    func syncSettingsToCloud() {
        guard isSyncEnabled, isCloudAvailable else { return }

        // Sync user preferences
        if let scanMode = UserDefaults.standard.string(forKey: "scanMode") {
            kvStore.set(scanMode, forKey: "scanMode")
        }
        if let trackingMode = UserDefaults.standard.string(forKey: "trackingMode") {
            kvStore.set(trackingMode, forKey: "trackingMode")
        }
        kvStore.set(UserDefaults.standard.bool(forKey: "hapticFeedback"), forKey: "hapticFeedback")
        kvStore.set(UserDefaults.standard.bool(forKey: "soundEffects"), forKey: "soundEffects")
        kvStore.synchronize()
    }

    /// Pull settings from iCloud KV store to local.
    func syncSettingsFromCloud() {
        guard isSyncEnabled, isCloudAvailable else { return }

        if let scanMode = kvStore.string(forKey: "scanMode") {
            UserDefaults.standard.set(scanMode, forKey: "scanMode")
        }
        if let trackingMode = kvStore.string(forKey: "trackingMode") {
            UserDefaults.standard.set(trackingMode, forKey: "trackingMode")
        }
        let haptic = kvStore.bool(forKey: "hapticFeedback")
        let sound = kvStore.bool(forKey: "soundEffects")
        UserDefaults.standard.set(haptic, forKey: "hapticFeedback")
        UserDefaults.standard.set(sound, forKey: "soundEffects")
    }

    private func setupKVStoreObserver() {
        NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
            .sink { [weak self] notification in
                guard let self else { return }
                if let changeReason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int {
                    switch changeReason {
                    case NSUbiquitousKeyValueStoreServerChange,
                         NSUbiquitousKeyValueStoreInitialSyncChange:
                        Task { @MainActor in
                            self.syncSettingsFromCloud()
                        }
                    default:
                        break
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Inventory Sync (iCloud Documents)

    /// Upload the current inventory data to iCloud Documents.
    func syncInventoryToCloud() {
        guard isSyncEnabled, isCloudAvailable else {
            if !isCloudAvailable {
                syncStatus = .unavailable
            }
            return
        }

        Task { @MainActor in
            syncStatus = .syncing
            syncError = nil
        }

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                try await self.uploadInventories()
                try await self.uploadSetCollection()
                try await self.uploadStorageBins()

                await MainActor.run {
                    self.syncStatus = .synced
                    self.lastSyncDate = Date()
                    self.syncError = nil
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastCloudSync")
                }
            } catch {
                await MainActor.run {
                    self.syncStatus = .error
                    self.syncError = error.localizedDescription
                }
            }
        }
    }

    /// Download inventory data from iCloud Documents and merge.
    func syncInventoryFromCloud() {
        guard isSyncEnabled, isCloudAvailable else {
            if !isCloudAvailable {
                syncStatus = .unavailable
            }
            return
        }

        Task { @MainActor in
            syncStatus = .syncing
            syncError = nil
        }

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                try await self.downloadAndMergeInventories()
                try await self.downloadAndMergeSetCollection()
                try await self.downloadAndMergeStorageBins()

                await MainActor.run {
                    self.syncStatus = .synced
                    self.lastSyncDate = Date()
                    self.syncError = nil
                }
            } catch {
                await MainActor.run {
                    self.syncStatus = .error
                    self.syncError = error.localizedDescription
                }
            }
        }
    }

    /// Full bidirectional sync: upload local changes, download remote changes.
    func performFullSync() {
        guard isSyncEnabled, isCloudAvailable else { return }
        syncSettingsToCloud()
        syncInventoryToCloud()
    }

    // MARK: - Upload

    private func uploadInventories() async throws {
        guard let cloudURL = cloudDocumentsURL else { return }
        try FileManager.default.createDirectory(at: cloudURL, withIntermediateDirectories: true)

        let localURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("inventories.json")
        let destURL = cloudURL.appendingPathComponent("inventories.json")

        guard FileManager.default.fileExists(atPath: localURL.path) else { return }
        let data = try Data(contentsOf: localURL)
        try data.write(to: destURL, options: .atomic)
    }

    private func uploadSetCollection() async throws {
        guard let cloudURL = cloudDocumentsURL else { return }

        let localURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("setCollection.json")
        let destURL = cloudURL.appendingPathComponent("setCollection.json")

        guard FileManager.default.fileExists(atPath: localURL.path) else { return }
        let data = try Data(contentsOf: localURL)
        try data.write(to: destURL, options: .atomic)
    }

    private func uploadStorageBins() async throws {
        guard let cloudURL = cloudDocumentsURL else { return }

        let localURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("storageBins.json")
        let destURL = cloudURL.appendingPathComponent("storageBins.json")

        guard FileManager.default.fileExists(atPath: localURL.path) else { return }
        let data = try Data(contentsOf: localURL)
        try data.write(to: destURL, options: .atomic)
    }

    // MARK: - Download & Merge

    private func downloadAndMergeInventories() async throws {
        guard let cloudURL = cloudDocumentsURL else { return }
        let remoteURL = cloudURL.appendingPathComponent("inventories.json")

        guard FileManager.default.fileExists(atPath: remoteURL.path) else { return }
        let data = try Data(contentsOf: remoteURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let remoteInventories = try decoder.decode([InventoryStore.Inventory].self, from: data)

        await MainActor.run {
            mergeInventories(remote: remoteInventories)
        }
    }

    private func downloadAndMergeSetCollection() async throws {
        guard let cloudURL = cloudDocumentsURL else { return }
        let remoteURL = cloudURL.appendingPathComponent("setCollection.json")

        guard FileManager.default.fileExists(atPath: remoteURL.path) else { return }
        let data = try Data(contentsOf: remoteURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let remoteEntries = try decoder.decode([SetCollectionStore.CollectionEntry].self, from: data)

        await MainActor.run {
            mergeSetCollection(remote: remoteEntries)
        }
    }

    private func downloadAndMergeStorageBins() async throws {
        guard let cloudURL = cloudDocumentsURL else { return }
        let remoteURL = cloudURL.appendingPathComponent("storageBins.json")

        guard FileManager.default.fileExists(atPath: remoteURL.path) else { return }
        let data = try Data(contentsOf: remoteURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let remoteBins = try decoder.decode([StorageBin].self, from: data)

        await MainActor.run {
            mergeStorageBins(remote: remoteBins)
        }
    }

    // MARK: - Merge Strategies

    /// Union merge: keep all inventories, for duplicates keep the newer version.
    @MainActor private func mergeInventories(remote: [InventoryStore.Inventory]) {
        let store = InventoryStore.shared
        var merged = store.inventories

        for remoteInv in remote {
            if let localIdx = merged.firstIndex(where: { $0.id == remoteInv.id }) {
                // Keep whichever was updated more recently
                if remoteInv.updatedAt > merged[localIdx].updatedAt {
                    merged[localIdx] = remoteInv
                }
            } else {
                merged.append(remoteInv)
            }
        }

        store.inventories = merged
    }

    /// Union merge for set collection.
    @MainActor private func mergeSetCollection(remote: [SetCollectionStore.CollectionEntry]) {
        let store = SetCollectionStore.shared
        var merged = store.collection

        for remoteEntry in remote {
            if !merged.contains(where: { $0.setNumber == remoteEntry.setNumber }) {
                merged.append(remoteEntry)
            }
        }

        store.collection = merged
    }

    /// Union merge for storage bins.
    @MainActor private func mergeStorageBins(remote: [StorageBin]) {
        let store = StorageBinStore.shared
        var merged = store.bins

        for remoteBin in remote {
            if let localIdx = merged.firstIndex(where: { $0.id == remoteBin.id }) {
                // Merge piece lists (union)
                let allPieces = Set(merged[localIdx].pieceIds).union(Set(remoteBin.pieceIds))
                merged[localIdx].pieceIds = Array(allPieces)
            } else {
                merged.append(remoteBin)
            }
        }

        store.bins = merged
    }
}
