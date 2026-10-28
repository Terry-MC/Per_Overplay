import XCTest
@testable import OverplayCore

final class AlertEngineTests: XCTestCase {
    private var store: OverplayStore!
    private var engine: AlertEngine!
    private let accountId = "acct-1"
    private let now = TestClock.date(2026, 10, 28, 12)

    override func setUpWithError() throws {
        store = try OverplayStore.inMemory()
        engine = AlertEngine(store: store)
    }

    private func snapshot(
        provider: ProviderKind = .openrouter,
        budget: Budget? = nil,
        monthSpend: Decimal? = nil,
        threshold: BalanceThreshold? = nil,
        balance: BalanceSnapshot? = nil,
        balanceIsFresh: Bool = true,
        failures: Int = 0,
        credentialInvalid: Bool = false,
        lastSuccess: Date? = nil,
        createdAt: Date? = nil,
        usageFresh: Bool = true,
        enabled: Bool = true,
        at date: Date? = nil
    ) -> AlertSnapshot {
        AlertSnapshot(
            accountId: accountId,
            accountName: "账户 A",
            provider: provider,
            enabled: enabled,
            budget: budget,
            monthSpend: monthSpend,
            balanceThreshold: threshold,
            latestBalance: balance,
            balanceIsFresh: balanceIsFresh,
            consecutiveFailures: failures,
            credentialInvalid: credentialInvalid,
            lastSuccessAt: lastSuccess ?? (date ?? now).addingTimeInterval(-60),
            lastAttemptAt: date ?? now,
            createdAt: createdAt ?? (date ?? now).addingTimeInterval(-86_400),
            refreshInterval: 15 * 60,
            usageIsFresh: usageFresh,
            now: date ?? now
        )
    }

    private func balance(_ total: Decimal, currency: String = "USD", asOf: Date? = nil) -> BalanceSnapshot {
        BalanceSnapshot(
            accountId: accountId, currency: currency, total: total,
            asOf: asOf ?? now, source: "test"
        )
    }

    func testBudgetWarningFiresOncePerMonthAndExceededSeparately() throws {
        var events = try engine.evaluate(snapshot(budget: Budget(amount: 100, currency: "USD"), monthSpend: 85))
        XCTAssertEqual(events.map(\.kind), [.budgetWarning])
        XCTAssertEqual(events.first?.threshold, "80%")
        XCTAssertEqual(events.first?.periodKey, "2026-10")

        events = try engine.evaluate(snapshot(budget: Budget(amount: 100, currency: "USD"), monthSpend: 85))
        XCTAssertTrue(events.isEmpty, "同一预算阈值在同一自然月只触发一次")

        events = try engine.evaluate(snapshot(budget: Budget(amount: 100, currency: "USD"), monthSpend: 105))
        XCTAssertEqual(events.map(\.kind), [.budgetExceeded])

        events = try engine.evaluate(snapshot(budget: Budget(amount: 100, currency: "USD"), monthSpend: 120))
        XCTAssertTrue(events.isEmpty)

        let nextMonth = TestClock.date(2026, 11, 5)
        events = try engine.evaluate(snapshot(budget: Budget(amount: 100, currency: "USD"), monthSpend: 120, at: nextMonth))
        XCTAssertEqual(Set(events.map(\.kind)), Set([.budgetWarning, .budgetExceeded]))
        XCTAssertEqual(events.first?.periodKey, "2026-11")
    }

    func testBudgetHysteresisChangesActiveStateButDoesNotRefire() throws {
        _ = try engine.evaluate(snapshot(budget: Budget(amount: 100, currency: "USD"), monthSpend: 85))
        let key = "budget:\(accountId):budgetWarning:2026-10"
        XCTAssertEqual(try store.alertState(key: key)?.active, true)

        _ = try engine.evaluate(snapshot(budget: Budget(amount: 100, currency: "USD"), monthSpend: 70))
        XCTAssertEqual(try store.alertState(key: key)?.active, false)
        XCTAssertNotNil(try store.alertState(key: key)?.lastFiredAt)

        let events = try engine.evaluate(snapshot(budget: Budget(amount: 100, currency: "USD"), monthSpend: 85))
        XCTAssertTrue(events.isEmpty, "回落后再次越线，在同一自然月不应重复触发")
    }

    func testBudgetSkippedWhenUsageStaleOrMissing() throws {
        XCTAssertTrue(try engine.evaluate(snapshot(budget: Budget(amount: 100, currency: "USD"), monthSpend: 99, usageFresh: false)).isEmpty)
        XCTAssertTrue(try engine.evaluate(snapshot(budget: Budget(amount: 100, currency: "USD"), monthSpend: nil)).isEmpty)
        XCTAssertTrue(try engine.evaluate(snapshot(provider: .deepseek, budget: Budget(amount: 100, currency: "USD"), monthSpend: 99)).isEmpty)
    }

