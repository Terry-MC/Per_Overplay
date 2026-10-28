import Foundation

public enum BudgetMath {
    public static func spend(
        records: [UsageRecord],
        accountId: String,
        currency: String,
        range: DayRange
    ) -> Decimal {
        records
            .filter { $0.accountId == accountId && range.contains($0.day) }
            .reduce(Decimal(0)) { partial, record in
                guard record.currency == currency, let cost = record.cost else { return partial }
                return partial + cost
            }
    }

    /// Returns nil when the account does not have a complete, usable activity sync.
    /// A partial/failed/credential-invalid account must not be displayed as 0 spend.
    public static func availableSpend(
        account: Account,
        records: [UsageRecord],
        range: DayRange
    ) -> Decimal? {
        guard account.provider.capabilities.usage,
              account.enabled,
              !account.credentialInvalid,
              account.lastError == nil,
              account.lastSuccessAt != nil,
              let budget = account.budget else { return nil }
        return spend(
            records: records,
            accountId: account.id,
            currency: budget.currency,
            range: range
        )
    }

    public static func ratio(spend: Decimal?, budget: Budget?) -> Decimal? {
        guard let spend, let budget, budget.amount > 0 else { return nil }
        return spend / budget.amount * 100
    }

    public static func remaining(budget: Budget?, spend: Decimal?) -> Decimal? {
        guard let budget, let spend else { return nil }
        return budget.amount - spend
    }

    public static func forecast(
        spend: Decimal?,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> Decimal? {
        guard let spend else { return nil }
        return UsageMath.forecastMonthSpend(
            monthToDate: spend, now: now, timeZone: timeZone, calendar: calendar
        )
    }
}
