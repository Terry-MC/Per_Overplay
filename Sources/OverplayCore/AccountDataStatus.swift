import Foundation

public enum AccountDataStatus {
    public static func balance(
        account: Account,
        balances: [BalanceSnapshot]
    ) -> DataStatus {
        if !account.enabled {
            return .unavailable(L10n.t("core.accountStatus.c07a0777f9"))
        }
        if account.credentialInvalid {
            return .failed(L10n.f("app.29dd8b4768", L10n.t(account.lastError ?? L10n.t("credential.fallback.apiKey"))))
        }
        if let error = account.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty {
            return balances.isEmpty
                ? .failed(L10n.f("app.b3c04fc986", L10n.t(error)))
                : .partial(L10n.f("app.b3c04fc986", L10n.t(error)))
        }
        guard account.capabilities.balance else {
            return .unavailable(L10n.f("core.accountStatus.8e13d1bfd2", account.provider.displayName))
        }
        guard !balances.isEmpty else {
            if account.lastSuccessAt == nil {
                return .missing(L10n.t("core.accountStatus.17acb0eaf2"))
            }
            return .missing(L10n.t("core.accountStatus.f0434eb0ef"))
        }
        let unavailable = balances.filter { $0.isAvailable == false }
        if !unavailable.isEmpty {
            let codes = unavailable.map(\.currency).sorted().joined(separator: " / ")
            return .anomaly(L10n.f("core.accountStatus.2220119e5e", codes))
        }
        return .actual
    }

    public static func quota(
        account: Account,
        quota: QuotaSnapshot?
    ) -> DataStatus {
        if !account.enabled {
            return .unavailable(L10n.t("core.accountStatus.c07a0777f9"))
        }
        if account.credentialInvalid {
            return .failed(L10n.f("app.29dd8b4768", L10n.t(account.lastError ?? L10n.t("credential.fallback.apiKey"))))
        }
        if let error = account.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty {
            return quota == nil
                ? .failed(L10n.f("app.b3c04fc986", L10n.t(error)))
                : .partial(L10n.f("app.b3c04fc986", L10n.t(error)))
        }
        guard account.capabilities.credits else {
            return .unavailable(L10n.f("core.accountStatus.980ff56512", account.provider.displayName))
        }
        guard quota != nil else {
            if account.lastSuccessAt == nil {
                return .missing(L10n.t("core.accountStatus.772a7f6811"))
            }
            return .missing(L10n.t("core.accountStatus.a5fe066fef"))
        }
        return .actual
    }

    public static func budget(
        account: Account,
        spend: Decimal?
    ) -> DataStatus {
        guard account.budget != nil else {
            return .unavailable(L10n.t("core.accountStatus.fa29ac2cb7"))
        }
        if !account.enabled {
            return .unavailable(L10n.t("core.accountStatus.c07a0777f9"))
        }
        if account.credentialInvalid {
            return .failed(L10n.f("app.29dd8b4768", L10n.t(account.lastError ?? L10n.t("credential.fallback.apiKey"))))
        }
        if let error = account.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty {
            return .partial(L10n.f("app.b3c04fc986", L10n.t(error)))
        }
        guard spend != nil else {
            return .partial(L10n.t("core.accountStatus.eae7a53e98"))
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
        guard !enabled.isEmpty else { return .unavailable(L10n.t("core.accountStatus.b61f5e75da")) }

        let statuses = enabled.map { account in
            usage(account: account, records: records)
        }
        return aggregate(statuses, emptyReason: emptyReason)
    }

    public static func usage(account: Account, records: [UsageRecord]) -> DataStatus {
        if !account.enabled { return .unavailable(L10n.t("core.accountStatus.c07a0777f9")) }
        if account.credentialInvalid {
            return .failed(L10n.f("app.29dd8b4768", L10n.t(account.lastError ?? L10n.t("credential.fallback.apiKey"))))
        }
        if let error = account.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty {
            return account.lastSuccessAt == nil
                ? .failed(L10n.f("app.b3c04fc986", L10n.t(error)))
                : .partial(L10n.f("app.b3c04fc986", L10n.t(error)))
        }
        guard account.capabilities.usage else {
            return .unavailable(L10n.f("core.accountStatus.fb0dfb6f9e", account.provider.displayName))
        }
        guard account.lastSuccessAt != nil else {
            return .missing(L10n.t("core.accountStatus.1088770bda"))
        }
        guard records.contains(where: { $0.accountId == account.id }) else {
            return .missing(L10n.t("core.accountStatus.ca45da3378"))
        }
        return .actual
    }

    public static func aggregate(_ statuses: [DataStatus], emptyReason: String) -> DataStatus {
        guard !statuses.isEmpty else { return .missing(emptyReason) }
        if statuses.allSatisfy(\.isActual) { return .actual }
        let reasons = statuses.compactMap(\.reason)
        let joined = reasons.joined(separator: L10n.t("common.listSeparator"))
        if statuses.contains(where: \.isActual) { return .partial(joined) }
        if statuses.contains(where: \.isPartial) { return .partial(joined) }
        if statuses.contains(where: \.isFailed) { return .failed(joined) }
        if statuses.contains(where: \.isAnomaly) { return .anomaly(joined) }
        if statuses.allSatisfy(\.isUnavailable) { return .unavailable(joined) }
        return .missing(joined)
    }
}
