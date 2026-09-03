import Foundation
import UIKit

/// One anonymized brick correction/confirmation queued for upload. Carries only
/// an on-device visual fingerprint (Vision feature print) + labels — never a photo.
struct ContributionObservation: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let embeddingBase64: String
    let action: String              // "confirm" | "correct"
    let predictedPartNumber: String
    let predictedColor: String
    let predictedConfidence: Double
    let userPartNumber: String
    let userColor: String
    let userStudsWide: Int
    let userStudsLong: Int
    let correctedShape: Bool
    let correctedColor: Bool
    let appVersion: String
    let anonUserId: String
}

/// Uploads one observation. Returns true on success (safe to drop from the queue).
protocol ContributionUploader: Sendable {
    func upload(_ observation: ContributionObservation, entitlementToken: String?) async -> Bool
}

/// Persisted, offline-safe outbox for anonymized corrections. `enqueue` is cheap
/// and only records when the user has opted in; `flush` uploads pending items and
/// drops the successes. No raw photos are ever queued.
@MainActor
final class ContributionUploadQueue: ObservableObject {
    static let shared = ContributionUploadQueue()

    /// Cap so a user who never gets a successful upload (e.g. offline, or not
    /// entitled) doesn't grow the queue without bound.
    private static let maxPending = 500

    @Published private(set) var pending: [ContributionObservation] = []
    var pendingCount: Int { pending.count }

    private let fileURL: URL
    private let uploader: ContributionUploader
    private let consent: @MainActor () -> Bool
    private let tokenProvider: @MainActor () async -> String?

    init(
        directoryName: String = "contributions",
        uploader: ContributionUploader = URLSessionContributionUploader(),
        consent: @escaping @MainActor () -> Bool = { ScanSettings.shared.shareCorrectionsEnabled },
        tokenProvider: @escaping @MainActor () async -> String? = { await SubscriptionManager.shared.recognitionEntitlementToken() }
    ) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("queue.json")
        self.uploader = uploader
        self.consent = consent
        self.tokenProvider = tokenProvider
        load()
    }

    /// Whether the user has opted into sharing corrections.
    var isSharingEnabled: Bool { consent() }

    /// Anonymous, stable per-install id — not tied to any account or PII.
    static var anonUserId: String {
        let key = "Contribution.anonUserId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    /// Queue an observation for later upload. No-op when the user hasn't opted in.
    func enqueue(_ observation: ContributionObservation) {
        guard consent() else { return }
        pending.append(observation)
        if pending.count > Self.maxPending {
            pending.removeFirst(pending.count - Self.maxPending)
        }
        save()
    }

    /// Upload all pending observations; drop the ones that succeed, keep failures.
    func flush() async {
        guard consent(), !pending.isEmpty else { return }
        let token = await tokenProvider()
        var remaining: [ContributionObservation] = []
        for obs in pending {
            let ok = await uploader.upload(obs, entitlementToken: token)
            if !ok { remaining.append(obs) }
        }
        pending = remaining
        save()
    }

    /// Drop everything queued (e.g. the user turned sharing off).
    func clear() {
        pending = []
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([ContributionObservation].self, from: data) else { return }
        pending = items
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension ContributionUploadQueue {
    /// Build + enqueue an observation from a crop and labels. The embedding is a
    /// Vision feature print of the crop (no photo leaves the device). No-op when
    /// sharing is off or a fingerprint can't be computed.
    func enqueueCorrection(
        crop: UIImage,
        action: String,
        predicted: LegoPiece,
        userPartNumber: String,
        userColor: LegoColor,
        userStudsWide: Int,
        userStudsLong: Int,
        correctedShape: Bool,
        correctedColor: Bool
    ) {
        guard isSharingEnabled,
              let cg = crop.cgImage,
              let fingerprint = BrickCorrectionReranker.featurePrint(for: cg) else { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        enqueue(ContributionObservation(
            id: UUID(),
            createdAt: Date(),
            embeddingBase64: fingerprint.data.base64EncodedString(),
            action: action,
            predictedPartNumber: predicted.partNumber,
            predictedColor: predicted.color.rawValue,
            predictedConfidence: predicted.confidence,
            userPartNumber: userPartNumber,
            userColor: userColor.rawValue,
            userStudsWide: userStudsWide,
            userStudsLong: userStudsLong,
            correctedShape: correctedShape,
            correctedColor: correctedColor,
            appVersion: version,
            anonUserId: Self.anonUserId
        ))
    }
}

/// Default uploader — POSTs the observation + entitlement token to the proxy.
struct URLSessionContributionUploader: ContributionUploader {
    func upload(_ observation: ContributionObservation, entitlementToken: String?) async -> Bool {
        guard let url = AppConfig.contributeFlagEndpoint else { return false }

        struct Body: Encodable {
            let embeddingBase64: String
            let action: String
            let predictedPartNumber: String
            let predictedColor: String
            let predictedConfidence: Double
            let userPartNumber: String
            let userColor: String
            let userStudsWide: Int
            let userStudsLong: Int
            let correctedShape: Bool
            let correctedColor: Bool
            let appVersion: String
            let anonUserId: String
            let entitlementToken: String?
        }
        let body = Body(
            embeddingBase64: observation.embeddingBase64,
            action: observation.action,
            predictedPartNumber: observation.predictedPartNumber,
            predictedColor: observation.predictedColor,
            predictedConfidence: observation.predictedConfidence,
            userPartNumber: observation.userPartNumber,
            userColor: observation.userColor,
            userStudsWide: observation.userStudsWide,
            userStudsLong: observation.userStudsLong,
            correctedShape: observation.correctedShape,
            correctedColor: observation.correctedColor,
            appVersion: observation.appVersion,
            anonUserId: observation.anonUserId,
            entitlementToken: entitlementToken
        )
        guard let data = try? JSONEncoder().encode(body) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }
}
