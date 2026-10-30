import Foundation

public struct AlertSnapshot {
    public var accountId: String
    public var accountName: String
    public var provider: ProviderKind
    public var enabled: Bool
    public var isDemo: Bool
    public var budget: Budget?
    public var monthSpend: Decimal?
    public var balanceThreshold: BalanceThreshold?
    public var latestBalance: BalanceSnapshot?
    public var balanceIsFresh: Bool
    public var consecutiveFailures: Int
    public var credentialInvalid: Bool
    public var lastSuccessAt: Date?
    public var lastAttemptAt: Date?
    public var createdAt: Date
    public var refreshInterval: TimeInterval
    public var usageIsFresh: Bool
    public var now: Date
    public var alertConfig: AccountAlertConfig?
    public var publicAlertConfig: PublicAlertConfig
    public var latestQuota: QuotaSnapshot?
    public var quotaIsFresh: Bool
    public var latestBalances: [BalanceSnapshot]
    public var monthTokens: Int?
    public var tokenUsageIsFresh: Bool

    public init(
        accountId: String,
        accountName: String,
        provider: ProviderKind,
        enabled: Bool,
        isDemo: Bool = false,
        budget: Budget?,
        monthSpend: Decimal?,
        balanceThreshold: BalanceThreshold?,
        latestBalance: BalanceSnapshot?,
        balanceIsFresh: Bool,
        consecutiveFailures: Int,
        credentialInvalid: Bool,
        lastSuccessAt: Date?,
        lastAttemptAt: Date?,
        createdAt: Date,
        refreshInterval: TimeInterval,
        usageIsFresh: Bool,
        now: Date,
        alertConfig: AccountAlertConfig? = nil,
        publicAlertConfig: PublicAlertConfig = PublicAlertConfig(),
        latestQuota: QuotaSnapshot? = nil,
        quotaIsFresh: Bool = false,
        latestBalances: [BalanceSnapshot] = [],
        monthTokens: Int? = nil,
        tokenUsageIsFresh: Bool = false
    ) {
        self.accountId = accountId
        self.accountName = accountName
        self.provider = provider
        self.enabled = enabled
        self.isDemo = isDemo
        self.budget = budget
        self.monthSpend = monthSpend
        self.balanceThreshold = balanceThreshold
        self.latestBalance = latestBalance
        self.balanceIsFresh = balanceIsFresh
        self.consecutiveFailures = consecutiveFailures
        self.credentialInvalid = credentialInvalid
        self.lastSuccessAt = lastSuccessAt
        self.lastAttemptAt = lastAttemptAt
        self.createdAt = createdAt
        self.refreshInterval = refreshInterval
        self.usageIsFresh = usageIsFresh
        self.now = now
        self.alertConfig = alertConfig
        self.publicAlertConfig = publicAlertConfig
        self.latestQuota = latestQuota
        self.quotaIsFresh = quotaIsFresh
        self.latestBalances = latestBalances
        self.monthTokens = monthTokens
        self.tokenUsageIsFresh = tokenUsageIsFresh
    }
}

public final class AlertEngine {
    public static let syncFailureCooldown: TimeInterval = 6 * 60 * 60
    public static let budgetHysteresis: Decimal = 5

    private let store: OverplayStore

    public init(store: OverplayStore) {
        self.store = store
    }

    @discardableResult
    public func evaluate(_ snapshot: AlertSnapshot) throws -> [AlertEvent] {
        guard snapshot.enabled else { return [] }
        var events: [AlertEvent] = []

        if snapshot.alertConfig != nil {
            events.append(contentsOf: try evaluateLines(snapshot))
        } else {
            events.append(contentsOf: try evaluateBudget(snapshot))
            events.append(contentsOf: try evaluateBalance(snapshot))
        }
        events.append(contentsOf: try evaluateSyncFailure(snapshot))
        events.append(contentsOf: try evaluateCredential(snapshot))
        events.append(contentsOf: try evaluateStale(snapshot))

        let unique = Dictionary(grouping: events, by: \.kind).compactMap { $0.value.first }
        if !events.isEmpty {
            try store.insertAlerts(events)
        }
        return unique
    }

