import Foundation
import StoreKit
import SwiftUI
import UIKit

private typealias StoreTransaction = StoreKit.Transaction

enum MembershipFeatureKey: String, CaseIterable {
    case textChat = "text_chat"
    case photoCaption = "photo_caption"
    case photoConversation = "photo_conversation"
    case photoStorySummary = "photo_story_summary"
    case memoryCorridorSummary = "memory_corridor_summary"
    case memoryProfileExtraction = "memory_profile_extraction"
    case memoryEmotionAnalysis = "memory_emotion_analysis"
    case memoryRetrieval = "memory_retrieval"
    case voiceConversation = "voice_conversation"
}

enum MembershipSettlementMode: String, Codable {
    case tokenActual = "token_actual"
    case durationEstimate = "duration_estimate"
}

struct MembershipPlan: Codable, Identifiable, Equatable {
    let planID: String
    let name: String
    let durationDays: Int
    let includedPoints: Int
    let appleProductID: String
    let autoRenewable: Bool
    let sortOrder: Int?

    var id: String { planID }

    enum CodingKeys: String, CodingKey {
        case planID = "plan_id"
        case name
        case durationDays = "duration_days"
        case includedPoints = "included_points"
        case appleProductID = "apple_product_id"
        case autoRenewable = "auto_renewable"
        case sortOrder = "sort_order"
    }
}

struct MembershipFeatureConfig: Codable, Identifiable {
    let featureKey: String
    let name: String
    let settlementMode: MembershipSettlementMode
    let unitSize: Int
    let pointsPerUnit: Int
    let preHoldPoints: Int
    let autoTriggerCharge: Bool
    let enabled: Bool

    var id: String { featureKey }

    enum CodingKeys: String, CodingKey {
        case featureKey = "feature_key"
        case name
        case settlementMode = "settlement_mode"
        case unitSize = "unit_size"
        case pointsPerUnit = "points_per_unit"
        case preHoldPoints = "pre_hold_points"
        case autoTriggerCharge = "auto_trigger_charge"
        case enabled
    }
}

struct MembershipCurrentSnapshot: Codable {
    let planID: String
    let planName: String
    let status: String
    let startedAt: Date?
    let expiresAt: Date?
    let autoRenewStatus: Bool
    let originalTransactionID: String
    let latestTransactionID: String

    enum CodingKeys: String, CodingKey {
        case planID = "plan_id"
        case planName = "plan_name"
        case status
        case startedAt = "started_at"
        case expiresAt = "expires_at"
        case autoRenewStatus = "auto_renew_status"
        case originalTransactionID = "original_transaction_id"
        case latestTransactionID = "latest_transaction_id"
    }
}

struct MembershipBucketSnapshot: Codable {
    let bucketID: String
    let bucketType: String
    let totalPoints: Int
    let usedPoints: Int
    let frozenPoints: Int
    let remainingPoints: Int
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case bucketID = "bucket_id"
        case bucketType = "bucket_type"
        case totalPoints = "total_points"
        case usedPoints = "used_points"
        case frozenPoints = "frozen_points"
        case remainingPoints = "remaining_points"
        case expiresAt = "expires_at"
    }
}

struct MembershipLedgerItem: Codable, Identifiable {
    let ledgerID: String
    let bucketID: String
    let featureKey: String
    let bizType: String
    let pointsDelta: Int
    let requestID: String
    let createdAt: Date?

    var id: String { ledgerID }

    enum CodingKeys: String, CodingKey {
        case ledgerID = "ledger_id"
        case bucketID = "bucket_id"
        case featureKey = "feature_key"
        case bizType = "biz_type"
        case pointsDelta = "points_delta"
        case requestID = "request_id"
        case createdAt = "created_at"
    }
}

struct MembershipProfile: Codable {
    let freeDailyPoints: Int
    let plans: [MembershipPlan]
    let featureCatalog: [MembershipFeatureConfig]
    let currentMembership: MembershipCurrentSnapshot?
    let activeBucket: MembershipBucketSnapshot?
    let currentRole: String
    let spendablePoints: Int

    enum CodingKeys: String, CodingKey {
        case freeDailyPoints = "free_daily_points"
        case plans
        case featureCatalog = "feature_catalog"
        case currentMembership = "current_membership"
        case activeBucket = "active_bucket"
        case currentRole = "current_role"
        case spendablePoints = "spendable_points"
    }

    static let empty = MembershipProfile(
        freeDailyPoints: 0,
        plans: [],
        featureCatalog: [],
        currentMembership: nil,
        activeBucket: nil,
        currentRole: "free",
        spendablePoints: 0
    )
}

struct MembershipDiagnosticEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: String
    let message: String
}

fileprivate struct MembershipEnvironmentNotice {
    let title: String
    let message: String
    let emphasized: Bool
}

private struct MembershipProductsPayload: Decodable {
    let freeDailyPoints: Int
    let plans: [MembershipPlan]
    let featureCatalog: [MembershipFeatureConfig]

    enum CodingKeys: String, CodingKey {
        case freeDailyPoints = "free_daily_points"
        case plans
        case featureCatalog = "feature_catalog"
    }
}

private struct MembershipLedgerPayload: Decodable {
    let items: [MembershipLedgerItem]
}

struct MembershipHoldReceipt {
    let holdID: String
    let requestID: String
    let holdPoints: Int
}

private struct MembershipHoldCreatePayload: Decodable {
    let holdID: String
    let requestID: String
    let holdPoints: Int
    let profile: MembershipProfile?

    enum CodingKeys: String, CodingKey {
        case holdID = "hold_id"
        case requestID = "request_id"
        case holdPoints = "hold_points"
        case profile
    }
}

private struct MembershipHoldCommitPayload: Decodable {
    let holdID: String
    let committedPoints: Int?
    let profile: MembershipProfile?

    enum CodingKeys: String, CodingKey {
        case holdID = "hold_id"
        case committedPoints = "committed_points"
        case profile
    }
}

private struct MembershipHoldProfilePayload: Decodable {
    let holdID: String
    let profile: MembershipProfile?

    enum CodingKeys: String, CodingKey {
        case holdID = "hold_id"
        case profile
    }
}

private struct MembershipEnvelope<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T?
}

enum MembershipError: LocalizedError {
    case invalidConfiguration
    case unauthorized
    case business(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "会员服务配置无效"
        case .unauthorized:
            return "请先登录"
        case .business(let message):
            return message
        case .invalidResponse:
            return "会员服务响应异常"
        }
    }
}

struct MembershipOperationUsage {
    var totalTokens: Int?
    var billableSeconds: Double?
}

struct MembershipMeteredValue<Value> {
    let value: Value
    let usage: MembershipOperationUsage
}

