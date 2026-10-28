import XCTest
@testable import OverplayCore

final class SyncCancellationTests: XCTestCase {
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

    private func success() -> HTTPResponse {
        response(200, body: #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"10.00"}]}"#)
    }

    private func makeEngine(_ transport: HTTPTransport) -> SyncEngine {
        SyncEngine(
            store: store,
            credentials: keychain,
            transport: transport,
            settings: AppSettings(refreshIntervalMinutes: 5, notificationsEnabled: false)
        )
    }

    private func waitForRequest(_ transport: DelayedHTTPTransport, count: Int) async -> Bool {
        for _ in 0..<200 {
            if transport.requestCount >= count { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    func testManualRefreshIsTrackedAndSingleFlight() async throws {
        let transport = DelayedHTTPTransport(delayNanoseconds: 200_000_000, responses: [success()])
        let engine = makeEngine(transport)

        XCTAssertTrue(engine.startManualRefresh(account: account, now: now))
        let started = await waitForRequest(transport, count: 1)
        XCTAssertTrue(started)
        XCTAssertFalse(engine.startManualRefresh(account: account, now: now))

        for _ in 0..<200 {
            if !engine.isInFlight(accountId: account.id) { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(transport.requestCount, 1)
        XCTAssertEqual(try store.balanceSnapshots(accountId: account.id, currency: "CNY").count, 1)
    }

    func testAccountDeletionDuringManualRefreshDoesNotWrite() async throws {
        let transport = DelayedHTTPTransport(delayNanoseconds: 300_000_000, responses: [success()])
        let engine = makeEngine(transport)

        XCTAssertTrue(engine.startManualRefresh(account: account, now: now))
        _ = await waitForRequest(transport, count: 1)
        try store.deleteAccount(id: account.id, removeHistory: true)
        engine.cancel(accountId: account.id)

        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(try store.account(id: account.id))
        XCTAssertTrue(try store.usage(accountId: account.id).isEmpty)
        XCTAssertTrue(try store.latestBalances(accountId: account.id).isEmpty)
        XCTAssertTrue(try store.alerts().isEmpty)
    }

    func testCancelAllAndClearDuringManualRefreshLeavesNoRows() async throws {
        let transport = DelayedHTTPTransport(delayNanoseconds: 300_000_000, responses: [success()])
        let engine = makeEngine(transport)

        XCTAssertTrue(engine.startManualRefresh(account: account, now: now))
        _ = await waitForRequest(transport, count: 1)
        engine.cancelAll()

        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(try store.balanceSnapshots(accountId: account.id, currency: "CNY").isEmpty)
        XCTAssertNil(try store.account(id: account.id)?.lastSuccessAt)

        try store.clearAllData()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(try store.accounts().isEmpty)
        XCTAssertTrue(try store.usage().isEmpty)
        XCTAssertTrue(try store.alerts().isEmpty)
    }
}

private final class DelayedHTTPTransport: HTTPTransport {
    private let delayNanoseconds: UInt64
    private let queue = DispatchQueue(label: "overplay.tests.delayed-transport")
    private var responses: [HTTPResponse]
    private var count = 0

    init(delayNanoseconds: UInt64, responses: [HTTPResponse]) {
        self.delayNanoseconds = delayNanoseconds
        self.responses = responses
    }

    var requestCount: Int {
        queue.sync { count }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let next: HTTPResponse? = queue.sync {
            guard !responses.isEmpty else { return nil }
            count += 1
            return responses.removeFirst()
        }
        guard let next else {
            throw HTTPTransportError.other("测试响应已耗尽")
        }
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return next
    }

    func shutdown() {}
}
