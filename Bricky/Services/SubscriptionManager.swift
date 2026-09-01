import StoreKit
import Foundation

/// Manages Bricky Pro subscriptions and free tier gating via StoreKit 2.
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    // MARK: - Product IDs

    /// Bricky Pro is a single one-time (non-consumable) purchase — there is no
    /// subscription.
    static let proProductID = AppConfig.iapProProductId
    static let productIDs: Set<String> = [proProductID]

    // MARK: - Free Tier Limits

    static let freeDailyScanLimit = 5
    static let freeBuildVisibleLimit = 20

    /// Build-puzzle packs. Free players get a stable starter pack; Pro unlocks
    /// the full rotation. The pools are deterministic (ordered by name) so the
    /// "X of N unlocked" progress is consistent across launches and the free
    /// pack is always a strict subset of the Pro pack.
    static let freePuzzleLimit = 10
    static let proPuzzleLimit = 50

    // MARK: - Published State

    /// Lifecycle of the StoreKit product fetch, so the paywall can show an
    /// honest state instead of spinning forever when StoreKit returns no
    /// products (e.g. no `.storekit` config in the scheme, or the IAPs aren't
    /// configured/approved in App Store Connect).
    enum ProductsLoadState {
        case loading
        case loaded
        case unavailable
    }

    @Published private(set) var isPro: Bool = false
    @Published private(set) var isFamilyShared: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var productsLoadState: ProductsLoadState = .loading
    @Published private(set) var purchaseError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var dailyScanCount: Int = 0

    /// AI subject recognitions used in the current calendar month. Mirrors the
    /// server-side quota for a responsive UI; the proxy remains the source of
    /// truth and the only place that can actually authorize an Azure call.
    @Published private(set) var aiRecognitionCount: Int = 0

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
    private let aiCountKey = AppConfig.aiRecognitionCountKey
    private let aiMonthKey = AppConfig.aiRecognitionMonthKey
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
        loadAIRecognitionCount()
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

    /// Number of build puzzles available to the current player. Free players get
    /// the starter pack; Pro unlocks the full pack.
    var puzzlePoolLimit: Int {
        isPro ? Self.proPuzzleLimit : Self.freePuzzleLimit
    }
    func recordScan() {
        resetDailyCountIfNeeded()
        dailyScanCount += 1
        saveDailyScanCount()
    }

    // MARK: - AI Subject Recognition (developer-only, cloud)

    /// Cloud AI subject recognition is a hidden, developer-only capability. It is
    /// unlocked ONLY by the in-app developer override (the 7-tap trick) — never
    /// by a normal Pro purchase — and involves no subscription or extra charge.
    /// The monthly count is just a safety cap on the developer's own Azure spend.
    var canUseAIRecognition: Bool {
        developerProOverride && aiRecognitionsRemaining > 0
    }

    /// LEGO **set** identification (scan a built model → which set is it) is the
    /// same kind of developer-only cloud GPT-4o vision call as subject
    /// recognition, so it is gated identically (developer override + shared
    /// monthly safety cap) and is never reachable by a normal Pro purchase.
    var canIdentifySets: Bool {
        canUseAIRecognition
    }

    /// Recognitions left in the current calendar month for the developer.
    /// Always 0 for anyone without the developer override.
    var aiRecognitionsRemaining: Int {
        guard developerProOverride else { return 0 }
        resetAIRecognitionCountIfNeeded()
        return max(0, AppConfig.proMonthlyAIRecognitionLimit - aiRecognitionCount)
    }

    /// Local mirror increment, called after the proxy reports a successful
    /// recognition. The server enforces the real quota; this only keeps the UI
    /// honest between launches.
    func recordAIRecognition() {
        resetAIRecognitionCountIfNeeded()
        aiRecognitionCount += 1
        saveAIRecognitionCount()
    }

    // MARK: - Computed Product Helpers

    /// The single Bricky Pro one-time purchase product.
    var proProduct: Product? {
        products.first { $0.id == Self.proProductID }
    }

    var activeSubscriptionName: String? {
        guard isPro else { return nil }
        return "\(AppConfig.appName) Pro"
    }

    /// Token the cloud mesh/recognition proxy verifies before spending a paid
    /// call. Two valid forms, in priority order:
    ///
    /// 1. **Developer override** — the shared dev-bypass token, returned only
    ///    when the in-app developer override (7-tap trick) is on. This produces
    ///    no StoreKit receipt and is honored only where `DEV_BYPASS_TOKEN` is
    ///    configured (the developer's own deployment). It unlocks every cloud
    ///    capability, including the developer-only GPT-4o recognition/set-ID.
    /// 2. **Real Bricky Pro** — the Apple-signed StoreKit JWS for the Pro
    ///    entitlement. The proxy validates it server-side and accepts it for the
    ///    Cloud AI **mesh** endpoints (opt-in via Settings → 3D Reconstruction →
    ///    Cloud AI), behind the global monthly spend cap. GPT-4o recognition and
    ///    set-ID remain developer-only regardless of this token.
    ///
    /// Returns `nil` for free users (or when no Pro entitlement is present), so
    /// callers fall back to the on-device pipeline.
    func recognitionEntitlementToken() async -> String? {
        if developerProOverride {
            return AppConfig.aiRecognitionDevBypassToken
        }
        // Real Pro purchase: hand the proxy the Apple-signed JWS for the Pro
        // entitlement so it can verify authenticity before spending.
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result),
                  Self.productIDs.contains(transaction.productID) else { continue }
            return result.jwsRepresentation
        }
        return nil
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

    private struct ProductFetchTimeout: Error {}

    /// Public entry point for the paywall's "Try Again" button.
    func reloadProducts() async {
        await fetchProducts()
    }

    private func fetchProducts() async {
        productsLoadState = .loading
        do {
            let storeProducts = try await withProductTimeout(seconds: 15) {
                try await Product.products(for: Self.productIDs)
            }
            products = storeProducts.sorted { $0.price < $1.price }
            // An empty (non-throwing) result means StoreKit found none of the
            // requested product IDs — surface an honest "unavailable" state
            // rather than leaving the paywall on an infinite spinner.
            productsLoadState = products.isEmpty ? .unavailable : .loaded
        } catch {
            products = []
            productsLoadState = .unavailable
        }
    }

    /// Races an async operation against a timeout so a hung network request
    /// can't keep the paywall spinning indefinitely.
    private func withProductTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ProductFetchTimeout()
            }
            guard let result = try await group.next() else {
                throw ProductFetchTimeout()
            }
            group.cancelAll()
            return result
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

    // MARK: - Monthly AI Recognition Count Tracking

    /// Current month marker as `yyyy-MM` so the count resets when the calendar
    /// month rolls over, independent of time zone drift.
    private var currentMonthMarker: String {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        let year = comps.year ?? 0
        let month = comps.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }

    private func loadAIRecognitionCount() {
        resetAIRecognitionCountIfNeeded()
        aiRecognitionCount = defaults.integer(forKey: aiCountKey)
    }

    private func saveAIRecognitionCount() {
        defaults.set(aiRecognitionCount, forKey: aiCountKey)
        defaults.set(currentMonthMarker, forKey: aiMonthKey)
    }

    private func resetAIRecognitionCountIfNeeded() {
        let storedMonth = defaults.string(forKey: aiMonthKey)
        guard let storedMonth else {
            // First use: stamp the month without touching the count.
            defaults.set(currentMonthMarker, forKey: aiMonthKey)
            return
        }
        if storedMonth != currentMonthMarker {
            aiRecognitionCount = 0
            defaults.set(0, forKey: aiCountKey)
            defaults.set(currentMonthMarker, forKey: aiMonthKey)
        }
    }
}