    func testBalanceAlertRearmsOnlyAfterRecovery() throws {
        let threshold = BalanceThreshold(amount: 100, currency: "USD")
        var events = try engine.evaluate(snapshot(
            provider: .deepseek, budget: nil, threshold: threshold, balance: balance(90)
        ))
        XCTAssertEqual(events.map(\.kind), [.balanceLow])

        events = try engine.evaluate(snapshot(
            provider: .deepseek, budget: nil, threshold: threshold, balance: balance(95)
        ))
        XCTAssertTrue(events.isEmpty)

        events = try engine.evaluate(snapshot(
            provider: .deepseek, budget: nil, threshold: threshold, balance: balance(100)
        ))
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(
            try store.alertState(key: "balance:\(accountId):USD")?.active,
            false
        )

        events = try engine.evaluate(snapshot(
            provider: .deepseek, budget: nil, threshold: threshold, balance: balance(99)
        ))
        XCTAssertEqual(events.map(\.kind), [.balanceLow])
    }

    func testBalanceSkippedWhenDataIsStaleOrCurrencyMismatch() throws {
        let threshold = BalanceThreshold(amount: 100, currency: "USD")
        XCTAssertTrue(try engine.evaluate(snapshot(
            provider: .deepseek, budget: nil, threshold: threshold,
            balance: balance(10), balanceIsFresh: false
        )).isEmpty)
        XCTAssertTrue(try engine.evaluate(snapshot(
            provider: .deepseek, budget: nil, threshold: threshold,
            balance: balance(10, currency: "CNY")
        )).isEmpty)
    }

    func testSyncFailureCooldown() throws {
        var events = try engine.evaluate(snapshot(failures: 2))
        XCTAssertTrue(events.isEmpty)

        events = try engine.evaluate(snapshot(failures: 3))
        XCTAssertEqual(events.map(\.kind), [.syncFailed])

        events = try engine.evaluate(snapshot(failures: 4))
        XCTAssertTrue(events.isEmpty, "6 小时冷却期内不重复")

        let later = now.addingTimeInterval(6 * 60 * 60 + 1)
        events = try engine.evaluate(snapshot(failures: 5, at: later))
        XCTAssertEqual(events.map(\.kind), [.syncFailed])
    }

    func testCredentialInvalidFiresOnceAndRearmsAfterRecovery() throws {
        var events = try engine.evaluate(snapshot(credentialInvalid: true))
        XCTAssertEqual(events.map(\.kind), [.credentialInvalid])
        events = try engine.evaluate(snapshot(credentialInvalid: true))
        XCTAssertTrue(events.isEmpty)

        _ = try engine.evaluate(snapshot(credentialInvalid: false))
        events = try engine.evaluate(snapshot(credentialInvalid: true))
        XCTAssertEqual(events.map(\.kind), [.credentialInvalid])
    }

    func testDataStaleAlertFiresAndResetsAfterSuccess() throws {
        let staleSuccess = now.addingTimeInterval(-31 * 60)
        var events = try engine.evaluate(snapshot(lastSuccess: staleSuccess))
        XCTAssertEqual(events.map(\.kind), [.dataStale])
        events = try engine.evaluate(snapshot(lastSuccess: staleSuccess))
        XCTAssertTrue(events.isEmpty)

        events = try engine.evaluate(snapshot(lastSuccess: now))
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(try store.alertState(key: "stale:\(accountId)")?.active, false)

        let later = now.addingTimeInterval(31 * 60)
        events = try engine.evaluate(snapshot(lastSuccess: now, at: later))
        XCTAssertEqual(events.map(\.kind), [.dataStale])
    }

    func testNeverSyncedAccountAlertsAfterGracePeriod() throws {
        let createdLongAgo = now.addingTimeInterval(-31 * 60)
        let neverSynced = AlertSnapshot(
            accountId: accountId, accountName: "账户 A", provider: .openrouter, enabled: true,
            budget: nil, monthSpend: nil, balanceThreshold: nil, latestBalance: nil,
            balanceIsFresh: false, consecutiveFailures: 0, credentialInvalid: false,
            lastSuccessAt: nil, lastAttemptAt: nil, createdAt: createdLongAgo,
            refreshInterval: 15 * 60, usageIsFresh: false, now: now
        )
        let events = try engine.evaluate(neverSynced)
        XCTAssertEqual(events.map(\.kind), [.dataStale])
    }

    func testDisabledAccountProducesNoAlerts() throws {
        let events = try engine.evaluate(snapshot(
            threshold: BalanceThreshold(amount: 100, currency: "USD"),
            balance: balance(1),
            failures: 9,
            credentialInvalid: true,
            enabled: false
        ))
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(try store.alerts().isEmpty)
    }

    func testAlertEventsArePersisted() throws {
        _ = try engine.evaluate(snapshot(budget: Budget(amount: 100, currency: "USD"), monthSpend: 85))
        let alerts = try store.alerts()
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.kind, .budgetWarning)
        try store.acknowledgeAlert(id: alerts[0].id)
        XCTAssertEqual(try store.alerts().first?.acknowledged, true)
    }
}
