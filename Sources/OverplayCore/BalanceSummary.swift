import Foundation

public enum BalanceSummary {
    /// 按账户过滤后按币种汇总；币种是分组键，不同币种永不相加。
    public static func totalsByCurrency(
        balances: [String: [String: BalanceSnapshot]],
        accountIds: Set<String>
    ) -> [String: Decimal] {
        var totals: [String: Decimal] = [:]
        for (accountId, byCurrency) in balances where accountIds.contains(accountId) {
            for snapshot in byCurrency.values {
                totals[snapshot.currency, default: 0] += snapshot.total
            }
        }
        return totals
    }

    public static func currencies(for snapshots: [BalanceSnapshot]) -> [String] {
        Array(Set(snapshots.map(\.currency))).sorted()
    }
}
