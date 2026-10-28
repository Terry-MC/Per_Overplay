import Foundation

public enum ProviderKind: String, Codable, CaseIterable, Identifiable {
    case deepseek
    case openrouter

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .openrouter: return "OpenRouter"
        }
    }

    public var defaultCurrency: String {
        switch self {
        case .deepseek: return "CNY"
        case .openrouter: return "USD"
        }
    }

    public var capabilities: ProviderCapabilities {
        switch self {
        case .deepseek:
            return ProviderCapabilities(
                balance: true,
                usage: false,
                cost: false,
                credits: false,
                note: "官方仅提供余额，无历史用量 / 费用接口"
            )
        case .openrouter:
            return ProviderCapabilities(
                balance: false,
                usage: true,
                cost: true,
                credits: true,
                note: "需 Management Key；用量窗口约 30 天（UTC 日桶）"
            )
        }
    }
}

public struct ProviderCapabilities: Equatable, Codable {
    public var balance: Bool
    public var usage: Bool
    public var cost: Bool
    public var credits: Bool
    public var note: String

    public var summary: String {
        var parts: [String] = []
        if credits { parts.append("credits / 额度") }
        if balance { parts.append("余额") }
        if usage { parts.append("用量") }
        if cost { parts.append("费用") }
        if parts.isEmpty { return "受限支持" }
        return parts.joined(separator: " / ") + " 可用"
    }
}

public struct Budget: Equatable {
    public var amount: Decimal
    public var currency: String
    public var period: String

    public init(amount: Decimal, currency: String, period: String = "month") {
        self.amount = amount
        self.currency = currency
        self.period = period
    }
}

public struct BalanceThreshold: Equatable {
    public var amount: Decimal
    public var currency: String

    public init(amount: Decimal, currency: String) {
        self.amount = amount
        self.currency = currency
    }
}

public struct Account: Identifiable, Equatable {
    public var id: String
    public var provider: ProviderKind
    public var name: String
    public var enabled: Bool
    public var createdAt: Date
    public var lastSuccessAt: Date?
    public var lastAttemptAt: Date?
    public var consecutiveFailures: Int
    public var credentialInvalid: Bool
    public var lastError: String?
    public var budget: Budget?
    public var balanceThreshold: BalanceThreshold?
    public var isDemo: Bool

    public init(
        id: String = UUID().uuidString,
        provider: ProviderKind,
        name: String,
        enabled: Bool = true,
        createdAt: Date = Date(),
        lastSuccessAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        consecutiveFailures: Int = 0,
        credentialInvalid: Bool = false,
        lastError: String? = nil,
        budget: Budget? = nil,
        balanceThreshold: BalanceThreshold? = nil,
        isDemo: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.name = name
        self.enabled = enabled
        self.createdAt = createdAt
        self.lastSuccessAt = lastSuccessAt
        self.lastAttemptAt = lastAttemptAt
        self.consecutiveFailures = consecutiveFailures
        self.credentialInvalid = credentialInvalid
        self.lastError = lastError
        self.budget = budget
        self.balanceThreshold = balanceThreshold
        self.isDemo = isDemo
    }

    public var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? provider.displayName
            : name
    }


    public var capabilities: ProviderCapabilities { provider.capabilities }
}

public struct UsageRecord: Identifiable, Equatable {
    public var id: String
    public var accountId: String
    public var accountName: String
    public var provider: ProviderKind
    public var day: String
    public var model: String
    public var providerName: String
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var reasoningTokens: Int?
    public var cachedTokens: Int?
    public var requests: Int?
    public var cost: Decimal?
    public var byokCost: Decimal?
    public var currency: String?
    public var source: String
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        accountId: String,
        accountName: String,
        provider: ProviderKind,
        day: String,
        model: String,
        providerName: String = "",
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        reasoningTokens: Int? = nil,
        cachedTokens: Int? = nil,
        requests: Int? = nil,
        cost: Decimal? = nil,
        byokCost: Decimal? = nil,
        currency: String? = nil,
        source: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.accountName = accountName
        self.provider = provider
        self.day = day
        self.model = model
        self.providerName = providerName
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
        self.cachedTokens = cachedTokens
        self.requests = requests
        self.cost = cost
        self.byokCost = byokCost
        self.currency = currency
        self.source = source
        self.updatedAt = updatedAt
    }

    public var totalTokens: Int? {
        if promptTokens == nil && completionTokens == nil { return nil }
        return (promptTokens ?? 0) + (completionTokens ?? 0)
    }

    public var uniqueKey: String {
        "\(accountId)|\(day)|\(model)|\(providerName)"
    }
}

public struct BalanceSnapshot: Identifiable, Equatable {
    public var id: String
    public var accountId: String
    public var currency: String
    public var total: Decimal
    public var granted: Decimal?
    public var toppedUp: Decimal?
    public var isAvailable: Bool?
    public var asOf: Date
    public var source: String

    public init(
        id: String = UUID().uuidString,
        accountId: String,
        currency: String,
        total: Decimal,
        granted: Decimal? = nil,
        toppedUp: Decimal? = nil,
        isAvailable: Bool? = nil,
        asOf: Date,
        source: String
    ) {
        self.id = id
        self.accountId = accountId
        self.currency = currency
        self.total = total
        self.granted = granted
        self.toppedUp = toppedUp
        self.isAvailable = isAvailable
        self.asOf = asOf
        self.source = source
    }
}

public struct QuotaSnapshot: Identifiable, Equatable {
    public var id: String
    public var accountId: String
    public var totalCredits: Decimal
    public var totalUsage: Decimal
    public var remaining: Decimal
    public var currency: String
    public var asOf: Date
    public var source: String