    private func evaluateLines(_ snapshot: AlertSnapshot) throws -> [AlertEvent] {
        guard let config = snapshot.alertConfig else { return [] }
        let rules = config.resolved(public: snapshot.publicAlertConfig)
        let (monthKey, _) = CalendarDay.monthRange(now: snapshot.now)
        var events: [AlertEvent] = []

        for rule in rules {
            guard let value = metricValue(rule: rule, snapshot: snapshot) else { continue }
            let periodKey = rule.metric == .balanceAbsolute ? "armed" : monthKey
            let key = "line:\(snapshot.accountId):\(rule.severity.rawValue):\(rule.metric.rawValue):\(periodKey)"
            let state = try store.alertState(key: key)
            let triggered: Bool
            let recovered: Bool
            if rule.metric.isLowerBound {
                triggered = value <= rule.threshold
                recovered = value > rule.threshold
            } else {
                let hysteresis: Decimal = rule.metric.usesPercent ? Self.budgetHysteresis : 0
                triggered = value >= rule.threshold
                recovered = value < rule.threshold - hysteresis
            }

            if triggered, state?.active != true {
                let kind: AlertKind = rule.severity == .critical ? .lineCritical : .lineWarning
                let event = AlertEvent(
                    accountId: snapshot.accountId,
                    accountName: snapshot.accountName,
                    kind: kind,
                    firedAt: snapshot.now,
                    value: displayValue(value, metric: rule.metric),
                    threshold: displayValue(rule.threshold, metric: rule.metric),
                    metric: "\(rule.metric.label) · \(rule.source)",
                    periodKey: periodKey,
                    isDemo: snapshot.isDemo
                )
                events.append(event)
                try store.upsertAlertState(AlertState(
                    key: key,
                    active: true,
                    lastFiredAt: snapshot.now,
                    lastValue: displayValue(value, metric: rule.metric)
                ))
            } else if recovered, state?.active == true {
                try store.upsertAlertState(AlertState(
                    key: key,
                    active: false,
                    lastFiredAt: state?.lastFiredAt,
                    lastValue: displayValue(value, metric: rule.metric)
                ))
            }
        }
        return events
    }

    private func metricValue(rule: ResolvedAlertRule, snapshot: AlertSnapshot) -> Decimal? {
        switch rule.metric {
        case .budgetPercent:
            guard snapshot.provider.capabilities.usage,
                  let budget = snapshot.budget,
                  budget.amount > 0,
                  let spend = snapshot.monthSpend,
                  snapshot.usageIsFresh else { return nil }
            return spend / budget.amount * 100
        case .quotaPercent:
            guard snapshot.quotaIsFresh,
                  let quota = snapshot.latestQuota,
                  let percent = quota.usagePercent else { return nil }
            return percent
        case .balanceAbsolute:
            guard snapshot.balanceIsFresh else { return nil }
            let balance: BalanceSnapshot?
            if let currency = rule.currency {
                balance = snapshot.latestBalances.first { $0.currency == currency }
                    ?? (snapshot.latestBalance?.currency == currency ? snapshot.latestBalance : nil)
            } else {
                balance = snapshot.latestBalances.first ?? snapshot.latestBalance
            }
            return balance?.total
        case .tokenAbsolute:
            guard snapshot.tokenUsageIsFresh, let tokens = snapshot.monthTokens else { return nil }
            return Decimal(tokens)
        }
    }

    private func displayValue(_ value: Decimal, metric: AlertMetricKind) -> String {
        switch metric {
        case .budgetPercent, .quotaPercent:
            return Money.percent(value)
        case .balanceAbsolute:
            return NSDecimalNumber(decimal: value).stringValue
        case .tokenAbsolute:
            return Money.formatInteger(NSDecimalNumber(decimal: value).intValue)
        }
    }

    private func evaluateBudget(_ snapshot: AlertSnapshot) throws -> [AlertEvent] {
        guard snapshot.provider.capabilities.usage,
              let budget = snapshot.budget,
              budget.amount > 0,
              let spend = snapshot.monthSpend,
              snapshot.usageIsFresh else { return [] }
        let ratio = spend / budget.amount * 100
        let (monthKey, _) = CalendarDay.monthRange(now: snapshot.now)
        var events: [AlertEvent] = []

        for (threshold, kind) in [(Decimal(80), AlertKind.budgetWarning), (Decimal(100), AlertKind.budgetExceeded)] {
            let key = "budget:\(snapshot.accountId):\(kind.rawValue):\(monthKey)"
            let state = try store.alertState(key: key)
            if ratio >= threshold {
                if state?.lastFiredAt == nil {
                    let event = AlertEvent(
                        accountId: snapshot.accountId,
                        accountName: snapshot.accountName,
                        kind: kind,
                        firedAt: snapshot.now,
                        value: Money.percent(ratio),
                        threshold: Money.percent(threshold, fractionDigits: 0),
                        metric: "本地预算月度使用率（\(Money.formatBalance(budget.amount, currency: budget.currency)) / 月）",
                        periodKey: monthKey,
                        isDemo: snapshot.isDemo
                    )
                    events.append(event)
                    try store.upsertAlertState(AlertState(
                        key: key,
                        active: true,
                        lastFiredAt: snapshot.now,
                        lastValue: Money.percent(ratio)
                    ))
                } else if state?.active == false {
                    try store.upsertAlertState(AlertState(
                        key: key,
                        active: true,
                        lastFiredAt: state?.lastFiredAt,
                        lastValue: Money.percent(ratio)
                    ))
                }
            } else if ratio < threshold - Self.budgetHysteresis, state?.active == true {
                try store.upsertAlertState(AlertState(
                    key: key,
                    active: false,
                    lastFiredAt: state?.lastFiredAt,
                    lastValue: Money.percent(ratio)
                ))
            }
        }
        return events
    }

