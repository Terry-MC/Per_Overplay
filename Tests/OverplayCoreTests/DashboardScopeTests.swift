import XCTest
@testable import OverplayCore

final class DashboardScopeTests: XCTestCase {
    private let range = DayRange(startDay: "2026-10-01", endDay: "2026-10-31")

    private func account(
        id: String,
        provider: ProviderKind,
        name: String? = nil,
        enabled: Bool = true,
        lastSuccessAt: Date? = Date(),
        lastError: String? = nil,
        budget: Budget? = nil
    ) -> Account {
        Account(
            id: id,
            provider: provider,
            name: name ?? id,
            enabled: enabled,
            lastSuccessAt: lastSuccessAt,
            lastError: lastError,
            budget: budget
        )
    }

    private func record(
        account: Account,
        day: String = "2026-10-27",
        cost: Decimal? = nil,
        currency: String? = nil,
        prompt: Int? = nil,
        completion: Int? = nil
    ) -> UsageRecord {
        UsageRecord(
            accountId: account.id,
            accountName: account.displayName,
            provider: account.provider,
            day: day,
            model: "test-model",
            promptTokens: prompt,
            completionTokens: completion,
            cost: cost,
            currency: currency,
            source: "test"
        )
    }

    func testPlatformAndAccountScope() {
        let deepSeekA = account(id: "ds-a", provider: .deepseek)
        let deepSeekB = account(id: "ds-b", provider: .deepseek)
        let kimi = account(id: "kimi", provider: .kimi)
        let openAI = account(id: "openai", provider: .openai)
        let all = [deepSeekA, deepSeekB, kimi, openAI]

        XCTAssertEqual(
            OverviewScope(platform: .deepseek).accounts(in: all).map(\.id),
            ["ds-a", "ds-b"]
        )
        XCTAssertEqual(
            OverviewScope(platform: .deepseek, accountId: "ds-b").accounts(in: all).map(\.id),
            ["ds-b"]
        )
        XCTAssertEqual(
            OverviewScope(accountId: "kimi").accounts(in: all).map(\.id),
            ["kimi"]
        )
        XCTAssertEqual(
            OverviewScope(platform: .deepseek, accountId: "kimi").accounts(in: all).map(\.id),
            ["ds-a", "ds-b"],
            "不属于当前平台的账户 ID 不得跨平台泄漏"
        )
        XCTAssertEqual(
            OverviewScope(platform: .kimi).platformAccounts(in: all).map(\.id),
            ["kimi"]
        )
    }

    func testCostsStaySeparatedByCurrencyAndScope() {
        let kimi = account(id: "kimi", provider: .kimi)
        let openAI = account(id: "openai", provider: .openai)
        let records = [
            record(account: kimi, cost: 10, currency: "CNY"),
            record(account: kimi, day: "2026-10-26", cost: 5, currency: "CNY"),
            record(account: openAI, cost: 2, currency: "USD"),
            record(account: openAI, day: "2026-09-30", cost: 99, currency: "USD")
        ]

        let scoped = DashboardMetrics.usageRecords(records, for: [kimi])
        let costs = DashboardMetrics.costs(scoped, in: range)
        XCTAssertEqual(costs, ["CNY": 15])
        XCTAssertNil(costs["USD"])
        XCTAssertEqual(
            DashboardMetrics.costs(records, onDay: "2026-10-26"),
            ["CNY": 5]
        )
    }

    func testTokenStatsExcludeMissingTokenFields() {
        let kimi = account(id: "kimi", provider: .kimi)
        let glm = account(id: "glm", provider: .glm)
        let records = [
            record(account: kimi, prompt: 10, completion: 5),
            record(account: glm),
            record(account: glm, day: "2026-10-26", prompt: 0, completion: 7)
        ]
        let stats = DashboardMetrics.tokenStats(
            records: records,
            range: range,
            totalAccounts: 3
        )
        XCTAssertEqual(stats.totalTokens, 22)
        XCTAssertEqual(stats.accountsWithTokens, 2)
        XCTAssertEqual(stats.totalAccounts, 3)
        XCTAssertEqual(stats.recordCount, 3)
    }