private struct MembershipPurchaseRecord: Codable {
    let planID: String
    let productID: String
    let originalTransactionID: String
    let latestTransactionID: String
    let purchaseDate: Date
    let expiresAt: Date
    let autoRenewStatus: Bool
}

private struct MembershipPurchaseSyncPayload {
    let planID: String
    let productID: String
    let originalTransactionID: String
    let latestTransactionID: String
    let purchaseDate: Date
    let expiresAt: Date
    let autoRenewStatus: Bool

    var requestBody: [String: Any] {
        [
            "plan_id": planID,
            "product_id": productID,
            "original_transaction_id": originalTransactionID,
            "latest_transaction_id": latestTransactionID,
            "purchase_date": ISO8601DateFormatter().string(from: purchaseDate),
            "expires_at": ISO8601DateFormatter().string(from: expiresAt),
            "auto_renew_status": autoRenewStatus
        ]
    }

    var restoreRequestBody: [String: Any] {
        [
            "original_transaction_id": originalTransactionID,
            "latest_transaction_id": latestTransactionID,
            "purchase_date": ISO8601DateFormatter().string(from: purchaseDate),
            "expires_at": ISO8601DateFormatter().string(from: expiresAt)
        ]
    }
}

private struct MembershipAPIConfig {
    let baseURL: URL
    let profilePath: String
    let productsPath: String
    let purchaseSyncPath: String
    let restoreSyncPath: String
    let holdCreatePath: String
    let holdCommitPath: String
    let holdReleasePath: String
    let ledgerPath: String

    static func current() -> MembershipAPIConfig {
        let info = Bundle.main.infoDictionary
        let rawBaseURL = (info?["AUTH_API_BASE_URL"] as? String) ?? Secrets.cloudBaseURL
        let url = URL(string: rawBaseURL) ?? URL(string: Secrets.cloudBaseURL)!
        return MembershipAPIConfig(
            baseURL: url,
            profilePath: "/membership/profile",
            productsPath: "/membership/products",
            purchaseSyncPath: "/membership/purchase/sync",
            restoreSyncPath: "/membership/restore/sync",
            holdCreatePath: "/membership/hold/create",
            holdCommitPath: "/membership/hold/commit",
            holdReleasePath: "/membership/hold/release",
            ledgerPath: "/membership/ledger/list"
        )
    }
}

private struct MembershipAPI {
    private let config = MembershipAPIConfig.current()
    private let decoder: JSONDecoder

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchProducts() async throws -> MembershipProductsPayload {
        try await post(path: config.productsPath, payload: [:], requiresAuth: false)
    }

    func fetchProfile() async throws -> MembershipProfile {
        try await post(path: config.profilePath, payload: [:], requiresAuth: true)
    }

    func fetchLedger(limit: Int = 30) async throws -> [MembershipLedgerItem] {
        let payload: MembershipLedgerPayload = try await post(
            path: config.ledgerPath,
            payload: ["limit": limit],
            requiresAuth: true
        )
        return payload.items
    }

    func syncPurchase(_ payload: MembershipPurchaseSyncPayload) async throws -> MembershipProfile {
        try await post(path: config.purchaseSyncPath, payload: payload.requestBody, requiresAuth: true)
    }

    func restorePurchase(originalTransactionID: String) async throws -> MembershipProfile {
        try await post(
            path: config.restoreSyncPath,
            payload: ["original_transaction_id": originalTransactionID],
            requiresAuth: true
        )
    }

    func restorePurchase(_ payload: MembershipPurchaseSyncPayload) async throws -> MembershipProfile {
        try await post(
            path: config.restoreSyncPath,
            payload: payload.restoreRequestBody,
            requiresAuth: true
        )
    }

    func createHold(
        featureKey: MembershipFeatureKey,
        requestID: String,
        estimatedPoints: Int? = nil,
        payload: [String: Any] = [:]
    ) async throws -> MembershipHoldCreatePayload {
        var body: [String: Any] = [
            "feature_key": featureKey.rawValue,
            "request_id": requestID,
            "payload": payload
        ]
        if let estimatedPoints {
            body["estimated_points"] = estimatedPoints
        }
        return try await post(path: config.holdCreatePath, payload: body, requiresAuth: true)
    }

    func commitHold(
        holdID: String,
        requestID: String,
        usage: MembershipOperationUsage,
        actualPoints: Int? = nil,
        payload: [String: Any] = [:]
    ) async throws -> MembershipHoldCommitPayload {
        var actualUsage: [String: Any] = [:]
        if let totalTokens = usage.totalTokens {
            actualUsage["total_tokens"] = totalTokens
        }
        if let billableSeconds = usage.billableSeconds {
            actualUsage["billable_seconds"] = billableSeconds
        }

        var body: [String: Any] = [
            "hold_id": holdID,
            "request_id": requestID,
            "actual_usage": actualUsage,
            "payload": payload
        ]
        if let actualPoints {
            body["actual_points"] = actualPoints
        }

        return try await post(path: config.holdCommitPath, payload: body, requiresAuth: true)
    }

    func releaseHold(holdID: String, requestID: String, reason: String) async throws -> MembershipHoldCommitPayload {
        let payload: MembershipHoldProfilePayload = try await post(
            path: config.holdReleasePath,
            payload: [
                "hold_id": holdID,
                "request_id": requestID,
                "reason": reason
            ],
            requiresAuth: true
        )
        return MembershipHoldCommitPayload(
            holdID: payload.holdID,
            committedPoints: nil,
            profile: payload.profile
        )
    }

    private func post<T: Decodable>(
        path: String,
        payload: [String: Any],
        requiresAuth: Bool
    ) async throws -> T {
        guard config.baseURL.absoluteString != "https://YOUR_CLOUDBASE_HTTP_DOMAIN",
              config.baseURL.absoluteString != "<YOUR_CLOUDBASE_HTTP_URL>" else {
            throw MembershipError.invalidConfiguration
        }

        guard let url = URL(string: path, relativeTo: config.baseURL) else {
            throw MembershipError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let deviceID = await MainActor.run { AuthService.shared.deviceID }
        request.setValue(deviceID, forHTTPHeaderField: "x-device-id")
        if requiresAuth {
            let authHeader = await MainActor.run { AuthService.shared.authorizationHeaderValue }
            guard let authHeader else {
                throw MembershipError.unauthorized
            }
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MembershipError.invalidResponse
        }

        let envelope = try decoder.decode(MembershipEnvelope<T>.self, from: data)
        guard (200 ... 299).contains(http.statusCode), envelope.code == 0, let payload = envelope.data else {
            let message = envelope.message.isEmpty ? "会员服务调用失败" : envelope.message
            if http.statusCode == 401 || envelope.code == 401 {
                throw MembershipError.unauthorized
            }
            throw MembershipError.business(message)
        }
        return payload
    }
}

private struct MembershipPendingPurchaseSync {
    let payload: MembershipPurchaseSyncPayload
    let transaction: StoreTransaction?
}

private struct MembershipStoreKitCatalogSnapshot {
    let availablePlanIDs: Set<String>
    let priceByPlanID: [String: String]
}

private enum MembershipStoreKitError: LocalizedError {
    case productNotConfigured(String)
    case productMappingMissing(String)
    case invalidEntitlement(String)
    case noRestorablePurchase
    case pending
    case userCancelled
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .productNotConfigured(let planName):
            return "\(planName) 暂未配置 App Store 订阅商品"
        case .productMappingMissing:
            return "当前订阅商品未在会员套餐中配置"
        case .invalidEntitlement(let planName):
            return "\(planName) 的订阅权益信息异常"
        case .noRestorablePurchase:
            return "当前 Apple ID 没有可恢复的会员订阅"
        case .pending:
            return "购买正在等待系统确认"
        case .userCancelled:
            return "你已取消购买"
        case .verificationFailed:
            return "App Store 交易校验失败"
        }
    }
}

