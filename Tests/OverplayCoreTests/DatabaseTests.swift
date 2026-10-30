import XCTest
@testable import OverplayCore

final class DatabaseTests: XCTestCase {
    private var store: OverplayStore!

    override func setUpWithError() throws {
        store = try OverplayStore.inMemory()
    }

    func testAccountRoundTripWithBudgetAndThreshold() throws {
        let account = try store.insertTestAccount(
            provider: .openrouter,
            name: "主账户",
            budget: Budget(amount: 100, currency: "USD"),
            threshold: BalanceThreshold(amount: 20, currency: "USD")
        )
        XCTAssertEqual(account.name, "主账户")
        XCTAssertEqual(account.budget?.amount, 100)
        XCTAssertEqual(account.balanceThreshold?.amount, 20)

        try store.renameAccount(id: account.id, name: "改名")
        try store.setBudget(accountId: account.id, budget: Budget(amount: 200, currency: "USD"))
        let updated = try store.account(id: account.id)
        XCTAssertEqual(updated?.name, "改名")
        XCTAssertEqual(updated?.budget?.amount, 200)
    }

    func testUsageUpsertIsIdempotent() throws {
        let account = try store.insertTestAccount(provider: .openrouter)
        let now = TestClock.date()
        let record = UsageRecord(
            accountId: account.id,
            accountName: account.displayName,
            provider: .openrouter,
            day: "2026-10-27",
            model: "openai/gpt-5.2",
            providerName: "OpenAI",
            promptTokens: 100,
            completionTokens: 50,
            reasoningTokens: 10,
            requests: 3,
            cost: Decimal(string: "1.25")!,
            currency: "USD",
            source: "test",
            updatedAt: now
        )
        try store.upsertUsage([record], accountName: account.displayName)
        try store.upsertUsage([record], accountName: account.displayName)
        var rows = try store.usage(accountId: account.id)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.cost, Decimal(string: "1.25"))