    func testCreditsExcludePartialAndFailedAccounts() {
        let good = account(id: "good", provider: .openrouter)
        let kimi = account(id: "kimi", provider: .kimi)
        let partial = account(id: "partial", provider: .glm, lastError: "timeout")
        let missing = account(id: "missing", provider: .qwen, lastSuccessAt: nil)

        let quotas = [
            good.id: QuotaSnapshot(
                accountId: good.id, totalCredits: 100, totalUsage: 20, remaining: 80,
                currency: "USD", asOf: Date(), source: "test"
            ),
            kimi.id: QuotaSnapshot(
                accountId: kimi.id, totalCredits: 1000, totalUsage: 250, remaining: 750,
                currency: "CNY", asOf: Date(), source: "test"
            ),
            partial.id: QuotaSnapshot(
                accountId: partial.id, totalCredits: 100, totalUsage: 90, remaining: 10,
                currency: "CNY", asOf: Date(), source: "test"
            )
        ]

        XCTAssertEqual(
            DashboardMetrics.creditsRemaining(
                accounts: [good, kimi, partial, missing],
                quotas: quotas
            ),
            ["USD": 80, "CNY": 750],
            "部分成功 / 未同步账户不得参与额度汇总"
        )
    }

    func testBalanceCurrencyOptionsAndTotalsAreIsolated() {
        let cny = account(id: "ds-cny", provider: .deepseek)
        let usd = account(id: "ds-usd", provider: .deepseek)
        let partial = account(id: "ds-partial", provider: .deepseek, lastError: "timeout")
        let balances: [String: [String: BalanceSnapshot]] = [
            cny.id: ["CNY": BalanceSnapshot(
                accountId: cny.id, currency: "CNY", total: 92.4,
                asOf: Date(), source: "test"
            )],
            usd.id: ["USD": BalanceSnapshot(
                accountId: usd.id, currency: "USD", total: 32.6,
                asOf: Date(), source: "test"
            )],
            partial.id: ["CNY": BalanceSnapshot(
                accountId: partial.id, currency: "CNY", total: 999,
                asOf: Date(), source: "test"
            )]
        ]

        let options = DashboardMetrics.balanceCurrencies(
            accounts: [cny, usd, partial],
            balances: balances
        )
        XCTAssertEqual(options, ["CNY", "USD"])
        XCTAssertEqual(
            DashboardMetrics.balanceTotal(
                accounts: [cny, usd, partial],
                balances: balances,
                currency: "CNY"
            ),
            92.4,
            "部分成功账户的余额不得混入汇总"
        )
        XCTAssertEqual(
            DashboardMetrics.balanceTotal(
                accounts: [cny, usd, partial],
                balances: balances,
                currency: "USD"
            ),
            32.6
        )
        XCTAssertNil(
            DashboardMetrics.balanceTotal(
                accounts: [cny, usd],
                balances: balances,
                currency: "EUR"
            )
        )
    }

    func testCurrencySelectionDefaultsAndAccountSwitch() {
        XCTAssertEqual(BalanceCurrencyPolicy.preferred(options: ["CNY", "USD"], current: nil), "CNY")
        XCTAssertEqual(BalanceCurrencyPolicy.preferred(options: ["USD"], current: "CNY"), "USD")
        XCTAssertEqual(BalanceCurrencyPolicy.preferred(options: ["CNY", "USD"], current: "USD"), "USD")
        XCTAssertEqual(BalanceCurrencyPolicy.preferred(options: ["EUR", "USD"], current: nil), "EUR")
        XCTAssertNil(BalanceCurrencyPolicy.preferred(options: [], current: "CNY"))
        XCTAssertFalse(BalanceCurrencyPolicy.shouldShowPicker(options: ["CNY"]),
                       "单账户单币种必须隐藏下拉")
        XCTAssertFalse(BalanceCurrencyPolicy.shouldShowPicker(options: []))
        XCTAssertTrue(BalanceCurrencyPolicy.shouldShowPicker(options: ["CNY", "USD"]))
    }

    func testBudgetRemainingExcludesIncompleteAccounts() {
        let good = account(
            id: "good",
            provider: .openrouter,
            budget: Budget(amount: 100, currency: "USD")
        )
        let partial = account(
            id: "partial",
            provider: .openrouter,
            lastError: "timeout",
            budget: Budget(amount: 50, currency: "USD")
        )
        let records = [
            record(account: good, cost: 20, currency: "USD"),
            record(account: partial, cost: 40, currency: "USD")
        ]
        let remaining = DashboardMetrics.budgetRemaining(
            accounts: [good, partial],
            records: records,
            range: range
        )
        XCTAssertEqual(remaining, ["USD": 80])
    }
}