    public init(
        id: String = UUID().uuidString,
        accountId: String,
        totalCredits: Decimal,
        totalUsage: Decimal,
        remaining: Decimal,
        currency: String = "USD",
        asOf: Date,
        source: String
    ) {
        self.id = id
        self.accountId = accountId
        self.totalCredits = totalCredits
        self.totalUsage = totalUsage
        self.remaining = remaining
        self.currency = currency
        self.asOf = asOf
        self.source = source
    }

    public var usagePercent: Decimal? {
        Money.ratio(totalUsage, totalCredits)
    }
}

public enum AlertKind: String, Codable, CaseIterable {
    case budgetWarning
    case budgetExceeded
    case balanceLow
    case syncFailed
    case credentialInvalid
    case dataStale

    public var title: String {
        switch self {
        case .budgetWarning: return "预算已达 80%"
        case .budgetExceeded: return "预算已用尽"
        case .balanceLow: return "余额低于阈值"
        case .syncFailed: return "连续同步失败"
        case .credentialInvalid: return "凭据失效"
        case .dataStale: return "数据已过期"
        }
    }
}

public struct AlertEvent: Identifiable, Equatable {
    public var id: String
    public var accountId: String
    public var accountName: String
    public var kind: AlertKind
    public var firedAt: Date
    public var value: String
    public var threshold: String
    public var metric: String
    public var periodKey: String
    public var acknowledged: Bool
    public var isDemo: Bool

    public init(
        id: String = UUID().uuidString,
        accountId: String,
        accountName: String,
        kind: AlertKind,
        firedAt: Date,
        value: String,
        threshold: String,
        metric: String,
        periodKey: String,
        acknowledged: Bool = false,
        isDemo: Bool = false
    ) {
        self.id = id
        self.accountId = accountId
        self.accountName = accountName
        self.kind = kind
        self.firedAt = firedAt
        self.value = value
        self.threshold = threshold
        self.metric = metric
        self.periodKey = periodKey
        self.acknowledged = acknowledged
        self.isDemo = isDemo
    }
}

public struct AlertState: Equatable {
    public var key: String
    public var active: Bool
    public var lastFiredAt: Date?
    public var lastValue: String?

    public init(key: String, active: Bool, lastFiredAt: Date? = nil, lastValue: String? = nil) {
        self.key = key
        self.active = active
        self.lastFiredAt = lastFiredAt
        self.lastValue = lastValue
    }
}

public struct AppSettings: Equatable {
    public var refreshIntervalMinutes: Int
    public var notificationsEnabled: Bool

    public init(refreshIntervalMinutes: Int = 15, notificationsEnabled: Bool = true) {
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.notificationsEnabled = notificationsEnabled
    }

    public var refreshInterval: TimeInterval {
        TimeInterval(max(5, min(60, refreshIntervalMinutes)) * 60)
    }
}

public enum SyncStatus: String, Codable {
    case success
    case partial
    case failed
    case invalidCredential
    case rateLimited
}

public struct SyncOutcome {
    public var status: SyncStatus
    public var error: String?
    public var retryAfter: TimeInterval?
    public var capabilities: ProviderCapabilities
    public var balanceSnapshots: [BalanceSnapshot]
    public var quotaSnapshot: QuotaSnapshot?
    public var usageRecords: [UsageRecord]
    public var source: String
    public var httpStatus: Int?
    public var failureCategory: ConnectionTestResult.Category?

    public init(
        status: SyncStatus,
        error: String? = nil,
        retryAfter: TimeInterval? = nil,
        capabilities: ProviderCapabilities,
        balanceSnapshots: [BalanceSnapshot] = [],
        quotaSnapshot: QuotaSnapshot? = nil,
        usageRecords: [UsageRecord] = [],
        source: String,
        httpStatus: Int? = nil,
        failureCategory: ConnectionTestResult.Category? = nil
    ) {
        self.status = status
        self.error = error
        self.retryAfter = retryAfter
        self.capabilities = capabilities
        self.balanceSnapshots = balanceSnapshots
        self.quotaSnapshot = quotaSnapshot
        self.usageRecords = usageRecords
        self.source = source
        self.httpStatus = httpStatus
        self.failureCategory = failureCategory
    }

    public var isFailure: Bool {
        status == .failed || status == .invalidCredential || status == .rateLimited
    }
}

public struct ConnectionTestResult: Equatable {
    public enum Category: String {
        case success
        case invalidCredential
        case permission
        case address
        case network
        case timeout
        case rateLimited
        case malformed
        case unknown
    }

    public var category: Category
    public var message: String
    public var capabilities: ProviderCapabilities?
    public var retryAfter: TimeInterval?

    public init(
        category: Category,
        message: String,
        capabilities: ProviderCapabilities? = nil,
        retryAfter: TimeInterval? = nil
    ) {
        self.category = category
        self.message = message
        self.capabilities = capabilities
        self.retryAfter = retryAfter
    }
}

public struct UsageSummary {
    public var promptTokens: Int
    public var completionTokens: Int
    public var reasoningTokens: Int
    public var requests: Int
    public var costsByCurrency: [String: Decimal]
    public var records: Int
    public var tokensAvailable: Bool

    public var totalTokens: Int { promptTokens + completionTokens }
}

public enum AccountHealth: Equatable {
    case neverSynced
    case syncing
    case healthy
    case partial
    case failed
    case invalidCredential
    case disabled
    case stale

    public var label: String {
        switch self {
        case .neverSynced: return "尚未同步"
        case .syncing: return "同步中"
        case .healthy: return "正常"
        case .partial: return "部分成功"
        case .failed: return "同步失败"
        case .invalidCredential: return "凭据失效"
        case .disabled: return "已禁用"
        case .stale: return "已过期"
        }
    }
}
