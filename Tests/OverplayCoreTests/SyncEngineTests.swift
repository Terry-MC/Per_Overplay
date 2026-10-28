import XCTest
@testable import OverplayCore

final class SyncEngineTests: XCTestCase {
    private let now = TestClock.date(2026, 10, 28, 12)
    private var store: OverplayStore!
    private var keychain: InMemoryCredentialStore!
    private var account: Account!

    override func setUpWithError() throws {
        store = try OverplayStore.inMemory()
        keychain = InMemoryCredentialStore()
        account = try store.insertTestAccount(provider: .deepseek, name: "DS")
        try keychain.setCredential("sk-test", accountId: account.id)
    }

    private func makeEngine(_ transport: HTTPTransport) -> SyncEngine {
        SyncEngine(
            store: store,
            credentials: keychain,
            transport: transport,
            settings: AppSettings()
        )
    }

    func testSuccessfulSyncPersistsDataAndState() async throws {
        let engine = makeEngine(FakeHTTPTransport([
            response(200, body: #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"88.50"}]}"#)
        ]))
        let outcome = await engine.refresh(account: account, now: now)
        XCTAssertEqual(outcome?.status, .success)
        let snapshots = try store.balanceSnapshots(accountId: account.id, currency: "CNY")
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.total, Decimal(string: "88.50"))
        let updated = try store.account(id: account.id)
        XCTAssertEqual(updated?.lastSuccessAt, now)
        XCTAssertEqual(updated?.consecutiveFailures, 0)
        XCTAssertNil(updated?.lastError)
        XCTAssertFalse(updated?.credentialInvalid ?? true)
    }

