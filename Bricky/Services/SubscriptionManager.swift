import StoreKit
import Foundation

/// Manages Bricky Pro subscriptions and free tier gating via StoreKit 2.
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    // MARK: - Product IDs

    static let monthlyProductID = AppConfig.iapMonthlyProductId
    static let annualProductID = AppConfig.iapAnnualProductId
    static let productIDs: Set<String> = [monthlyProductID, annualProductID]

    // MARK: - Free Tier Limits

    static let freeDailyScanLimit = 3
    static let freeBuildVisibleLimit = 20

    // MARK: - Published State

    @Published private(set) var isPro: Bool = false
    @Published private(set) var isFamilyShared: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var dailyScanCount: Int = 0

    /// Developer override that grants Pro access without a real purchase.
    /// Stored in `NSUbiquitousKeyValueStore` so it follows the user's iCloud
    /// account across devices and survives reinstalls. Hidden behind a 7-tap
    /// gesture on the version row in Settings → About so it isn't discovered
    /// by normal users.
    @Published var developerProOverride: Bool {
        didSet {
            kvStore.set(developerProOverride, forKey: Self.kvOverrideKey)
            kvStore.synchronize()
            recomputePro()
        }
    }

    // MARK: - Private

    private var transactionListener: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private let scanCountKey = AppConfig.dailyScanCountKey
    private let scanDateKey = AppConfig.dailyScanDateKey
    private let kvStore = NSUbiquitousKeyValueStore.default
    private static let kvOverrideKey = AppConfig.developerProOverrideKey

    /// Latest result from real StoreKit entitlements (without the override).
    private var storeKitIsPro: Bool = false

    private init() {
        // Load the override from iCloud KVS first so all stored properties
        // are initialized before any method call uses `self`.
        kvStore.synchronize()
        self.developerProOverride = kvStore.bool(forKey: Self.kvOverrideKey)

        loadDailyScanCount()
        transactionListener = listenForTransactions()
        // Apply the override immediately so the user doesn't see the paywall
        // flicker before StoreKit returns.
        recomputePro()
        Task { await checkEntitlements() }
        Task { await fetchProducts() }
        // Re-check whenever iCloud KVS pushes a remote change (e.g. enabled
        // on another device).
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let remoteValue = self.kvStore.bool(forKey: Self.kvOverrideKey)
                if remoteValue != self.developerProOverride {
                    self.developerProOverride = remoteValue
                }
            }
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Free Tier Checks

    var canScan: Bool {
        isPro || dailyScanCount < Self.freeDailyScanLimit
    }

    var remainingFreeScans: Int {
        max(0, Self.freeDailyScanLimit - dailyScanCount)
    }

    func canViewBuild(at index: Int) -> Bool {
        isPro || index < Self.freeBuildVisibleLimit
    }

    func recordScan() {
        resetDailyCountIfNeeded()
        dailyScanCount += 1
        saveDailyScanCount()
    }

    // MARK: - Computed Product Helpers

    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductID }
    }

    var annualProduct: Product? {
        products.first { $0.id == Self.annualProductID }
    }

    var activeSubscriptionName: String? {
        guard isPro else { return nil }
        // Check which product is currently active
        return "\(AppConfig.appName) Pro"
    }

    // MARK: - StoreKit 2 Purchase

    func purchase(_ product: Product) async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await checkEntitlements()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await checkEntitlements()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Entitlement Check

    func checkEntitlements() async {
        var hasPro = false
        var familyShared = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if Self.productIDs.contains(transaction.productID) {
                    hasPro = true
                    if transaction.ownershipType == .familyShared {
                        familyShared = true
                    }
                }
            }
        }
        storeKitIsPro = hasPro
        isFamilyShared = familyShared
        recomputePro()
    }

    /// `isPro` = real StoreKit entitlement OR the iCloud-synced developer
    /// override. Centralized so both inputs flow through one place.
    private func recomputePro() {
        isPro = storeKitIsPro || developerProOverride
    }

    // MARK: - Product Fetching

    private func fetchProducts() async {
        do {
            let storeProducts = try await Product.products(for: Self.productIDs)
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            purchaseError = "Failed to load products."
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? await self?.checkVerified(result) {
                    await transaction.finish()
                    await self?.checkEntitlements()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    // MARK: - Daily Scan Count Tracking

    private func loadDailyScanCount() {
        resetDailyCountIfNeeded()
        dailyScanCount = defaults.integer(forKey: scanCountKey)
    }

    private func saveDailyScanCount() {
        defaults.set(dailyScanCount, forKey: scanCountKey)
        defaults.set(Date().timeIntervalSince1970, forKey: scanDateKey)
    }

    private func resetDailyCountIfNeeded() {
        let lastTimestamp = defaults.double(forKey: scanDateKey)
        guard lastTimestamp > 0 else { return }
        let lastDate = Date(timeIntervalSince1970: lastTimestamp)
        if !Calendar.current.isDateInToday(lastDate) {
            dailyScanCount = 0
            defaults.set(0, forKey: scanCountKey)
        }
    }
}
