import Foundation

public struct OverviewScope: Equatable, Sendable {
    public var platform: ProviderKind?
    public var accountId: String?

    public init(platform: ProviderKind? = nil, accountId: String? = nil) {
        self.platform = platform
        self.accountId = accountId
    }

    public func platformAccounts(in accounts: [Account]) -> [Account] {
        guard let platform else { return accounts }
        return accounts.filter { $0.provider == platform }
    }

    public func accounts(in accounts: [Account]) -> [Account] {
        let platformAccounts = platformAccounts(in: accounts)
        guard let accountId,
              let selected = platformAccounts.first(where: { $0.id == accountId }) else {
            return platformAccounts
        }
        return [selected]
    }
}

public struct TokenStats: Equatable, Sendable {
    public var totalTokens: Int
    public var accountsWithTokens: Int
    public var totalAccounts: Int
    public var recordCount: Int

    public init(totalTokens: Int, accountsWithTokens: Int, totalAccounts: Int, recordCount: Int) {
        self.totalTokens = totalTokens
        self.accountsWithTokens = accountsWithTokens
        self.totalAccounts = totalAccounts
        self.recordCount = recordCount
    }
}

public enum BalanceCurrencyPolicy {
    public static func preferred(options: [String], current: String?) -> String? {
        guard !options.isEmpty else { return nil }
        if let current, options.contains(current) { return current }
        if options.contains("CNY") { return "CNY" }
        return options.first
    }

    public static func shouldShowPicker(options: [String]) -> Bool {
        options.count > 1
    }
}

public enum DashboardMetrics {
    public static func usageRecords(_ records: [UsageRecord], for accounts: [Account]) -> [UsageRecord] {
        let ids = Set(accounts.map(\.id))
        return records.filter { ids.contains($0.accountId) }
    }

    public static func costs(_ records: [UsageRecord], in range: DayRange) -> [String: Decimal] {
        var result: [String: Decimal] = [:]
        for record in records where range.contains(record.day) {
            guard let cost = record.cost, let currency = record.currency else { continue }
            result[currency, default: 0] += cost
        }
        return result
    }

    public static func costs(_ records: [UsageRecord], onDay day: String) -> [String: Decimal] {
        var result: [String: Decimal] = [:]
        for record in records where record.day == day {
            guard let cost = record.cost, let currency = record.currency else { continue }
            result[currency, default: 0] += cost
        }
        return result
    }

    public static func tokenStats(
        records: [UsageRecord],
        range: DayRange,
        totalAccounts: Int
    ) -> TokenStats {
        let scoped = records.filter { range.contains($0.day) }
        let total = scoped.reduce(0) { $0 + ($1.totalTokens ?? 0) }
        let withTokens = Set(scoped.filter { $0.totalTokens != nil }.map(\.accountId))
        return TokenStats(
            totalTokens: total,
            accountsWithTokens: withTokens.count,
            totalAccounts: totalAccounts,
            recordCount: scoped.count
        )
    }

    /// 只聚合完整、可用的官方额度；部分成功 / 失败账户不参与计算。
    public static func creditsRemaining(
        accounts: [Account],
        quotas: [String: QuotaSnapshot]
    ) -> [String: Decimal] {
        var result: [String: Decimal] = [:]
        for account in accounts where account.enabled && account.capabilities.credits {
            guard let quota = quotas[account.id],
                  AccountDataStatus.quota(account: account, quota: quota).isActual else { continue }
            result[quota.currency, default: 0] += quota.remaining
        }
        return result
    }

    /// 币种选项只来自当前范围内已成功同步的余额数据。
    public static func balanceCurrencies(
        accounts: [Account],
        balances: [String: [String: BalanceSnapshot]]
    ) -> [String] {
        var result = Set<String>()
        for account in accounts where account.enabled && account.capabilities.balance {
            let snapshots = balances[account.id] ?? [:]
            guard !snapshots.isEmpty else { continue }
            let ordered = snapshots.values.sorted { $0.currency < $1.currency }
            guard AccountDataStatus.balance(account: account, balances: ordered).isActual else { continue }
            result.formUnion(snapshots.keys)
        }
        return result.sorted()
    }

    /// 按账户汇总指定币种的官方余额；没有完整数据时返回 nil。
    public static func balanceTotal(
        accounts: [Account],
        balances: [String: [String: BalanceSnapshot]],
        currency: String
    ) -> Decimal? {
        var total: Decimal?
        for account in accounts where account.enabled && account.capabilities.balance {
            let snapshots = balances[account.id] ?? [:]
            let ordered = snapshots.values.sorted { $0.currency < $1.currency }
            guard AccountDataStatus.balance(account: account, balances: ordered).isActual,
                  let snapshot = snapshots[currency] else { continue }
            total = (total ?? 0) + snapshot.total
        }
        return total
    }

    /// 预算剩余只计算数据完整的账户；部分成功 / 缺失账户被排除。
    public static func budgetRemaining(
        accounts: [Account],
        records: [UsageRecord],
        range: DayRange
    ) -> [String: Decimal] {
        var result: [String: Decimal] = [:]
        for account in accounts {
            guard let budget = account.budget,
                  let spend = BudgetMath.availableSpend(account: account, records: records, range: range),
                  let remaining = BudgetMath.remaining(budget: budget, spend: spend) else { continue }
            result[budget.currency, default: 0] += remaining
        }
        return result
    }
}
