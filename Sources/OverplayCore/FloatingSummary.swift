import Foundation

public struct FloatingLine: Equatable, Sendable {
    public var label: String
    public var value: Decimal
    public var currency: String
    public var status: DataStatus

    public init(label: String, value: Decimal, currency: String, status: DataStatus) {
        self.label = label
        self.value = value
        self.currency = currency
        self.status = status
    }
}

public struct FloatingAccountRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var officialName: String?
    public var iconName: String?
    public var provider: ProviderKind
    public var isDemo: Bool
    public var enabled: Bool
    public var primaryLines: [FloatingLine]
    public var primaryStatus: DataStatus
    public var secondaryLines: [FloatingLine]
    public var secondaryStatus: DataStatus?
    public var budgetRatio: Decimal?
    public var errorSummary: String?
    public var lastSuccessAt: Date?
    public var unacknowledgedAlerts: Int
    public var criticalAlerts: Int

    public init(
        id: String,
        name: String,
        officialName: String? = nil,
        iconName: String? = nil,
        provider: ProviderKind,
        isDemo: Bool,
        enabled: Bool,
        primaryLines: [FloatingLine],
        primaryStatus: DataStatus,
        secondaryLines: [FloatingLine],
        secondaryStatus: DataStatus?,
        budgetRatio: Decimal?,
        errorSummary: String?,
        lastSuccessAt: Date?,
        unacknowledgedAlerts: Int,
        criticalAlerts: Int
    ) {
        self.id = id
        self.name = name
        self.officialName = officialName
        self.iconName = iconName
        self.provider = provider
        self.isDemo = isDemo
        self.enabled = enabled
        self.primaryLines = primaryLines
        self.primaryStatus = primaryStatus
        self.secondaryLines = secondaryLines
        self.secondaryStatus = secondaryStatus
        self.budgetRatio = budgetRatio
        self.errorSummary = errorSummary
        self.lastSuccessAt = lastSuccessAt
        self.unacknowledgedAlerts = unacknowledgedAlerts
        self.criticalAlerts = criticalAlerts
    }
}

public struct FloatingSummary: Equatable, Sendable {
    public var todayCosts: [String: Decimal]
    public var todayStatus: DataStatus
    public var creditsRemaining: [String: Decimal]
    public var creditsStatus: DataStatus
    public var balances: [String: Decimal]
    public var balancesStatus: DataStatus
    public var tokenTotal: Int
    public var tokenAccounts: Int
    public var totalAccounts: Int
    public var requestCount: Int
    public var requestsAvailable: Bool
    public var tokenStatus: DataStatus
    public var unacknowledgedAlertCount: Int
    public var criticalAlertCount: Int
    public var lastSyncAt: Date?
    public var rows: [FloatingAccountRow]
    public var activeAccountCount: Int
    public var disabledAccountCount: Int

    public init(
        todayCosts: [String: Decimal],
        todayStatus: DataStatus,
        creditsRemaining: [String: Decimal],
        creditsStatus: DataStatus,
        balances: [String: Decimal],
        balancesStatus: DataStatus,
        tokenTotal: Int,
        tokenAccounts: Int,
        totalAccounts: Int,
        requestCount: Int,
        requestsAvailable: Bool,
        tokenStatus: DataStatus,
        unacknowledgedAlertCount: Int,
        criticalAlertCount: Int,
        lastSyncAt: Date?,
        rows: [FloatingAccountRow],
        activeAccountCount: Int,
        disabledAccountCount: Int
    ) {
        self.todayCosts = todayCosts
        self.todayStatus = todayStatus
        self.creditsRemaining = creditsRemaining
        self.creditsStatus = creditsStatus
        self.balances = balances
        self.balancesStatus = balancesStatus
        self.tokenTotal = tokenTotal
        self.tokenAccounts = tokenAccounts
        self.totalAccounts = totalAccounts
        self.requestCount = requestCount
        self.requestsAvailable = requestsAvailable
        self.tokenStatus = tokenStatus
        self.unacknowledgedAlertCount = unacknowledgedAlertCount
        self.criticalAlertCount = criticalAlertCount
        self.lastSyncAt = lastSyncAt
        self.rows = rows
        self.activeAccountCount = activeAccountCount
        self.disabledAccountCount = disabledAccountCount
    }
}

