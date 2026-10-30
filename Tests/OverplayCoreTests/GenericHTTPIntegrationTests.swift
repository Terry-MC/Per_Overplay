import XCTest
@testable import OverplayCore

final class GenericHTTPIntegrationTests: XCTestCase {
    private let now = TestClock.date(2026, 10, 28, 12)

    private func account() -> Account {
        Account(
            provider: .genericHTTP,
            name: "Generic",
            lastSuccessAt: now.addingTimeInterval(-60),
            budget: Budget(amount: 100, currency: "USD"),
            genericConfig: GenericHTTPConfig(
                baseURL: "https://api.example.com",
                mapping: GenericFieldMapping(
                    balanceTotal: "balance.total",
                    balanceCurrency: "balance.currency",
                    creditsTotal: "credits.total",
                    creditsUsed: "credits.used",
                    creditsCurrency: "credits.currency",
                    usageDay: "day",
                    promptTokens: "prompt",
                    requests: "requests",
                    cost: "cost",
                    usageCurrency: "currency"
                )
            )
        )
    }

    func testGenericAccountCapabilitiesFlowThroughStatusesAggregatesAndBudget() throws {
        let account = account()
        let balance = BalanceSnapshot(
            accountId: account.id,
            currency: "USD",
            total: 50,
            asOf: now,
            source: "test"
        )
        let quota = QuotaSnapshot(
            accountId: account.id,
            totalCredits: 100,
            totalUsage: 20,
            remaining: 80,
            currency: "USD",
            asOf: now,
            source: "test"
        )
        let record = UsageRecord(
            accountId: account.id,
            accountName: account.displayName,
            provider: .genericHTTP,
            day: "2026-10-28",
            model: "generic-http",
            promptTokens: 100,
            requests: 2,
            cost: 5,
            currency: "USD",
            source: "test",
            updatedAt: now
        )

        XCTAssertEqual(AccountDataStatus.balance(account: account, balances: [balance]), .actual)
        XCTAssertEqual(AccountDataStatus.quota(account: account, quota: quota), .actual)
        XCTAssertEqual(AccountDataStatus.usage(account: account, records: [record]), .actual)

        XCTAssertEqual(
            DashboardMetrics.creditsRemaining(accounts: [account], quotas: [account.id: quota]),
            ["USD": 80]
        )
        XCTAssertEqual(
            DashboardMetrics.balanceTotal(
                accounts: [account],
                balances: [account.id: ["USD": balance]],
                currency: "USD"
            ),
            50
        )

        let month = CalendarDay.monthRange(now: now)
        XCTAssertEqual(
            BudgetMath.availableSpend(
                account: account,
                records: [record],
                range: month.range
            ),
            5
        )

        let summary = FloatingSummaryBuilder.make(
            accounts: [account],
            usageRecords: [record],
            balances: [account.id: ["USD": balance]],
            quotas: [account.id: quota],
            alerts: [],
            now: now
        )
        XCTAssertEqual(summary.rows.count, 1)
        XCTAssertEqual(summary.rows.first?.primaryStatus, .actual)
        XCTAssertEqual(summary.rows.first?.primaryLines.first?.value, 50)
    }

    func testGenericBudgetPercentAlertLineUsesAccountCapabilities() throws {
        let store = try OverplayStore.inMemory()
        let engine = AlertEngine(store: store)
        let account = account()
        let config = AccountAlertConfig(
            warning: AlertLineRule(mode: .custom, metric: .budgetPercent, value: 1),
            critical: .off
        )
        let snapshot = AlertSnapshot(
            accountId: account.id,
            accountName: account.displayName,
            provider: .genericHTTP,
            enabled: true,
            budget: account.budget,
            monthSpend: 5,
            balanceThreshold: nil,
            latestBalance: nil,
            balanceIsFresh: false,
            consecutiveFailures: 0,
            credentialInvalid: false,
            lastSuccessAt: now.addingTimeInterval(-60),
            lastAttemptAt: now,
            createdAt: now.addingTimeInterval(-86_400),
            refreshInterval: 15 * 60,
            usageIsFresh: true,
            now: now,
            alertConfig: config,
            capabilities: account.capabilities
        )
        let events = try engine.evaluate(snapshot)
        XCTAssertEqual(events.map(\.kind), [.lineWarning])
    }
}
