import XCTest
@testable import OverplayCore

final class DemoDataTests: XCTestCase {
    func testDemoStoreIsIsolatedAndLabeled() throws {
        let now = TestClock.date(2026, 10, 28, 12)
        let store = try DemoData.makeStore(now: now)
        XCTAssertTrue(store.isInMemory)
        let accounts = try store.accounts()
        XCTAssertEqual(accounts.count, 2)
        XCTAssertTrue(accounts.allSatisfy(\.isDemo))
        XCTAssertTrue(accounts.contains { $0.provider == .deepseek })
        XCTAssertTrue(accounts.contains { $0.provider == .openrouter })

        let usage = try store.usage()
        XCTAssertFalse(usage.isEmpty)
        XCTAssertTrue(usage.allSatisfy { $0.source.contains("演示") })
        XCTAssertTrue(usage.compactMap(\.cost).reduce(Decimal(0), +) > 0)

        let alerts = try store.alerts()
        XCTAssertFalse(alerts.isEmpty)
        XCTAssertTrue(alerts.allSatisfy(\.isDemo))
        XCTAssertTrue(alerts.contains { $0.kind == .balanceLow })

        let quota = try store.latestQuota(accountId: "demo-openrouter")
        XCTAssertNotNil(quota)
        let balances = try store.latestBalances(accountId: "demo-deepseek")
        XCTAssertNotNil(balances["CNY"])
    }

    func testDemoDisclaimerIsComplete() {
        XCTAssertTrue(DemoMode.disclaimer.contains("模拟数据"))
        XCTAssertTrue(DemoMode.disclaimer.contains("不会连接任何厂商接口"))
        XCTAssertTrue(DemoMode.shortBadge.contains("演示数据"))
    }
}