    func testRepeatedSyncIsIdempotentForBalanceSnapshots() async throws {
        let engine = makeEngine(FakeHTTPTransport([
            response(200, body: #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"88.50"}]}"#),
            response(200, body: #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"88.50"}]}"#)
        ]))
        _ = await engine.refresh(account: account, now: now)
        _ = await engine.refresh(account: account, now: now)
        XCTAssertEqual(try store.balanceSnapshots(accountId: account.id, currency: "CNY").count, 1)
    }

    func testConsecutiveFailuresRaisesAlertAtThree() async throws {
        let engine = makeEngine(FakeHTTPTransport([
            response(500), response(500), response(500)
        ]))
        for index in 0..<3 {
            let date = now.addingTimeInterval(Double(index) * 10)
            _ = await engine.refresh(account: try store.account(id: account.id)!, now: date)
        }
        let updated = try store.account(id: account.id)
        XCTAssertEqual(updated?.consecutiveFailures, 3)
        let alerts = try store.alerts()
        XCTAssertTrue(alerts.contains(where: { $0.kind == .syncFailed }))
    }

    func testInvalidCredentialMarksAccountAndAlerts() async throws {
        let engine = makeEngine(FakeHTTPTransport([response(401)]))
        let outcome = await engine.refresh(account: account, now: now)
        XCTAssertEqual(outcome?.status, .invalidCredential)
        let updated = try store.account(id: account.id)
        XCTAssertEqual(updated?.credentialInvalid, true)
        XCTAssertEqual(updated?.consecutiveFailures, 1)
        let alerts = try store.alerts()
        XCTAssertTrue(alerts.contains(where: { $0.kind == .credentialInvalid }))
        XCTAssertFalse(updated?.lastError?.contains("sk-test") ?? true)
    }

    func testMissingCredentialFailsWithoutNetwork() async throws {
        try keychain.deleteCredential(accountId: account.id)
        let transport = FakeHTTPTransport()
        let engine = makeEngine(transport)
        let outcome = await engine.refresh(account: account, now: now)
        XCTAssertEqual(outcome?.status, .failed)
        XCTAssertTrue(outcome?.error?.contains("Keychain") ?? false)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testOpenRouterPartialPersistsQuotaButSkipsBudgetAlerts() async throws {
        try store.deleteAccount(id: account.id, removeHistory: true)
        let openRouter = try store.insertTestAccount(
            provider: .openrouter,
            name: "OR",
            budget: Budget(amount: 10, currency: "USD")
        )
        try keychain.setCredential("mgmt", accountId: openRouter.id)
        try store.upsertUsage([
            UsageRecord(
                accountId: openRouter.id, accountName: openRouter.displayName,
                provider: .openrouter, day: "2026-10-27", model: "m", cost: 9,
                currency: "USD", source: "test", updatedAt: now
            )
        ], accountName: openRouter.displayName)
        let engine = makeEngine(FakeHTTPTransport([
            response(200, body: #"{"data":{"total_credits":10,"total_usage":9.5}}"#),
            response(500, body: "activity down")
        ]))
        let outcome = await engine.refresh(account: openRouter, now: now)
        XCTAssertEqual(outcome?.status, .partial)
        XCTAssertNotNil(try store.latestQuota(accountId: openRouter.id))
        let updated = try store.account(id: openRouter.id)
        XCTAssertEqual(updated?.lastSuccessAt, now)
        XCTAssertNotNil(updated?.lastError)
        XCTAssertFalse(try store.alerts().contains(where: { $0.kind == .budgetWarning }))
        XCTAssertFalse(try store.alerts().contains(where: { $0.kind == .budgetExceeded }))

        _ = engine.evaluatePeriodicAlerts(
            accounts: [try XCTUnwrap(updated)],
            settings: AppSettings(),
            now: now.addingTimeInterval(60)
        )
        XCTAssertFalse(
            try store.alerts().contains(where: {
                $0.kind == .budgetWarning || $0.kind == .budgetExceeded
            }),
            "部分成功且 activity 失败时，预算数据不完整，不应触发阈值告警"
        )
    }

    func testOpenRouterUsageUpsertIsIdempotentAcrossSyncs() async throws {
        try store.deleteAccount(id: account.id, removeHistory: true)
        let openRouter = try store.insertTestAccount(provider: .openrouter, name: "OR")
        try keychain.setCredential("mgmt", accountId: openRouter.id)
        let credits = response(200, body: #"{"data":{"total_credits":10,"total_usage":1}}"#)
        let activity = response(200, body: """
        {"data":[
          {"date":"2026-10-27","model":"m","provider_name":"P","usage":0.20,
           "requests":1,"prompt_tokens":10,"completion_tokens":5}
        ]}
        """)
        let engine = makeEngine(FakeHTTPTransport([
            credits, activity, credits, activity
        ]))
        _ = await engine.refresh(account: openRouter, now: now)
        _ = await engine.refresh(account: openRouter, now: now.addingTimeInterval(60))
        let records = try store.usage(accountId: openRouter.id)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.cost, Decimal(string: "0.20"))
    }

    func testSingleFlightPerAccount() async throws {
        final class SlowTransport: HTTPTransport {
            func send(_ request: HTTPRequest) async throws -> HTTPResponse {
                try? await Task.sleep(nanoseconds: 300_000_000)
                return response(200, body: #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"1.00"}]}"#)
            }
            func shutdown() {}
        }
        let engine = makeEngine(SlowTransport())
        let task = Task { await engine.refresh(account: account, now: now) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let second = await engine.refresh(account: account, now: now)
        XCTAssertNil(second, "同一账户不应并发叠加同步")
        let first = await task.value
        XCTAssertEqual(first?.status, .success)
    }

    func testAIUnavailableErrorDoesNotLeakCredential() async throws {
        let secret = "sk-never-log-me"
        try keychain.setCredential(secret, accountId: account.id)
        let engine = makeEngine(FakeHTTPTransport([
            response(400, body: #"{"error":{"message":"bad sk-never-log-me"}}"#)
        ]))
        let outcome = await engine.refresh(account: account, now: now)
        XCTAssertFalse(outcome?.error?.contains(secret) ?? true)
        let updated = try store.account(id: account.id)
        XCTAssertFalse(updated?.lastError?.contains(secret) ?? true)
    }
}
