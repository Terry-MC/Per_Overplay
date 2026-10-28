import XCTest
@testable import OverplayCore

final class FloatingSummaryTests: XCTestCase {
    private let now = TestClock.date(2026, 10, 28, 12)

    private func account(
        id: String,
        provider: ProviderKind,
        name: String,
        enabled: Bool = true,
        lastSuccessAt: Date? = Date(),
        lastError: String? = nil,
        budget: Budget? = nil
    ) -> Account {
        Account(
            id: id,
            provider: provider,
            name: name,
            enabled: enabled,
            lastSuccessAt: lastSuccessAt,
            credentialInvalid: false,
            lastError: lastError,
            budget: budget
        )
    }

    private func record(
        account: Account,
        day: String,
        cost: Decimal? = nil,
        currency: String? = nil,
        prompt: Int? = nil,
        completion: Int? = nil,
        requests: Int? = nil
    ) -> UsageRecord {
        UsageRecord(
            accountId: account.id,
            accountName: account.name,
            provider: account.provider,
            day: day,
            model: "test-model",
            promptTokens: prompt,
            completionTokens: completion,
            requests: requests,
            cost: cost,
            currency: currency,
            source: "test"
        )
    }

    func testSummaryMapsGlobalFieldsAndRows() {
        let deepSeek = account(id: "ds", provider: .deepseek, name: "DeepSeek")
        let kimi = account(
            id: "kimi", provider: .kimi, name: "Kimi 主账户",
            budget: Budget(amount: 400, currency: "CNY")
        )
        let openRouter = account(
            id: "or", provider: .openrouter, name: "OpenRouter",
            budget: Budget(amount: 100, currency: "USD")
        )
        let today = CalendarDay.string(for: now, timeZone: CalendarDay.utc)
        let yesterday = "2026-10-27"
        let usage = [
            record(account: kimi, day: today, cost: 10, currency: "CNY",
                   prompt: 100, completion: 50, requests: 5),
            record(account: openRouter, day: today, cost: 2, currency: "USD",
                   prompt: 20, completion: 10)
        ]
        let balances: [String: [String: BalanceSnapshot]] = [
            deepSeek.id: ["CNY": BalanceSnapshot(
                accountId: deepSeek.id, currency: "CNY", total: 100,
                asOf: now, source: "test"
            )]
        ]
        let quotas = [
            kimi.id: QuotaSnapshot(
                accountId: kimi.id, totalCredits: 500, totalUsage: 0,
                remaining: 500, currency: "CNY", asOf: now, source: "test"
            ),
            openRouter.id: QuotaSnapshot(
                accountId: openRouter.id, totalCredits: 60, totalUsage: 10,
                remaining: 50, currency: "USD", asOf: now, source: "test"
            )
        ]
        let alerts = [
            AlertEvent(
                id: "critical", accountId: kimi.id, accountName: kimi.name,
                kind: .budgetExceeded, firedAt: now,
                value: "100%", threshold: "100%", metric: "预算", periodKey: "2026-10"
            ),
            AlertEvent(
                id: "warning", accountId: openRouter.id, accountName: openRouter.name,
                kind: .budgetWarning, firedAt: now,
                value: "80%", threshold: "80%", metric: "预算", periodKey: "2026-10"
            )
        ]

        let summary = FloatingSummaryBuilder.make(
            accounts: [deepSeek, kimi, openRouter],
            usageRecords: usage,
            balances: balances,
            quotas: quotas,
            alerts: alerts,
            now: now
        )

        XCTAssertEqual(summary.todayStatus, .actual)
        XCTAssertEqual(summary.todayCosts, ["CNY": 10, "USD": 2])
        XCTAssertEqual(summary.creditsStatus, .actual)
        XCTAssertEqual(summary.creditsRemaining, ["CNY": 500, "USD": 50])
        XCTAssertEqual(summary.balancesStatus, .actual)
        XCTAssertEqual(summary.balances, ["CNY": 100])
        XCTAssertEqual(summary.tokenTotal, 180)
        XCTAssertEqual(summary.tokenAccounts, 2)
        XCTAssertEqual(summary.totalAccounts, 3)
        XCTAssertEqual(summary.requestCount, 5)
        XCTAssertTrue(summary.requestsAvailable)
        XCTAssertEqual(summary.unacknowledgedAlertCount, 2)
        XCTAssertEqual(summary.criticalAlertCount, 1)
        XCTAssertEqual(summary.rows.count, 3)
        XCTAssertEqual(summary.rows[0].name, "DeepSeek")
        XCTAssertEqual(summary.rows[1].name, "Kimi 主账户")
        XCTAssertEqual(summary.rows[1].primaryLines.count, 1)
        XCTAssertEqual(summary.rows[1].primaryLines[0].currency, "CNY")
        XCTAssertEqual(summary.rows[1].secondaryLines.count, 1)
        XCTAssertEqual(summary.rows[1].budgetRatio, 2.5)
        XCTAssertEqual(summary.rows[1].unacknowledgedAlerts, 1)
        XCTAssertEqual(summary.rows[1].criticalAlerts, 1)
        XCTAssertEqual(summary.rows[2].primaryLines[0].currency, "USD")
        XCTAssertEqual(summary.rows[2].unacknowledgedAlerts, 1)
        XCTAssertEqual(summary.rows[2].criticalAlerts, 0)
        XCTAssertNotNil(summary.lastSyncAt)
        XCTAssertFalse(summary.rows.contains { $0.primaryStatus.isActual == false })
    }

