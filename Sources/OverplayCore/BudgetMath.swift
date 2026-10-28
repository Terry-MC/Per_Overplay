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