    private func evaluateBalance(_ snapshot: AlertSnapshot) throws -> [AlertEvent] {
        guard snapshot.balanceIsFresh,
              let threshold = snapshot.balanceThreshold,
              let balance = snapshot.latestBalance,
              balance.currency == threshold.currency else { return [] }
        let key = "balance:\(snapshot.accountId):\(threshold.currency)"
        let state = try store.alertState(key: key)
        var events: [AlertEvent] = []

        if balance.total < threshold.amount {
            if state?.active != true {
                events.append(AlertEvent(
                    accountId: snapshot.accountId,
                    accountName: snapshot.accountName,
                    kind: .balanceLow,
                    firedAt: snapshot.now,
                    value: Money.formatBalance(balance.total, currency: balance.currency),
                    threshold: Money.formatBalance(threshold.amount, currency: threshold.currency),
                    metric: "官方余额低水位（\(threshold.currency)）",
                    periodKey: "armed-\(Int(snapshot.now.timeIntervalSince1970))",
                    isDemo: snapshot.isDemo
                ))
                try store.upsertAlertState(AlertState(
                    key: key,
                    active: true,
                    lastFiredAt: snapshot.now,
                    lastValue: Money.formatBalance(balance.total, currency: balance.currency)
                ))
            }
        } else if balance.total >= threshold.amount, state?.active == true {
            try store.upsertAlertState(AlertState(
                key: key,
                active: false,
                lastFiredAt: state?.lastFiredAt,
                lastValue: Money.formatBalance(balance.total, currency: balance.currency)
            ))
        }
        return events
    }

    private func evaluateSyncFailure(_ snapshot: AlertSnapshot) throws -> [AlertEvent] {
        guard snapshot.consecutiveFailures >= 3 else { return [] }
        let key = "syncfail:\(snapshot.accountId)"
        let state = try store.alertState(key: key)
        if let lastFired = state?.lastFiredAt,
           snapshot.now.timeIntervalSince(lastFired) < Self.syncFailureCooldown {
            return []
        }
        let event = AlertEvent(
            accountId: snapshot.accountId,
            accountName: snapshot.accountName,
            kind: .syncFailed,
            firedAt: snapshot.now,
            value: "连续 \(snapshot.consecutiveFailures) 次失败",
            threshold: "3 次",
            metric: "同步失败告警（6 小时冷却）",
            periodKey: "cooldown",
            isDemo: snapshot.isDemo
        )
        try store.upsertAlertState(AlertState(
            key: key,
            active: true,
            lastFiredAt: snapshot.now,
            lastValue: "\(snapshot.consecutiveFailures)"
        ))
        return [event]
    }

    private func evaluateCredential(_ snapshot: AlertSnapshot) throws -> [AlertEvent] {
        let key = "credential:\(snapshot.accountId)"
        let state = try store.alertState(key: key)
        if snapshot.credentialInvalid {
            guard state?.active != true else { return [] }
            let event = AlertEvent(
                accountId: snapshot.accountId,
                accountName: snapshot.accountName,
                kind: .credentialInvalid,
                firedAt: snapshot.now,
                value: "401 / 403",
                threshold: "凭据需重新输入",
                metric: "凭据失效，已暂停自动重试",
                periodKey: "credential",
                isDemo: snapshot.isDemo
            )
            try store.upsertAlertState(AlertState(
                key: key,
                active: true,
                lastFiredAt: snapshot.now,
                lastValue: "invalid"
            ))
            return [event]
        }
        if state?.active == true {
            try store.upsertAlertState(AlertState(
                key: key,
                active: false,
                lastFiredAt: state?.lastFiredAt,
                lastValue: "recovered"
            ))
        }
        return []
    }

    private func evaluateStale(_ snapshot: AlertSnapshot) throws -> [AlertEvent] {
        let key = "stale:\(snapshot.accountId)"
        let state = try store.alertState(key: key)
        let threshold = snapshot.refreshInterval * 2
        let stale: Bool
        if let lastSuccess = snapshot.lastSuccessAt {
            stale = snapshot.now.timeIntervalSince(lastSuccess) > threshold
        } else {
            stale = snapshot.now.timeIntervalSince(snapshot.createdAt) > threshold
        }

        if stale {
            guard state?.active != true else { return [] }
            let valueText = snapshot.lastSuccessAt.map {
                DateFormatters.mediumDateTime.string(from: $0)
            } ?? "从未成功同步"
            let event = AlertEvent(
                accountId: snapshot.accountId,
                accountName: snapshot.accountName,
                kind: .dataStale,
                firedAt: snapshot.now,
                value: valueText,
                threshold: "\(Int(snapshot.refreshInterval / 60 * 2)) 分钟",
                metric: "超过 2 个刷新周期未成功同步",
                periodKey: "stale",
                isDemo: snapshot.isDemo
            )
            try store.upsertAlertState(AlertState(
                key: key,
                active: true,
                lastFiredAt: snapshot.now,
                lastValue: valueText
            ))
            return [event]
        }

        if state?.active == true {
            try store.upsertAlertState(AlertState(
                key: key,
                active: false,
                lastFiredAt: state?.lastFiredAt,
                lastValue: "fresh"
            ))
        }
        return []
    }
}

public enum DateFormatters {
    public static let mediumDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    public static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