    func testMissingTodayAndTokenDataDoNotBecomeZero() {
        let kimi = account(id: "kimi", provider: .kimi, name: "Kimi")
        let balances: [String: [String: BalanceSnapshot]] = [
            kimi.id: ["CNY": BalanceSnapshot(
                accountId: kimi.id, currency: "CNY", total: 0,
                asOf: now, source: "test"
            )]
        ]
        let summary = FloatingSummaryBuilder.make(
            accounts: [kimi],
            usageRecords: [],
            balances: balances,
            quotas: [kimi.id: QuotaSnapshot(
                accountId: kimi.id, totalCredits: 10, totalUsage: 10,
                remaining: 0, currency: "CNY", asOf: now, source: "test"
            )],
            alerts: [],
            now: now
        )
        XCTAssertTrue(summary.todayStatus.isMissing)
        XCTAssertTrue(summary.todayCosts.isEmpty)
        XCTAssertTrue(summary.tokenStatus.isMissing)
        XCTAssertTrue(summary.rows[0].primaryStatus.isActual)
        XCTAssertEqual(summary.rows[0].primaryLines.count, 1)
        XCTAssertEqual(summary.rows[0].primaryLines[0].value, 0)
        XCTAssertTrue(summary.creditsStatus.isActual)
        XCTAssertEqual(summary.creditsRemaining, ["CNY": 0])
        XCTAssertTrue(summary.requestsAvailable == false)
        XCTAssertEqual(summary.requestCount, 0)
    }

    func testDisabledAndPartialAccountsShowEmptyState() {
        let disabled = account(
            id: "disabled", provider: .glm, name: "Disabled", enabled: false
        )
        let partial = account(
            id: "partial", provider: .kimi, name: "Partial",
            lastError: "timeout",
            budget: Budget(amount: 100, currency: "CNY")
        )
        let summary = FloatingSummaryBuilder.make(
            accounts: [disabled, partial],
            usageRecords: [],
            balances: [:],
            quotas: [
                partial.id: QuotaSnapshot(
                    accountId: partial.id, totalCredits: 10, totalUsage: 5,
                    remaining: 5, currency: "CNY", asOf: now, source: "test"
                )
            ],
            alerts: [],
            now: now
        )
        XCTAssertEqual(summary.rows[0].primaryStatus, .unavailable("该账户已禁用"))
        XCTAssertTrue(summary.rows[1].primaryStatus.isPartial)
        XCTAssertTrue(summary.rows[1].primaryLines.isEmpty)
        XCTAssertEqual(summary.rows[1].secondaryStatus, .partial("同步失败：timeout"))
        XCTAssertTrue(summary.creditsRemaining.isEmpty)
        XCTAssertTrue(summary.creditsStatus.isPartial)
    }
}
