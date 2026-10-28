import XCTest
@testable import OverplayCore

final class SyncSchedulingTests: XCTestCase {
    private let t0 = TestClock.date(2026, 10, 28, 12)
    private var store: OverplayStore!
    private var keychain: InMemoryCredentialStore!
    private var settings: AppSettings!

    override func setUpWithError() throws {
        store = try OverplayStore.inMemory()
        keychain = InMemoryCredentialStore()
        settings = AppSettings(refreshIntervalMinutes: 5, notificationsEnabled: false)
    }

    private func makeAccount(name: String = "DS") throws -> Account {
        let account = try store.insertTestAccount(provider: .deepseek, name: name)
        try keychain.setCredential("sk-test", accountId: account.id)
        return account
    }

    private func makeEngine(_ transport: HTTPTransport) -> SyncEngine {
        SyncEngine(store: store, credentials: keychain, transport: transport, settings: settings)
    }

    private func deepSeekSuccess(_ total: String = "10.00") -> HTTPResponse {
        response(200, body: #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"\#(total)"}]}"#)
    }

    private func waitForRequest(_ transport: FakeHTTPTransport, count: Int) async {
        for _ in 0..<200 {
            if transport.requestCount >= count { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func waitUntilIdle(_ engine: SyncEngine, accountId: String) async {
        for _ in 0..<200 {
            if !engine.isInFlight(accountId: accountId) { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("同步任务在预期时间内未结束")
    }

    private func trigger(
        _ engine: SyncEngine,
        account: Account,
        transport: FakeHTTPTransport,
        at date: Date,
        expectedRequests: Int
    ) async {
        engine.refreshDue(accounts: [account], now: date)
        await waitForRequest(transport, count: expectedRequests)
        await waitUntilIdle(engine, accountId: account.id)
    }

    func testSuccessSchedulesNextRunAtConfiguredInterval() async throws {
        let account = try makeAccount()
        let transport = FakeHTTPTransport([deepSeekSuccess(), deepSeekSuccess("11.00")])
        let engine = makeEngine(transport)
        engine.bootstrap(accounts: [account], now: t0)

        await trigger(engine, account: account, transport: transport, at: t0, expectedRequests: 1)
        XCTAssertEqual(transport.requestCount, 1)

        let interval = settings.refreshInterval
        engine.refreshDue(accounts: [account], now: t0.addingTimeInterval(interval - 1))
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(transport.requestCount, 1, "成功同步后应等待配置的 5 分钟周期")

        await trigger(
            engine, account: account, transport: transport,
            at: t0.addingTimeInterval(interval + 1), expectedRequests: 2
        )
        XCTAssertEqual(transport.requestCount, 2)
    }

    func testFailureUsesExponentialBackoff() async throws {
        let account = try makeAccount()
        let transport = FakeHTTPTransport([response(500), response(500), deepSeekSuccess()])
        let engine = makeEngine(transport)
        engine.bootstrap(accounts: [account], now: t0)

        await trigger(engine, account: account, transport: transport, at: t0, expectedRequests: 1)

        // 第一次失败：60 秒退避
        engine.refreshDue(accounts: [account], now: t0.addingTimeInterval(59))
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(transport.requestCount, 1)

        await trigger(
            engine, account: account, transport: transport,
            at: t0.addingTimeInterval(61), expectedRequests: 2
        )

        // 第二次失败：120 秒退避
        engine.refreshDue(accounts: [account], now: t0.addingTimeInterval(61 + 119))
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(transport.requestCount, 2)

        await trigger(
            engine, account: account, transport: transport,
            at: t0.addingTimeInterval(61 + 121), expectedRequests: 3
        )
        XCTAssertEqual(try store.account(id: account.id)?.lastSuccessAt, t0.addingTimeInterval(61 + 121))
    }

    func testRateLimitHonorsRetryAfter() async throws {
        let account = try makeAccount()
        let transport = FakeHTTPTransport([
            response(429, headers: ["Retry-After": "120"]),
            deepSeekSuccess()
        ])
        let engine = makeEngine(transport)
        engine.bootstrap(accounts: [account], now: t0)

        await trigger(engine, account: account, transport: transport, at: t0, expectedRequests: 1)

        engine.refreshDue(accounts: [account], now: t0.addingTimeInterval(119))
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(transport.requestCount, 1, "应尊重 120 秒 Retry-After")

        await trigger(
            engine, account: account, transport: transport,
            at: t0.addingTimeInterval(121), expectedRequests: 2
        )
        XCTAssertEqual(transport.requestCount, 2)
    }

    func testInvalidCredentialPausesAutomaticRetry() async throws {
        let account = try makeAccount()
        let transport = FakeHTTPTransport([response(401), deepSeekSuccess()])
        let engine = makeEngine(transport)
        engine.bootstrap(accounts: [account], now: t0)

        await trigger(engine, account: account, transport: transport, at: t0, expectedRequests: 1)
        XCTAssertEqual(try store.account(id: account.id)?.credentialInvalid, true)

        engine.refreshDue(accounts: [account], now: t0.addingTimeInterval(86_400))
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(transport.requestCount, 1, "凭据失效后应暂停自动重试，直到用户重新输入 Key")
    }

    func testBootstrapStaggersAccounts() async throws {
        let first = try makeAccount(name: "First")
        let second = try makeAccount(name: "Second")
        let transport = FakeHTTPTransport([deepSeekSuccess(), deepSeekSuccess("12.00")])
        let engine = makeEngine(transport)
        engine.bootstrap(accounts: [first, second], now: t0)

        await trigger(engine, account: first, transport: transport, at: t0, expectedRequests: 1)
        XCTAssertEqual(transport.requestCount, 1)

        engine.refreshDue(accounts: [first, second], now: t0.addingTimeInterval(3))
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(transport.requestCount, 1, "第二个账户应错峰到 4 秒后")

        engine.refreshDue(accounts: [first, second], now: t0.addingTimeInterval(5))
        await waitForRequest(transport, count: 2)
        await waitUntilIdle(engine, accountId: second.id)
        XCTAssertEqual(transport.requestCount, 2)
    }
    func testActivityRetryAfterDelaysPartialResult() async throws {
        let account = try store.insertTestAccount(provider: .openrouter, name: "OR")
        try keychain.setCredential("mgmt", accountId: account.id)
        let credits = response(200, body: #"{"data":{"total_credits":10,"total_usage":1}}"#)
        let activityLimited = response(429, headers: ["Retry-After": "90"])
        let activityOK = response(200, body: #"{"data":[]}"#)
        let transport = FakeHTTPTransport([credits, activityLimited, credits, activityOK])
        let engine = makeEngine(transport)
        engine.bootstrap(accounts: [account], now: t0)

        engine.refreshDue(accounts: [account], now: t0)
        await waitForRequest(transport, count: 2)
        await waitUntilIdle(engine, accountId: account.id)
        let partial = try XCTUnwrap(try store.account(id: account.id))
        XCTAssertNotNil(partial.lastError)
        XCTAssertEqual(partial.lastSuccessAt, t0)

        engine.refreshDue(accounts: [partial], now: t0.addingTimeInterval(89))
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(transport.requestCount, 2, "activity 429 的 Retry-After 应推迟部分成功后的重试")

        engine.refreshDue(accounts: [partial], now: t0.addingTimeInterval(91))
        await waitForRequest(transport, count: 4)
        await waitUntilIdle(engine, accountId: account.id)
        XCTAssertEqual(transport.requestCount, 4)
        XCTAssertNil(try store.account(id: account.id)?.lastError)
    }

}