private actor MembershipStoreKitCoordinator {
    private var productsByProductID: [String: Product] = [:]
    private var plansByProductID: [String: MembershipPlan] = [:]

    func prepareCatalog(plans: [MembershipPlan]) async throws -> MembershipStoreKitCatalogSnapshot {
        let planMap = Dictionary(uniqueKeysWithValues: plans.map { ($0.appleProductID, $0) })
        plansByProductID = planMap

        let productIDs = Array(planMap.keys)
        guard !productIDs.isEmpty else {
            productsByProductID = [:]
            return MembershipStoreKitCatalogSnapshot(availablePlanIDs: [], priceByPlanID: [:])
        }

        let products = try await Product.products(for: productIDs)
        productsByProductID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

        var availablePlanIDs: Set<String> = []
        var priceByPlanID: [String: String] = [:]
        for (productID, plan) in planMap {
            guard let product = productsByProductID[productID] else { continue }
            availablePlanIDs.insert(plan.planID)
            priceByPlanID[plan.planID] = product.displayPrice
        }

        return MembershipStoreKitCatalogSnapshot(
            availablePlanIDs: availablePlanIDs,
            priceByPlanID: priceByPlanID
        )
    }

    func purchase(plan: MembershipPlan) async throws -> MembershipPendingPurchaseSync {
        guard let product = productsByProductID[plan.appleProductID] else {
            throw MembershipStoreKitError.productNotConfigured(plan.name)
        }

        switch try await product.purchase() {
        case .success(let verification):
            guard let pending = try await pendingSync(from: verification, fallbackPlan: plan) else {
                throw MembershipStoreKitError.invalidEntitlement(plan.name)
            }
            return pending
        case .pending:
            throw MembershipStoreKitError.pending
        case .userCancelled:
            throw MembershipStoreKitError.userCancelled
        @unknown default:
            throw MembershipStoreKitError.verificationFailed
        }
    }

    func restorePurchases() async throws -> [MembershipPendingPurchaseSync] {
        try await AppStore.sync()
        return try await currentEntitlements()
    }

    func currentEntitlements() async throws -> [MembershipPendingPurchaseSync] {
        var pendings: [MembershipPendingPurchaseSync] = []
        for await verification in StoreTransaction.currentEntitlements {
            if let pending = try await pendingSync(from: verification, fallbackPlan: nil) {
                pendings.append(pending)
            }
        }
        return deduplicated(pendings)
    }

    func pendingSync(from verification: VerificationResult<StoreTransaction>) async throws -> MembershipPendingPurchaseSync? {
        try await pendingSync(from: verification, fallbackPlan: nil)
    }

    func finish(_ transaction: StoreTransaction) async {
        await transaction.finish()
    }

    private func pendingSync(
        from verification: VerificationResult<StoreTransaction>,
        fallbackPlan: MembershipPlan?
    ) async throws -> MembershipPendingPurchaseSync? {
        let transaction = try Self.verify(verification)

        if transaction.revocationDate != nil {
            await transaction.finish()
            return nil
        }

        guard let payload = try await syncPayload(for: transaction, fallbackPlan: fallbackPlan) else {
            return nil
        }

        return MembershipPendingPurchaseSync(payload: payload, transaction: transaction)
    }

    private func syncPayload(
        for transaction: StoreTransaction,
        fallbackPlan: MembershipPlan?
    ) async throws -> MembershipPurchaseSyncPayload? {
        guard let plan = plansByProductID[transaction.productID] ?? fallbackPlan else {
            return nil
        }

        let expiresAt = transaction.expirationDate
            ?? Calendar.current.date(byAdding: .day, value: plan.durationDays, to: transaction.purchaseDate)
            ?? transaction.purchaseDate
        guard expiresAt > Date() else {
            return nil
        }

        return MembershipPurchaseSyncPayload(
            planID: plan.planID,
            productID: transaction.productID,
            originalTransactionID: String(transaction.originalID),
            latestTransactionID: String(transaction.id),
            purchaseDate: transaction.purchaseDate,
            expiresAt: expiresAt,
            autoRenewStatus: await autoRenewStatus(for: transaction)
        )
    }

    private func autoRenewStatus(for transaction: StoreTransaction) async -> Bool {
        guard let subscriptionStatus = await transaction.subscriptionStatus else {
            return transaction.expirationDate != nil
        }

        switch subscriptionStatus.renewalInfo {
        case .verified(let renewalInfo):
            return renewalInfo.willAutoRenew
        case .unverified(_, _):
            return transaction.expirationDate != nil
        }
    }

    private func deduplicated(_ pendings: [MembershipPendingPurchaseSync]) -> [MembershipPendingPurchaseSync] {
        var latestByOriginalTransactionID: [String: MembershipPendingPurchaseSync] = [:]
        for pending in pendings {
            let key = pending.payload.originalTransactionID
            guard let existing = latestByOriginalTransactionID[key] else {
                latestByOriginalTransactionID[key] = pending
                continue
            }

            let shouldReplace =
                pending.payload.expiresAt > existing.payload.expiresAt ||
                pending.payload.purchaseDate > existing.payload.purchaseDate

            if shouldReplace {
                latestByOriginalTransactionID[key] = pending
            }
        }

        return Array(latestByOriginalTransactionID.values)
    }

    private static func verify<T>(_ verification: VerificationResult<T>) throws -> T {
        switch verification {
        case .verified(let value):
            return value
        case .unverified(_, _):
            throw MembershipStoreKitError.verificationFailed
        }
    }
}

private final class MembershipPurchaseSimulator {
    static let shared = MembershipPurchaseSimulator()

