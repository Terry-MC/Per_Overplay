import Foundation

public enum AccountDataStatus {
    public static func balance(
        account: Account,
        balances: [BalanceSnapshot]
    ) -> DataStatus {
        if !account.enabled {
            return .unavailable("该账户已禁用")
        }
        if account.credentialInvalid {
            return .failed("凭据失效：\(account.lastError ?? "需要重新输入 API Key")")
        }
        if let error = account.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty {
            return balances.isEmpty
                ? .failed("同步失败：\(error)")
                : .partial("同步失败：\(error)")
        }
        guard account.capabilities.balance else {
            return .unavailable("\(account.provider.displayName) 不提供官方余额")
        }
        guard !balances.isEmpty else {
            if account.lastSuccessAt == nil {
                return .missing("尚未成功同步余额")
            }
            return .missing("厂商未返回余额数据")
        }
        let unavailable = balances.filter { $0.isAvailable == false }
        if !unavailable.isEmpty {
            let codes = unavailable.map(\.currency).sorted().joined(separator: " / ")
            return .anomaly("官方标记 \(codes) 余额不可用；请检查账户状态")
        }
        return .actual
    }

    public static func quota(
        account: Account,
        quota: QuotaSnapshot?
    ) -> DataStatus {
        if !account.enabled {
            return .unavailable("该账户已禁用")
        }
        if account.credentialInvalid {
            return .failed("凭据失效：\(account.lastError ?? "需要重新输入 API Key")")
        }
        if let error = account.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty {
            return quota == nil
                ? .failed("同步失败：\(error)")
                : .partial("同步失败：\(error)")
        }
        guard account.capabilities.credits else {
            return .unavailable("\(account.provider.displayName) 不提供官方额度")
        }
        guard quota != nil else {
            if account.lastSuccessAt == nil {
                return .missing("尚未成功同步官方额度")
            }
            return .missing("厂商未返回官方额度数据")
        }
        return .actual
    }

    public static func budget(
        account: Account,
        spend: Decimal?
    ) -> DataStatus {
        guard account.budget != nil else {
            return .unavailable("未设置本地预算")
        }
        if !account.enabled {
            return .unavailable("该账户已禁用")
        }
        if account.credentialInvalid {
            return .failed("凭据失效：\(account.lastError ?? "需要重新输入 API Key")")
        }
        if let error = account.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty {
            return .partial("同步失败：\(error)")
        }
        guard spend != nil else {
            return .partial("本月用量数据不完整，暂不能计算预算")
        }
        return .actual
    }

    public static func usage(
        accounts: [Account],
        records: [UsageRecord],
        emptyReason: String
    ) -> DataStatus {
        guard !accounts.isEmpty else { return .missing(emptyReason) }
        let enabled = accounts.filter(\.enabled)
        guard !enabled.isEmpty else { return .unavailable("所选账户均已禁用") }

        let statuses = enabled.map { account in
            usage(account: account, records: records)
        }
        return aggregate(statuses, emptyReason: emptyReason)
    }

    public static func usage(account: Account, records: [UsageRecord]) -> DataStatus {
        if !account.enabled { return .unavailable("该账户已禁用") }
        if account.credentialInvalid {
            return .failed("凭据失效：\(account.lastError ?? "需要重新输入 API Key")")
        }
        if let error = account.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty {
            return account.lastSuccessAt == nil
                ? .failed("同步失败：\(error)")
                : .partial("同步失败：\(error)")
        }
        guard account.capabilities.usage else {
            return .unavailable("\(account.provider.displayName) 不提供历史用量")
        }
        guard account.lastSuccessAt != nil else {
            return .missing("尚未成功同步用量")
        }
        guard records.contains(where: { $0.accountId == account.id }) else {
            return .missing("已连接，但厂商未返回用量数据")
        }
        return .actual
    }

    public static func aggregate(_ statuses: [DataStatus], emptyReason: String) -> DataStatus {
        guard !statuses.isEmpty else { return .missing(emptyReason) }
        if statuses.allSatisfy(\.isActual) { return .actual }
        let reasons = statuses.compactMap(\.reason)
        let joined = reasons.joined(separator: "；")
        if statuses.contains(where: \.isActual) { return .partial(joined) }
        if statuses.contains(where: \.isPartial) { return .partial(joined) }
        if statuses.contains(where: \.isFailed) { return .failed(joined) }
        if statuses.contains(where: \.isAnomaly) { return .anomaly(joined) }
        if statuses.allSatisfy(\.isUnavailable) { return .unavailable(joined) }
        return .missing(joined)
    }
}