public enum FloatingSummaryBuilder {
    public static let criticalAlertKinds: Set<AlertKind> = [
        .budgetExceeded, .balanceLow, .credentialInvalid, .syncFailed
    ]

    public static func make(
        accounts: [Account],
        usageRecords: [UsageRecord],
        balances: [String: [String: BalanceSnapshot]],
        quotas: [String: QuotaSnapshot],
        alerts: [AlertEvent],
        now: Date
    ) -> FloatingSummary {
        let usageAccounts = accounts.filter { $0.capabilities.usage }
        let balanceAccounts = accounts.filter { $0.capabilities.balance }
        let creditAccounts = accounts.filter { $0.capabilities.credits }
        let today = CalendarDay.string(for: now, timeZone: CalendarDay.utc)
        let todayRecords = usageRecords.filter { $0.day == today }
        let lastThirty = CalendarDay.range(preset: .thirty, now: now)

        let todayCosts = DashboardMetrics.costs(todayRecords, onDay: today)
        let todayStatus: DataStatus
        if usageAccounts.isEmpty {
            todayStatus = .unavailable("没有提供用量数据的账户")
        } else if todayRecords.isEmpty {
            todayStatus = .missing("今日暂无厂商记录")
        } else {
            todayStatus = AccountDataStatus.usage(
                accounts: usageAccounts,
                records: todayRecords,
                emptyReason: "今日暂无厂商记录"
            )
        }

        let credits = DashboardMetrics.creditsRemaining(accounts: creditAccounts, quotas: quotas)
        let creditsStatus: DataStatus
        if creditAccounts.isEmpty {
            creditsStatus = .unavailable("没有提供官方额度的账户")
        } else {
            creditsStatus = AccountDataStatus.aggregate(
                creditAccounts.map { AccountDataStatus.quota(account: $0, quota: quotas[$0.id]) },
                emptyReason: "没有官方额度数据"
            )
        }

        var balancesByCurrency: [String: Decimal] = [:]
        let currencyOptions = DashboardMetrics.balanceCurrencies(
            accounts: balanceAccounts,
            balances: balances
        )
        for currency in currencyOptions {
            if let total = DashboardMetrics.balanceTotal(
                accounts: balanceAccounts,
                balances: balances,
                currency: currency
            ) {
                balancesByCurrency[currency] = total
            }
        }
        let balancesStatus: DataStatus
        if balanceAccounts.isEmpty {
            balancesStatus = .unavailable("没有提供官方余额的账户")
        } else {
            balancesStatus = AccountDataStatus.aggregate(
                balanceAccounts.map {
                    AccountDataStatus.balance(
                        account: $0,
                        balances: (balances[$0.id] ?? [:]).values.sorted { $0.currency < $1.currency }
                    )
                },
                emptyReason: "没有官方余额数据"
            )
        }

        let periodRecords = usageRecords.filter { lastThirty.contains($0.day) }
        let stats = DashboardMetrics.tokenStats(
            records: periodRecords,
            range: lastThirty,
            totalAccounts: accounts.count
        )
        let tokenStatus: DataStatus
        if usageAccounts.isEmpty {
            tokenStatus = .unavailable("没有提供历史用量的账户")
        } else if stats.accountsWithTokens == 0 {
            tokenStatus = .missing("厂商未提供 token 数据")
        } else {
            tokenStatus = AccountDataStatus.usage(
                accounts: usageAccounts,
                records: periodRecords,
                emptyReason: "没有可用的 token 数据"
            )
        }
        let requestRecords = periodRecords.filter { $0.requests != nil }
        let requestCount = requestRecords.reduce(0) { $0 + ($1.requests ?? 0) }
        let requestsAvailable = !requestRecords.isEmpty

        let unacknowledged = alerts.filter { !$0.acknowledged }
        let criticalCount = unacknowledged.filter { criticalAlertKinds.contains($0.kind) }.count
        let lastSyncAt = accounts.compactMap(\.lastSuccessAt).max()

        let rows = accounts.map { account in
            buildRow(
                account: account,
                balances: (balances[account.id] ?? [:]).values.sorted { $0.currency < $1.currency },
                quota: quotas[account.id],
                usageRecords: usageRecords,
                alerts: alerts,
                now: now
            )
        }

        return FloatingSummary(
            todayCosts: todayCosts,
            todayStatus: todayStatus,
            creditsRemaining: credits,
            creditsStatus: creditsStatus,
            balances: balancesByCurrency,
            balancesStatus: balancesStatus,
            tokenTotal: stats.totalTokens,
            tokenAccounts: stats.accountsWithTokens,
            totalAccounts: stats.totalAccounts,
            requestCount: requestCount,
            requestsAvailable: requestsAvailable,
            tokenStatus: tokenStatus,
            unacknowledgedAlertCount: unacknowledged.count,
            criticalAlertCount: criticalCount,
            lastSyncAt: lastSyncAt,
            rows: rows,
            activeAccountCount: accounts.filter(\.enabled).count,
            disabledAccountCount: accounts.filter { !$0.enabled }.count
        )
    }