    private let storageKey = "gaya.membership.purchase.records"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func purchase(plan: MembershipPlan) -> MembershipPurchaseSyncPayload {
        let now = Date()
        let record = MembershipPurchaseRecord(
            planID: plan.planID,
            productID: plan.appleProductID,
            originalTransactionID: "mock.orig.\(UUID().uuidString)",
            latestTransactionID: "mock.tx.\(UUID().uuidString)",
            purchaseDate: now,
            expiresAt: Calendar.current.date(byAdding: .day, value: plan.durationDays, to: now) ?? now,
            autoRenewStatus: plan.autoRenewable
        )
        var records = loadRecords()
        records.removeAll { $0.originalTransactionID == record.originalTransactionID }
        records.append(record)
        saveRecords(records)
        return MembershipPurchaseSyncPayload(
            planID: record.planID,
            productID: record.productID,
            originalTransactionID: record.originalTransactionID,
            latestTransactionID: record.latestTransactionID,
            purchaseDate: record.purchaseDate,
            expiresAt: record.expiresAt,
            autoRenewStatus: record.autoRenewStatus
        )
    }

    func restorePayloads() -> [MembershipPurchaseSyncPayload] {
        loadRecords().map {
            MembershipPurchaseSyncPayload(
                planID: $0.planID,
                productID: $0.productID,
                originalTransactionID: $0.originalTransactionID,
                latestTransactionID: $0.latestTransactionID,
                purchaseDate: $0.purchaseDate,
                expiresAt: $0.expiresAt,
                autoRenewStatus: $0.autoRenewStatus
            )
        }
    }

    func syncAutoRenewIfNeeded(plans: [MembershipPlan]) -> [MembershipPurchaseSyncPayload] {
        var records = loadRecords()
        var renewals: [MembershipPurchaseSyncPayload] = []
        let now = Date()

        for index in records.indices {
            guard records[index].autoRenewStatus else { continue }
            guard let plan = plans.first(where: { $0.planID == records[index].planID }) else { continue }

            while records[index].expiresAt <= now {
                let newPurchaseDate = records[index].expiresAt
                let newExpiresAt = Calendar.current.date(byAdding: .day, value: plan.durationDays, to: newPurchaseDate) ?? newPurchaseDate
                records[index] = MembershipPurchaseRecord(
                    planID: records[index].planID,
                    productID: records[index].productID,
                    originalTransactionID: records[index].originalTransactionID,
                    latestTransactionID: "mock.tx.\(UUID().uuidString)",
                    purchaseDate: newPurchaseDate,
                    expiresAt: newExpiresAt,
                    autoRenewStatus: true
                )

                renewals.append(
                    MembershipPurchaseSyncPayload(
                        planID: records[index].planID,
                        productID: records[index].productID,
                        originalTransactionID: records[index].originalTransactionID,
                        latestTransactionID: records[index].latestTransactionID,
                        purchaseDate: records[index].purchaseDate,
                        expiresAt: records[index].expiresAt,
                        autoRenewStatus: true
                    )
                )
            }
        }

        saveRecords(records)
        return renewals
    }

    func debugRecords() -> [MembershipPurchaseRecord] {
        loadRecords()
    }

    func clearRecords() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func loadRecords() -> [MembershipPurchaseRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let records = try? decoder.decode([MembershipPurchaseRecord].self, from: data) else {
            return []
        }
        return records
    }

