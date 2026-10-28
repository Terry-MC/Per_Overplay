import XCTest
@testable import OverplayCore

final class BudgetMathTests: XCTestCase {
    private let now = TestClock.date(2026, 10, 28)
    private let range = DayRange(startDay: "2026-10-01", endDay: "2026-10-31")

    private func record(
        accountId: String = "a",
        day: String = "2026-10-10",
        cost: Decimal? = 10,
        currency: String? = "USD"
    ) -> UsageRecord {
        UsageRecord(
            accountId: accountId, accountName: "A", provider: .openrouter, day: day,
            model: "m", cost: cost, currency: currency, source: "test", updatedAt: now
        )
    }

    func testSpendFiltersAccountCurrencyAndRange() {
        let records = [
            record(cost: 10),
            record(cost: 5),
            record(cost: 7, currency: "CNY"),
            record(accountId: "b", cost: 99),
            record(day: "2026-09-30", cost: 99),
            record(cost: nil)
        ]
        XCTAssertEqual(
            BudgetMath.spend(records: records, accountId: "a", currency: "USD", range: range),
            15
        )
    }

    func testRatioAndRemaining() {
        let budget = Budget(amount: 100, currency: "USD")
        XCTAssertEqual(BudgetMath.ratio(spend: 85, budget: budget), Decimal(85))
        XCTAssertEqual(BudgetMath.remaining(budget: budget, spend: 85), Decimal(15))
        XCTAssertEqual(BudgetMath.remaining(budget: budget, spend: 120), Decimal(-20))
        XCTAssertNil(BudgetMath.ratio(spend: 10, budget: Budget(amount: 0, currency: "USD")))
        XCTAssertNil(BudgetMath.ratio(spend: nil, budget: budget))
    }

    func testForecast() {
        let forecast = BudgetMath.forecast(spend: 50, now: now, timeZone: TestClock.utc, calendar: TestClock.calendar)
        XCTAssertEqual(forecast.map { Money.rounded($0, scale: 2) }, Decimal(string: "55.36"))
    }
}

extension BudgetMathTests {
    func testAvailableSpendRequiresCompleteAccountSync() {
        let budget = Budget(amount: 100, currency: "USD")
        let records = [record(cost: 10), record(cost: 5)]

        func account(
            provider: ProviderKind = .openrouter,
            enabled: Bool = true,
            success: Date? = TestClock.date(2026, 10, 28),
            credentialInvalid: Bool = false,
            lastError: String? = nil
        ) -> Account {
            Account(
                id: "a",
                provider: provider,
                name: "OR",
                enabled: enabled,
                lastSuccessAt: success,
                credentialInvalid: credentialInvalid,
                lastError: lastError,
                budget: budget
            )
        }

        XCTAssertEqual(
            BudgetMath.availableSpend(account: account(), records: records, range: range),
            15
        )
        XCTAssertNil(BudgetMath.availableSpend(
            account: account(lastError: "activity 部分失败"), records: records, range: range
        ))
        XCTAssertNil(BudgetMath.availableSpend(
            account: account(credentialInvalid: true), records: records, range: range
        ))
        XCTAssertNil(BudgetMath.availableSpend(
            account: account(enabled: false), records: records, range: range
        ))
        XCTAssertNil(BudgetMath.availableSpend(
            account: account(success: nil), records: records, range: range
        ))
        XCTAssertNil(BudgetMath.availableSpend(
            account: account(provider: .deepseek), records: records, range: range
        ))
    }
}