    private static func buildRow(
        account: Account,
        balances: [BalanceSnapshot],
        quota: QuotaSnapshot?,
        usageRecords: [UsageRecord],
        alerts: [AlertEvent],
        now: Date
    ) -> FloatingAccountRow {
        var primaryLines: [FloatingLine] = []
        let primaryStatus: DataStatus
        if account.capabilities.balance {
            primaryStatus = AccountDataStatus.balance(account: account, balances: balances)
            for snapshot in balances {
                primaryLines.append(FloatingLine(
                    label: "官方余额",
                    value: snapshot.total,
                    currency: snapshot.currency,
                    status: primaryStatus
                ))
            }
        } else if account.capabilities.credits {
            primaryStatus = AccountDataStatus.quota(account: account, quota: quota)
            if let quota, primaryStatus.isActual {
                primaryLines.append(FloatingLine(
                    label: "官方额度",
                    value: quota.remaining,
                    currency: quota.currency,
                    status: primaryStatus
                ))
            }
        } else if account.capabilities.usage {
            primaryStatus = AccountDataStatus.usage(account: account, records: usageRecords)
            let totals = ProviderAnalysisMetrics.totals(records: usageRecords, account: account)
            if totals.costAvailable {
                for currency in totals.costs.keys.sorted() {
                    primaryLines.append(FloatingLine(
                        label: "所选范围费用",
                        value: totals.costs[currency] ?? 0,
                        currency: currency,
                        status: primaryStatus
                    ))
                }
            }
        } else {
            primaryStatus = .unavailable("该平台没有可用主指标")
        }

        var secondaryLines: [FloatingLine] = []
        var secondaryStatus: DataStatus?
        var budgetRatio: Decimal?
        if let budget = account.budget {
            let (_, monthRange) = CalendarDay.monthRange(now: now)
            let spend = BudgetMath.availableSpend(
                account: account,
                records: usageRecords,
                range: monthRange
            )
            let status = AccountDataStatus.budget(account: account, spend: spend)
            secondaryStatus = status
            budgetRatio = BudgetMath.ratio(spend: spend, budget: budget)
            if let spend, let remaining = BudgetMath.remaining(budget: budget, spend: spend) {
                secondaryLines.append(FloatingLine(
                    label: remaining < 0 ? "本地预算超支" : "本地预算剩余",
                    value: abs(remaining),
                    currency: budget.currency,
                    status: status
                ))
            }
        }

        var errorSummary: String?
        if account.credentialInvalid {
            errorSummary = "凭据失效：\(account.lastError ?? "需要重新输入 API Key")"
        } else if let error = account.lastError, !error.isEmpty {
            errorSummary = "同步失败：\(error)"
        } else if balances.contains(where: { $0.isAvailable == false }) {
            errorSummary = "官方标记余额不可用"
        }

        let accountAlerts = alerts.filter { $0.accountId == account.id && !$0.acknowledged }
        return FloatingAccountRow(
            id: account.id,
            name: account.displayName,
            officialName: account.officialName,
            iconName: account.iconName,
            provider: account.provider,
            isDemo: account.isDemo,
            enabled: account.enabled,
            primaryLines: primaryLines,
            primaryStatus: primaryStatus,
            secondaryLines: secondaryLines,
            secondaryStatus: secondaryStatus,
            budgetRatio: budgetRatio,
            errorSummary: errorSummary,
            lastSuccessAt: account.lastSuccessAt,
            unacknowledgedAlerts: accountAlerts.count,
            criticalAlerts: accountAlerts.filter { criticalAlertKinds.contains($0.kind) }.count
        )
    }
}