    private func saveRecords(_ records: [MembershipPurchaseRecord]) {
        guard let data = try? encoder.encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

@MainActor
final class MembershipStore: ObservableObject {
    static let shared = MembershipStore()

    @Published private(set) var profile: MembershipProfile = .empty
    @Published private(set) var plans: [MembershipPlan] = []
    @Published private(set) var featureCatalog: [MembershipFeatureConfig] = []
    @Published private(set) var ledgerItems: [MembershipLedgerItem] = []
    @Published private(set) var diagnosticEvents: [MembershipDiagnosticEvent] = []
    @Published private(set) var storeKitPriceByPlanID: [String: String] = [:]
    @Published private(set) var availableStoreKitPlanIDs: Set<String> = []
    @Published private(set) var debugSimulatorSummaryText: String = "无本地模拟订单"
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isPurchasing: Bool = false
    @Published var blockingMessage: String?

    private let api = MembershipAPI()
    private let purchaseSimulator = MembershipPurchaseSimulator.shared
    private let storeKitCoordinator = MembershipStoreKitCoordinator()
    private var transactionUpdatesTask: Task<Void, Never>?
    private var lastActivationRefreshAt: Date?
    private let activationRefreshThrottle: TimeInterval = 20

    private init() {
        refreshDebugSimulatorState()
    }

    var spendablePoints: Int { profile.spendablePoints }
    var activeBucket: MembershipBucketSnapshot? { profile.activeBucket }
    var currentMembership: MembershipCurrentSnapshot? { profile.currentMembership }
    var isMembershipActive: Bool { currentMembership?.status == "active" }
    var hasValidBackendConfiguration: Bool {
        let url = MembershipAPIConfig.current().baseURL.absoluteString
        return url != "https://YOUR_CLOUDBASE_HTTP_DOMAIN" && url != "<YOUR_CLOUDBASE_HTTP_URL>"
    }
    var debugStoreKitStatusText: String {
        if !availableStoreKitPlanIDs.isEmpty {
            return "已就绪 \(availableStoreKitPlanIDs.count) 个商品"
        }
        return allowsSimulatorFallback ? "未发现商品，当前可走调试模拟" : "未发现商品"
    }
    var debugBillingModeText: String {
        if !availableStoreKitPlanIDs.isEmpty {
            return "App Store 真实订阅"
        }
        return allowsSimulatorFallback ? "Debug 模拟购买" : "未就绪"
    }
    var debugBackendHostText: String {
        let url = MembershipAPIConfig.current().baseURL
        return url.host ?? url.absoluteString
    }
    var debugOriginalTransactionText: String {
        guard let originalID = currentMembership?.originalTransactionID, !originalID.isEmpty else {
            return "-"
        }
        if originalID.count <= 18 {
            return originalID
        }
        let prefix = originalID.prefix(8)
        let suffix = originalID.suffix(6)
        return "\(prefix)...\(suffix)"
    }
    var displayTitle: String {
        if let membership = currentMembership, membership.status == "active" {
            return membership.planName
        }
        return "免费用户"
    }
    fileprivate var summaryNotice: MembershipEnvironmentNotice? {
        guard AuthService.shared.isLoggedIn else { return nil }

        if !hasValidBackendConfiguration {
            return MembershipEnvironmentNotice(
                title: "会员后端未配置完成",
                message: "当前 AUTH_API_BASE_URL 仍是占位配置，购买、恢复购买和积分扣费都不会真正生效。",
                emphasized: true
            )
        }

        let missingPlans = plans.filter { !availableStoreKitPlanIDs.contains($0.planID) }
        guard !missingPlans.isEmpty else { return nil }

        let planNames = missingPlans.map(\.name).joined(separator: "、")
        if allowsSimulatorFallback {
            return MembershipEnvironmentNotice(
                title: "当前处于调试模拟购买",
                message: "以下套餐还没有拿到 App Store 商品：\(planNames)。现在仍可跑业务逻辑；要联调真实订阅，请在 Xcode 给 gaya scheme 挂上 .storekit 配置。",
                emphasized: false
            )
        }

        return MembershipEnvironmentNotice(
            title: "App Store 商品未就绪",
            message: "以下套餐暂不可购买：\(planNames)。请检查 App Store Connect / StoreKit 配置是否和后台商品 ID 一致。",
            emphasized: true
        )
    }
    var debugMissingStoreKitProductsText: String {
        let missing = plans
            .filter { !availableStoreKitPlanIDs.contains($0.planID) }
            .map(\.appleProductID)
        return missing.isEmpty ? "无" : missing.joined(separator: "、")
    }
    var debugRecommendedActionText: String {
        if !hasValidBackendConfiguration {
            return "先补好 AUTH_API_BASE_URL 或 Secrets.cloudBaseURL，再验证购买与积分链路。"
        }
        if plans.isEmpty {
            return "先确认会员套餐已从后端拉取成功，再检查 StoreKit 商品状态。"
        }
        if availableStoreKitPlanIDs.count == plans.count {
            return "当前可以直接验证购买、恢复购买、自动续期和积分到账。"
        }
        if allowsSimulatorFallback {
            return "当前可先用调试购买跑业务；联调真实订阅时，在 Xcode 的 gaya scheme 上挂 .storekit 文件后重启 App。"
        }
        return "检查 App Store Connect 商品、订阅组和本地 StoreKit 配置是否都已创建。"
    }

    func prepareForAppLaunch() {
        guard transactionUpdatesTask == nil else { return }

        recordDiagnostic("launch", message: "启动 StoreKit 交易监听")

        transactionUpdatesTask = Task {
            for await verification in StoreTransaction.updates {
                do {
                    guard let pending = try await storeKitCoordinator.pendingSync(from: verification) else {
                        await MainActor.run {
                            self.recordDiagnostic("autosync", message: "收到交易更新，但无有效权益可同步")
                        }
                        continue
                    }
                    guard shouldAutoSyncEntitlement(pending) else {
                        await MainActor.run {
                            self.recordDiagnostic(
                                "autosync",
                                message: "跳过非当前订阅交易 \(pending.payload.originalTransactionID)"
                            )
                        }
                        continue
                    }
                    try await applyStoreKitSync(
                        pending,
                        refreshLedger: false,
                        reason: "交易更新自动同步"
                    )
                } catch {
                    await MainActor.run {
                        self.recordDiagnostic("autosync", message: "交易更新同步失败：\(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func handleAppDidBecomeActive() async {
        guard AuthService.shared.isLoggedIn else { return }

        let now = Date()
        if let lastActivationRefreshAt, now.timeIntervalSince(lastActivationRefreshAt) < activationRefreshThrottle {
            recordDiagnostic("foreground", message: "前台刷新节流，跳过本次会员同步")
            return
        }

        lastActivationRefreshAt = now
        recordDiagnostic("foreground", message: "App 回到前台，刷新会员状态")
        await refresh(forceLedger: false)
    }

    func refresh(forceLedger: Bool = false) async {
        guard AuthService.shared.isLoggedIn else {
            reset()
            return
        }

        prepareForAppLaunch()
        isLoading = true
        defer { isLoading = false }

        do {
            if plans.isEmpty || featureCatalog.isEmpty {
                let products = try await api.fetchProducts()
                plans = products.plans.sorted {
                    ($0.sortOrder ?? .max) < ($1.sortOrder ?? .max)
                }
                featureCatalog = products.featureCatalog
                recordDiagnostic("catalog", message: "从后端拉取套餐 \(plans.count) 个，计费功能 \(featureCatalog.count) 个")
            }

            await refreshStoreKitCatalog()

            var latestProfile = try await api.fetchProfile()
            updateProfile(latestProfile)
            recordDiagnostic(
                "profile",
                message: "会员角色 \(latestProfile.currentRole)，可用积分 \(latestProfile.spendablePoints)"
            )

            latestProfile = try await syncBoundStoreKitEntitlementsIfNeeded(baseProfile: latestProfile)
            updateProfile(latestProfile)

            if shouldUseSimulatorFallback {
                recordDiagnostic("catalog", message: "未发现 App Store 商品，Debug 模式启用本地模拟订阅")
                let renewals = purchaseSimulator.syncAutoRenewIfNeeded(plans: plans)
                for renewal in renewals {
                    latestProfile = try await api.syncPurchase(renewal)
                    recordDiagnostic("renewal", message: "模拟自动续期已同步 \(renewal.planID)")
                }
                updateProfile(latestProfile)
            }

            refreshDebugSimulatorState()

            if forceLedger || ledgerItems.isEmpty {
                ledgerItems = try await api.fetchLedger()
                recordDiagnostic("ledger", message: "积分流水刷新完成，共 \(ledgerItems.count) 条")
            }
            blockingMessage = nil
        } catch {
            recordDiagnostic("error", message: "会员刷新失败：\(error.localizedDescription)")
            blockingMessage = error.localizedDescription
        }
    }

    func refreshLedger() async {
        guard AuthService.shared.isLoggedIn else {
            ledgerItems = []
            return
        }
        do {
            ledgerItems = try await api.fetchLedger()
            recordDiagnostic("ledger", message: "手动刷新积分流水，共 \(ledgerItems.count) 条")
            blockingMessage = nil
        } catch {
            recordDiagnostic("error", message: "刷新积分流水失败：\(error.localizedDescription)")
            blockingMessage = error.localizedDescription
        }
    }

    func purchase(plan: MembershipPlan) async throws {
        isPurchasing = true
        defer { isPurchasing = false }

        prepareForAppLaunch()
        if availableStoreKitPlanIDs.isEmpty {
            await refreshStoreKitCatalog()
        }

        if availableStoreKitPlanIDs.contains(plan.planID) {
            do {
                recordDiagnostic("purchase", message: "开始发起 App Store 购买 \(plan.planID)")
                let pending = try await storeKitCoordinator.purchase(plan: plan)
                try await applyStoreKitSync(
                    pending,
                    refreshLedger: true,
                    reason: "购买成功同步"
                )
                refreshDebugSimulatorState()
                blockingMessage = nil
                return
            } catch {
                recordDiagnostic("error", message: "购买 \(plan.planID) 失败：\(error.localizedDescription)")
                throw error
            }
        }

        guard allowsSimulatorFallback else {
            throw MembershipStoreKitError.productNotConfigured(plan.name)
        }

        do {
            recordDiagnostic("purchase", message: "App Store 商品缺失，改走调试购买 \(plan.planID)")
            let payload = purchaseSimulator.purchase(plan: plan)
            let syncedProfile = try await api.syncPurchase(payload)
            updateProfile(syncedProfile)
            refreshDebugSimulatorState()
            blockingMessage = nil
            await refreshLedger()
        } catch {
            recordDiagnostic("error", message: "调试购买 \(plan.planID) 失败：\(error.localizedDescription)")
            throw error
        }
    }

    func restorePurchases() async throws {
        isPurchasing = true
        defer { isPurchasing = false }

        prepareForAppLaunch()
        if availableStoreKitPlanIDs.isEmpty {
            await refreshStoreKitCatalog()
        }

        var lastProfile: MembershipProfile?

        if !availableStoreKitPlanIDs.isEmpty {
            do {
                recordDiagnostic("restore", message: "开始从 App Store 恢复订阅")
                let pendings = try await storeKitCoordinator.restorePurchases()
                guard !pendings.isEmpty else {
                    throw MembershipStoreKitError.noRestorablePurchase
                }

                for pending in pendings {
                    lastProfile = try await api.restorePurchase(pending.payload)
                    recordDiagnostic("restore", message: "已恢复订阅 \(pending.payload.planID)")
                }
            } catch {
                recordDiagnostic("error", message: "恢复购买失败：\(error.localizedDescription)")
                throw error
            }
        } else {
            guard allowsSimulatorFallback else {
                throw MembershipStoreKitError.noRestorablePurchase
            }

            do {
                recordDiagnostic("restore", message: "未发现 App Store 商品，改走调试恢复购买")
                let payloads = purchaseSimulator.restorePayloads()
                guard !payloads.isEmpty else {
                    throw MembershipStoreKitError.noRestorablePurchase
                }

                for payload in payloads {
                    lastProfile = try await api.restorePurchase(payload)
                    recordDiagnostic("restore", message: "已恢复调试订阅 \(payload.planID)")
                }
            } catch {
                recordDiagnostic("error", message: "调试恢复购买失败：\(error.localizedDescription)")
                throw error
            }
        }

        guard let lastProfile else {
            throw MembershipStoreKitError.noRestorablePurchase
        }

        updateProfile(lastProfile)
        refreshDebugSimulatorState()
        blockingMessage = nil
        await refreshLedger()
    }

    func featureConfig(for feature: MembershipFeatureKey) -> MembershipFeatureConfig? {
        featureCatalog.first(where: { $0.featureKey == feature.rawValue })
    }

    func consumeBlockingMessage() -> String? {
        defer { blockingMessage = nil }
        return blockingMessage
    }

    func updateProfile(_ profile: MembershipProfile?) {
        guard let profile else { return }
        self.profile = profile
        self.blockingMessage = nil
    }

    func planSummary(for plan: MembershipPlan) -> String {
        var segments: [String] = []
        if let price = storeKitPriceByPlanID[plan.planID] {
            segments.append(price)
        } else {
#if DEBUG
            if usesSimulatorPurchase(for: plan) {
                segments.append("调试购买")
            }
#endif
        }
        segments.append("有效期 \(plan.durationDays) 天")
        segments.append("包含 \(plan.includedPoints) 积分")
        return segments.joined(separator: " · ")
    }

    func purchaseButtonTitle(for plan: MembershipPlan) -> String {
        if isPurchasing {
            return "处理中"
        }
#if DEBUG
        if usesSimulatorPurchase(for: plan) {
            return "调试开通"
        }
#endif
        return "立即开通"
    }

    func canPurchase(plan: MembershipPlan) -> Bool {
        guard !isPurchasing else { return false }
        return availableStoreKitPlanIDs.contains(plan.planID) || usesSimulatorPurchase(for: plan)
    }

    func planDebugFootnote(for plan: MembershipPlan) -> String {
        let status: String
        if availableStoreKitPlanIDs.contains(plan.planID) {
            status = "App Store 已就绪"
        } else if allowsSimulatorFallback {
            status = "未发现商品，Debug 下走模拟购买"
        } else {
            status = "商品未就绪"
        }
        return "商品 ID: \(plan.appleProductID) · \(status)"
    }

    func openManageSubscriptions() async throws {
        guard let scene = currentWindowScene() else {
            recordDiagnostic("manage", message: "无法获取 UIWindowScene，打开订阅管理失败")
            throw MembershipError.business("无法打开订阅管理页面")
        }

        try await AppStore.showManageSubscriptions(in: scene)
        recordDiagnostic("manage", message: "已打开系统订阅管理页")
    }

    func clearDiagnosticEvents() {
        diagnosticEvents = []
    }

    func copyDiagnosticSnapshot() {
        UIPasteboard.general.string = diagnosticSnapshotText()
        recordDiagnostic("debug", message: "已复制会员诊断快照")
    }

    func reloadStoreKitCatalog() async {
        await refreshStoreKitCatalog()
        refreshDebugSimulatorState()
    }

    func clearLocalSimulatorPurchases() {
        guard allowsSimulatorFallback else { return }
        purchaseSimulator.clearRecords()
        refreshDebugSimulatorState()
        recordDiagnostic("debug", message: "已清空本机调试模拟订阅记录")
    }

    func reset() {
        profile = .empty
        ledgerItems = []
        blockingMessage = nil
        refreshDebugSimulatorState()
#if DEBUG
        diagnosticEvents = []
#endif
    }

    private func refreshStoreKitCatalog() async {
        guard !plans.isEmpty else {
            availableStoreKitPlanIDs = []
            storeKitPriceByPlanID = [:]
            return
        }

        do {
            let snapshot = try await storeKitCoordinator.prepareCatalog(plans: plans)
            availableStoreKitPlanIDs = snapshot.availablePlanIDs
            storeKitPriceByPlanID = snapshot.priceByPlanID
            let planIDs = availableStoreKitPlanIDs.sorted().joined(separator: ", ")
            recordDiagnostic("catalog", message: "StoreKit 商品可用：\(planIDs.isEmpty ? "无" : planIDs)")
        } catch {
            availableStoreKitPlanIDs = []
            storeKitPriceByPlanID = [:]
            recordDiagnostic("error", message: "StoreKit 商品加载失败：\(error.localizedDescription)")
        }
    }

    private func syncBoundStoreKitEntitlementsIfNeeded(baseProfile: MembershipProfile) async throws -> MembershipProfile {
        guard let originalTransactionID = baseProfile.currentMembership?.originalTransactionID else {
            return baseProfile
        }

        let pendings = try await storeKitCoordinator.currentEntitlements()
        guard !pendings.isEmpty else {
            return baseProfile
        }

        var latestProfile = baseProfile
        for pending in pendings where pending.payload.originalTransactionID == originalTransactionID {
            latestProfile = try await api.syncPurchase(pending.payload)
            recordDiagnostic("autosync", message: "前台校准订阅成功 \(pending.payload.planID)")
        }

        return latestProfile
    }

    private func shouldAutoSyncEntitlement(_ pending: MembershipPendingPurchaseSync) -> Bool {
        guard let originalTransactionID = currentMembership?.originalTransactionID else {
            return false
        }
        return pending.payload.originalTransactionID == originalTransactionID
    }

    private func applyStoreKitSync(
        _ pending: MembershipPendingPurchaseSync,
        refreshLedger: Bool,
        reason: String
    ) async throws {
        let syncedProfile = try await api.syncPurchase(pending.payload)
        updateProfile(syncedProfile)
        recordDiagnostic(
            "sync",
            message: "\(reason)：\(pending.payload.planID)，到期 \(formattedDiagnosticDate(pending.payload.expiresAt))"
        )

        if let transaction = pending.transaction {
            await storeKitCoordinator.finish(transaction)
            recordDiagnostic("sync", message: "交易 \(pending.payload.latestTransactionID) 已 finish")
        }

        guard refreshLedger else { return }

        do {
            ledgerItems = try await api.fetchLedger()
        } catch {
            recordDiagnostic("error", message: "同步后刷新流水失败：\(error.localizedDescription)")
            blockingMessage = error.localizedDescription
        }
    }

    private var shouldUseSimulatorFallback: Bool {
        allowsSimulatorFallback && availableStoreKitPlanIDs.isEmpty
    }

    private var allowsSimulatorFallback: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    private func usesSimulatorPurchase(for plan: MembershipPlan) -> Bool {
        !availableStoreKitPlanIDs.contains(plan.planID) && allowsSimulatorFallback
    }

    private func currentWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { lhs, rhs in
                activationPriority(lhs.activationState) > activationPriority(rhs.activationState)
            }
            .first
    }

    private func activationPriority(_ state: UIScene.ActivationState) -> Int {
        switch state {
        case .foregroundActive:
            return 3
        case .foregroundInactive:
            return 2
        case .background:
            return 1
        case .unattached:
            return 0
        @unknown default:
            return -1
        }
    }

    private func recordDiagnostic(_ category: String, message: String) {
        let event = MembershipDiagnosticEvent(
            timestamp: Date(),
            category: category,
            message: message
        )
        diagnosticEvents.insert(event, at: 0)
        if diagnosticEvents.count > 20 {
            diagnosticEvents.removeLast(diagnosticEvents.count - 20)
        }
        print("💳 [Membership][\(category)] \(message)")
    }

    private func formattedDiagnosticDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func diagnosticSnapshotText() -> String {
        var lines: [String] = []
        lines.append("role=\(profile.currentRole)")
        lines.append("spendable_points=\(profile.spendablePoints)")
        lines.append("storekit_status=\(debugStoreKitStatusText)")
        lines.append("billing_mode=\(debugBillingModeText)")
        lines.append("backend=\(debugBackendHostText)")
        lines.append("original_transaction_id=\(currentMembership?.originalTransactionID ?? "-")")
        lines.append("missing_products=\(debugMissingStoreKitProductsText)")
        lines.append("debug_simulator=\(debugSimulatorSummaryText)")
        if let activeBucket {
            lines.append("bucket=\(activeBucket.bucketType) remaining=\(activeBucket.remainingPoints)")
        }

        if !diagnosticEvents.isEmpty {
            lines.append("events:")
            for event in diagnosticEvents.prefix(10).reversed() {
                lines.append("[\(formattedDiagnosticDate(event.timestamp))][\(event.category)] \(event.message)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func refreshDebugSimulatorState() {
        guard allowsSimulatorFallback else {
            debugSimulatorSummaryText = "当前构建不支持本地模拟购买"
            return
        }

        let records = purchaseSimulator.debugRecords()
        guard !records.isEmpty else {
            debugSimulatorSummaryText = "无本地模拟订单"
            return
        }

        let activeCount = records.filter { $0.expiresAt > Date() }.count
        let latestExpiry = records.map(\.expiresAt).max() ?? Date()
        debugSimulatorSummaryText = "\(records.count) 条记录，活跃 \(activeCount) 条，最近到期 \(formattedDiagnosticDate(latestExpiry))"
    }
}

actor MembershipBillingCoordinator {
    static let shared = MembershipBillingCoordinator()

    private let api = MembershipAPI()

    func createHold(
        feature: MembershipFeatureKey,
        requestID: String = UUID().uuidString,
        estimatedPoints: Int? = nil,
        payload: [String: Any] = [:]
    ) async throws -> MembershipHoldReceipt {
        let response = try await api.createHold(
            featureKey: feature,
            requestID: requestID,
            estimatedPoints: estimatedPoints,
            payload: payload
        )

        await MainActor.run {
            MembershipStore.shared.updateProfile(response.profile)
        }

        return MembershipHoldReceipt(
            holdID: response.holdID,
            requestID: response.requestID,
            holdPoints: response.holdPoints
        )
    }

    func commitHold(
        _ hold: MembershipHoldReceipt,
        usage: MembershipOperationUsage,
        actualPoints: Int? = nil,
        payload: [String: Any] = [:]
    ) async {
        do {
            let response = try await api.commitHold(
                holdID: hold.holdID,
                requestID: hold.requestID,
                usage: usage,
                actualPoints: actualPoints,
                payload: payload
            )
            await MainActor.run {
                MembershipStore.shared.updateProfile(response.profile)
            }
        } catch {
            await MainActor.run {
                MembershipStore.shared.blockingMessage = error.localizedDescription
            }
        }
    }

    func releaseHold(_ hold: MembershipHoldReceipt, reason: String) async {
        do {
            let response = try await api.releaseHold(
                holdID: hold.holdID,
                requestID: hold.requestID,
                reason: reason
            )
            await MainActor.run {
                MembershipStore.shared.updateProfile(response.profile)
            }
        } catch {
            await MainActor.run {
                MembershipStore.shared.blockingMessage = error.localizedDescription
            }
        }
    }

    func runMeteredOperation<Value>(
        feature: MembershipFeatureKey,
        estimatedPoints: Int? = nil,
        payload: [String: Any] = [:],
        operation: @escaping () async throws -> MembershipMeteredValue<Value>
    ) async throws -> Value {
        let hold: MembershipHoldReceipt
        do {
            hold = try await createHold(feature: feature, estimatedPoints: estimatedPoints, payload: payload)
        } catch {
            await MainActor.run {
                MembershipStore.shared.blockingMessage = error.localizedDescription
            }
            throw error
        }

        do {
            let result = try await operation()
            await commitHold(hold, usage: result.usage)
            return result.value
        } catch {
            await releaseHold(hold, reason: "operation_failed")
            throw error
        }
    }

    nonisolated static func estimatedSpeechSeconds(for text: String) -> Double {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return 0 }
        return max(2, Double(compact.count) / 4.8)
    }
}

struct MembershipCenterView: View {
    @ObservedObject private var store = MembershipStore.shared
    let onClose: () -> Void

    private let topControlSize: CGFloat = 42

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    summaryCard
                    planSection
                    ledgerSection
#if DEBUG
                    diagnosticsSection
#endif
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, max(20, proxy.safeAreaInsets.bottom + 12))
            }
            .background(Color.black.ignoresSafeArea())
            .task {
                await store.refresh(forceLedger: true)
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .frame(width: topControlSize, height: topControlSize)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("会员中心")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white.opacity(0.96))

            Spacer()

            Color.clear
                .frame(width: topControlSize, height: topControlSize)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.displayTitle)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            Text("可用积分 \(store.spendablePoints)")
                .font(.system(size: 30, weight: .heavy))
                .foregroundColor(Color(red: 0.96, green: 0.86, blue: 0.52))

            if let bucket = store.activeBucket {
                Text("已用 \(bucket.usedPoints) · 冻结 \(bucket.frozenPoints) · 总额 \(bucket.totalPoints)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                Text("当前没有可用积分桶")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
            }

            if let membership = store.currentMembership, let expiresAt = membership.expiresAt {
                Text("到期时间 \(formattedDate(expiresAt)) · 自动续费 \(membership.autoRenewStatus ? "已开启" : "未开启")")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.62))
            } else {
                Text("免费用户每日赠送 \(store.profile.freeDailyPoints) 积分")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.62))
            }

            if let notice = store.summaryNotice {
                membershipNoticeCard(notice)
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        do {
                            try await store.restorePurchases()
                        } catch {
                            store.blockingMessage = error.localizedDescription
                        }
                    }
                } label: {
                    capsuleButton(title: "恢复购买", fill: Color.white.opacity(0.12), textColor: .white.opacity(0.92))
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await store.refresh(forceLedger: true)
                    }
                } label: {
                    capsuleButton(title: "刷新状态", fill: Color.white.opacity(0.08), textColor: .white.opacity(0.92))
                }
                .buttonStyle(.plain)
            }

            if store.currentMembership != nil {
                Button {
                    Task {
                        do {
                            try await store.openManageSubscriptions()
                        } catch {
                            store.blockingMessage = error.localizedDescription
                        }
                    }
                } label: {
                    capsuleButton(title: "管理订阅", fill: Color.white.opacity(0.08), textColor: .white.opacity(0.92))
                }
                .buttonStyle(.plain)
            }

            if let message = store.blockingMessage {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.red.opacity(0.9))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.09, blue: 0.13),
                            Color(red: 0.04, green: 0.05, blue: 0.09)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("套餐")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white.opacity(0.95))

            ForEach(store.plans) { plan in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(plan.name)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)

                            Text(store.planSummary(for: plan))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))