        var updated = record
        updated.cost = Decimal(string: "1.50")!
        updated.promptTokens = 120
        try store.upsertUsage([updated], accountName: account.displayName)
        rows = try store.usage(accountId: account.id)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.cost, Decimal(string: "1.50"))
        XCTAssertEqual(rows.first?.promptTokens, 120)
    }

    func testDifferentModelsAndProvidersAreSeparateRows() throws {
        let account = try store.insertTestAccount(provider: .openrouter)
        let now = TestClock.date()
        let base = UsageRecord(
            accountId: account.id, accountName: account.displayName, provider: .openrouter,
            day: "2026-10-27", model: "m1", providerName: "P1", source: "test", updatedAt: now
        )
        var second = base
        second.model = "m2"
        var third = base
        third.providerName = "P2"
        try store.upsertUsage([base, second, third], accountName: account.displayName)
        XCTAssertEqual(try store.usage(accountId: account.id).count, 3)
    }

    func testUsageFiltersByRange() throws {
        let account = try store.insertTestAccount(provider: .openrouter)
        let now = TestClock.date()
        let records = ["2026-09-01", "2026-10-01", "2026-10-28"].enumerated().map { index, day in
            UsageRecord(
                accountId: account.id, accountName: account.displayName, provider: .openrouter,
                day: day, model: "m\(index)", cost: 1, currency: "USD", source: "test", updatedAt: now
            )
        }
        try store.upsertUsage(records, accountName: account.displayName)
        let range = DayRange(startDay: "2026-10-01", endDay: "2026-10-28")
        XCTAssertEqual(try store.usage(accountId: account.id, range: range).count, 2)
    }

    func testMonthSpendUsesOnlyMatchingCurrency() throws {
        let account = try store.insertTestAccount(provider: .openrouter)
        let now = TestClock.date(2026, 10, 28)
        let records = [
            UsageRecord(
                accountId: account.id, accountName: account.displayName, provider: .openrouter,
                day: "2026-10-10", model: "a", cost: 10, currency: "USD", source: "test", updatedAt: now
            ),
            UsageRecord(
                accountId: account.id, accountName: account.displayName, provider: .openrouter,
                day: "2026-10-11", model: "b", cost: 5, currency: "USD", source: "test", updatedAt: now
            ),
            UsageRecord(
                accountId: account.id, accountName: account.displayName, provider: .openrouter,
                day: "2026-10-12", model: "c", cost: 7, currency: "CNY", source: "test", updatedAt: now
            ),
            UsageRecord(
                accountId: account.id, accountName: account.displayName, provider: .openrouter,
                day: "2026-09-30", model: "d", cost: 99, currency: "USD", source: "test", updatedAt: now
            )
        ]
        try store.upsertUsage(records, accountName: account.displayName)
        XCTAssertEqual(try store.monthSpend(accountId: account.id, currency: "USD", now: now), 15)
        XCTAssertEqual(try store.monthSpend(accountId: account.id, currency: "CNY", now: now), 7)
    }

    func testDeleteAccountRetainsOrRemovesHistory() throws {
        let account = try store.insertTestAccount(provider: .openrouter)
        let now = TestClock.date()
        try store.upsertUsage([
            UsageRecord(
                accountId: account.id, accountName: account.displayName, provider: .openrouter,
                day: "2026-10-27", model: "m", cost: 1, currency: "USD", source: "test", updatedAt: now
            )
        ], accountName: account.displayName)
        try store.deleteAccount(id: account.id, removeHistory: false)
        XCTAssertNil(try store.account(id: account.id))
        XCTAssertEqual(try store.accounts().count, 0)
        XCTAssertEqual(try store.usage(accountId: account.id).count, 1)

        let second = try store.insertTestAccount(provider: .openrouter)
        try store.upsertUsage([
            UsageRecord(
                accountId: second.id, accountName: second.displayName, provider: .openrouter,
                day: "2026-10-27", model: "m", cost: 1, currency: "USD", source: "test", updatedAt: now
            )
        ], accountName: second.displayName)
        try store.deleteAccount(id: second.id, removeHistory: true)
        XCTAssertEqual(try store.usage(accountId: second.id).count, 0)
    }

    func testDeleteAccountDoesNotAffectOtherAccountDataOrCredentials() throws {
        let keychain = InMemoryCredentialStore()
        let now = TestClock.date()

        let retained = try store.insertTestAccount(
            provider: .deepseek,
            name: "Retained",
            threshold: BalanceThreshold(amount: 10, currency: "CNY")
        )
        let removed = try store.insertTestAccount(
            provider: .openrouter,
            name: "Removed",
            budget: Budget(amount: 100, currency: "USD")
        )
        try keychain.setCredential("retained-key", accountId: retained.id)
        try keychain.setCredential("removed-key", accountId: removed.id)
        try store.upsertUsage([
            UsageRecord(
                accountId: retained.id, accountName: retained.displayName, provider: .deepseek,
                day: "2026-10-27", model: "retained-model", promptTokens: 10,
                source: "test", updatedAt: now
            ),
            UsageRecord(
                accountId: removed.id, accountName: removed.displayName, provider: .openrouter,
                day: "2026-10-27", model: "removed-model", cost: 5, currency: "USD",
                source: "test", updatedAt: now
            )
        ], accountName: "seed")
        try store.insertBalanceSnapshots([
            BalanceSnapshot(
                accountId: retained.id, currency: "CNY", total: 42,
                asOf: now.addingTimeInterval(-60), source: "test"
            )
        ])
        try store.insertQuotaSnapshot(QuotaSnapshot(
            id: "quota-retained", accountId: retained.id, totalCredits: 100,
            totalUsage: 10, remaining: 90, currency: "CNY",
            asOf: now.addingTimeInterval(-60), source: "test"
        ))
        try store.insertQuotaSnapshot(QuotaSnapshot(
            id: "quota-removed", accountId: removed.id, totalCredits: 100,
            totalUsage: 10, remaining: 90, currency: "USD",
            asOf: now.addingTimeInterval(-60), source: "test"
        ))

        try keychain.deleteCredential(accountId: removed.id)
        try store.deleteAccount(id: removed.id, removeHistory: false)

        XCTAssertNil(try store.account(id: removed.id))
        XCTAssertEqual(try store.usage(accountId: removed.id).count, 1, "默认保留被删账户历史")
        XCTAssertEqual(try store.usage(accountId: retained.id).count, 1)
        XCTAssertEqual(try store.latestQuota(accountId: retained.id)?.remaining, 90)
        XCTAssertEqual(
            try store.balanceSnapshots(accountId: retained.id, currency: "CNY").first?.total,
            42
        )
        XCTAssertEqual(try store.account(id: retained.id)?.balanceThreshold?.amount, 10)
        XCTAssertEqual(try keychain.credential(accountId: removed.id), nil)
        XCTAssertEqual(try keychain.credential(accountId: retained.id), "retained-key")

        let secondRetained = try store.insertTestAccount(provider: .deepseek, name: "Keep")
        let secondRemoved = try store.insertTestAccount(provider: .openrouter, name: "Drop")
        try keychain.setCredential("keep-key", accountId: secondRetained.id)
        try keychain.setCredential("drop-key", accountId: secondRemoved.id)
        try store.upsertUsage([
            UsageRecord(
                accountId: secondRetained.id, accountName: secondRetained.displayName,
                provider: .deepseek, day: "2026-10-27", model: "keep", source: "test", updatedAt: now
            ),
            UsageRecord(
                accountId: secondRemoved.id, accountName: secondRemoved.displayName,
                provider: .openrouter, day: "2026-10-27", model: "drop",
                cost: 1, currency: "USD", source: "test", updatedAt: now
            )
        ], accountName: "seed2")

        try keychain.deleteCredential(accountId: secondRemoved.id)
        try store.deleteAccount(id: secondRemoved.id, removeHistory: true)

        XCTAssertEqual(try store.usage(accountId: secondRemoved.id).count, 0)
        XCTAssertEqual(try store.usage(accountId: secondRetained.id).count, 1)
        XCTAssertNotNil(try store.account(id: secondRetained.id))
        XCTAssertEqual(try keychain.credential(accountId: secondRetained.id), "keep-key")
        XCTAssertNil(try keychain.credential(accountId: secondRemoved.id))
    }

    func testSnapshotsAndAlertStatePersistence() throws {
        let account = try store.insertTestAccount(provider: .deepseek)
        try store.insertBalanceSnapshots([
            BalanceSnapshot(
                accountId: account.id, currency: "CNY", total: 100, granted: 10, toppedUp: 90,
                isAvailable: true, asOf: TestClock.date(2026, 10, 27), source: "test"
            ),
            BalanceSnapshot(
                accountId: account.id, currency: "CNY", total: 90, granted: 10, toppedUp: 80,
                isAvailable: true, asOf: TestClock.date(2026, 10, 28), source: "test"
            )
        ])
        let latest = try store.latestBalances(accountId: account.id)
        XCTAssertEqual(latest["CNY"]?.total, 90)
        XCTAssertEqual(try store.balanceSnapshots(accountId: account.id, currency: "CNY").count, 2)

        try store.upsertAlertState(AlertState(key: "k", active: true, lastFiredAt: TestClock.date(), lastValue: "1"))
        try store.upsertAlertState(AlertState(key: "k", active: false, lastFiredAt: nil, lastValue: "2"))
        let state = try store.alertState(key: "k")
        XCTAssertEqual(state?.active, false)
        XCTAssertEqual(state?.lastValue, "2")
        XCTAssertNotNil(state?.lastFiredAt)
    }

    func testSettingsRoundTrip() throws {
        XCTAssertEqual(try store.settings().refreshIntervalMinutes, 15)
        try store.saveSettings(AppSettings(refreshIntervalMinutes: 30, notificationsEnabled: false))
        let settings = try store.settings()
        XCTAssertEqual(settings.refreshIntervalMinutes, 30)
        XCTAssertFalse(settings.notificationsEnabled)
    }

    func testClearAllData() throws {
        _ = try store.insertTestAccount(provider: .openrouter)
        try store.saveSettings(AppSettings(refreshIntervalMinutes: 30))
        try store.clearAllData()
        XCTAssertEqual(try store.accounts().count, 0)
        XCTAssertEqual(try store.settings().refreshIntervalMinutes, 15)
    }

}