#if DEBUG
                            Text(store.planDebugFootnote(for: plan))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.46))
#endif
                        }

                        Spacer()

                        Button {
                            Task {
                                do {
                                    try await store.purchase(plan: plan)
                                } catch {
                                    store.blockingMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            capsuleButton(
                                title: store.purchaseButtonTitle(for: plan),
                                fill: Color(red: 0.95, green: 0.84, blue: 0.52),
                                textColor: Color.black.opacity(0.82)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!store.canPurchase(plan: plan))
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            }
        }
    }

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("积分流水")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white.opacity(0.95))

            if store.ledgerItems.isEmpty {
                Text("暂无记录")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            } else {
                ForEach(store.ledgerItems.prefix(12)) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Text(item.bizType)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .frame(width: 64, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.featureKey.isEmpty ? "系统" : item.featureKey)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.74))
                            if let createdAt = item.createdAt {
                                Text(formattedDate(createdAt))
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white.opacity(0.46))
                            }
                        }

                        Spacer()

                        Text("\(item.pointsDelta > 0 ? "+" : "")\(item.pointsDelta)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(item.pointsDelta >= 0 ? Color.green.opacity(0.88) : Color.orange.opacity(0.88))
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }
            }
        }
    }

#if DEBUG
    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("订阅调试")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white.opacity(0.95))

                Spacer()

                Button {
                    store.copyDiagnosticSnapshot()
                } label: {
                    Text("复制")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))
                }
                .buttonStyle(.plain)

                Button {
                    store.clearDiagnosticEvents()
                } label: {
                    Text("清空")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("商品状态：\(store.debugStoreKitStatusText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.82))

                Text("计费模式：\(store.debugBillingModeText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.82))

                Text("后端域名：\(store.debugBackendHostText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.82))

                Text("原始交易：\(store.debugOriginalTransactionText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.82))

                Text("缺失商品：\(store.debugMissingStoreKitProductsText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.82))

                Text("模拟订单：\(store.debugSimulatorSummaryText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.82))

                Text("下一步：\(store.debugRecommendedActionText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.82))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )

            HStack(spacing: 12) {
                Button {
                    Task {
                        await store.reloadStoreKitCatalog()
                    }
                } label: {
                    capsuleButton(title: "刷新商品", fill: Color.white.opacity(0.08), textColor: .white.opacity(0.92))
                }
                .buttonStyle(.plain)

                Button {
                    store.clearLocalSimulatorPurchases()
                } label: {
                    capsuleButton(title: "清空模拟订单", fill: Color.white.opacity(0.08), textColor: .white.opacity(0.92))
                }
                .buttonStyle(.plain)
            }

            Text("清空模拟订单只会移除本机 Debug 购买记录，不会回滚云端已经生效的会员权益。")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.48))

            if store.diagnosticEvents.isEmpty {
                Text("暂无诊断事件")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            } else {
                ForEach(store.diagnosticEvents.prefix(10)) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(event.category.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(red: 0.96, green: 0.86, blue: 0.52))

                            Text(formattedDate(event.timestamp))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.42))
                        }

                        Text(event.message)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.82))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }
            }
        }
    }
#endif

    private func capsuleButton(title: String, fill: Color, textColor: Color) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
            )
    }

    private func membershipNoticeCard(_ notice: MembershipEnvironmentNotice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(notice.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.95))

            Text(notice.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.74))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(notice.emphasized ? Color.orange.opacity(0.14) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            notice.emphasized ? Color.orange.opacity(0.34) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
        )
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
