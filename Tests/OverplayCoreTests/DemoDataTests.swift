import XCTest
@testable import OverplayCore

final class DemoDataTests: XCTestCase {
    func testDemoStoreIsIsolatedAndLabeled() throws {
        let now = TestClock.date(2026, 10, 28, 12)
        let store = try DemoData.makeStore(now: now)
        XCTAssertTrue(store.isInMemory)
        let accounts = try store.accounts()
        XCTAssertEqual(accounts.count, 16)
        XCTAssertTrue(accounts.allSatisfy(\.isDemo))
        let deepSeekAccounts = accounts.filter { $0.provider == .deepseek }
        XCTAssertEqual(deepSeekAccounts.count, 2)
        var demoCurrencies = Set<String>()
        for account in deepSeekAccounts {
            let balances = try store.latestBalances(accountId: account.id)
            XCTAssertEqual(balances.count, 1, "每个 DeepSeek 演示账户只应有一个币种")
            if let currency = balances.keys.first {
                demoCurrencies.insert(currency)
                XCTAssertEqual(account.balanceThreshold?.currency, currency,
                               "演示阈值必须跟随所在账户的币种")
            }
        }
        XCTAssertEqual(demoCurrencies, Set(["CNY", "USD"]))
        XCTAssertTrue(accounts.contains { $0.provider == .openrouter })
        let usage = try store.usage()

        let demoOnlyProviders: [ProviderKind] = [
            .kimi, .glm, .minimax, .qwen, .seed, .hunyuan,
            .openai, .anthropic, .gemini, .meta, .xai, .mistral
        ]
        XCTAssertEqual(Set(accounts.map(\.provider)).intersection(demoOnlyProviders),
                       Set(demoOnlyProviders), "每个演示平台都应至少有一个虚拟账户")
        XCTAssertEqual(accounts.filter { $0.provider == .kimi }.count, 2,
                       "Kimi 需要两个账户以演示同平台账户切换")
        for provider in demoOnlyProviders {
            XCTAssertFalse(provider.supportsRealConnection,
                           "\(provider.displayName) 仅提供演示数据，不应当被当作真实连接器")
            let account = try XCTUnwrap(accounts.first { $0.provider == provider })
            let quota = try store.latestQuota(accountId: account.id)
            let snapshot = try XCTUnwrap(quota)
            XCTAssertEqual(snapshot.currency, provider.defaultCurrency)
            XCTAssertTrue(usage.contains { $0.provider == provider && $0.accountId == account.id },
                          "\(provider.displayName) 应有虚拟用量记录")
        }

        XCTAssertFalse(usage.isEmpty)
        XCTAssertTrue(usage.allSatisfy { $0.source.contains("演示") })
        let utcToday = CalendarDay.string(
            for: now, timeZone: CalendarDay.utc, calendar: TestClock.calendar
        )
        XCTAssertFalse(usage.contains { $0.day == utcToday },
                       "演示数据应模拟 OpenRouter 的真实窗口：不含今天")
        XCTAssertTrue(usage.compactMap(\.cost).reduce(Decimal(0), +) > 0)

        let alerts = try store.alerts()
        XCTAssertFalse(alerts.isEmpty)
        XCTAssertTrue(alerts.allSatisfy(\.isDemo))
        XCTAssertTrue(alerts.contains { $0.kind == .balanceLow })

        let openRouter = try XCTUnwrap(accounts.first { $0.provider == .openrouter })
        let monthSpend = try store.monthSpend(
            accountId: openRouter.id,
            currency: "USD",
            now: now
        )
        let ratio = Money.percent(monthSpend / (openRouter.budget?.amount ?? 1) * 100)
        let budgetAlerts = alerts.filter {
            $0.kind == .budgetWarning || $0.kind == .budgetExceeded
        }
        XCTAssertFalse(budgetAlerts.isEmpty)
        XCTAssertTrue(budgetAlerts.allSatisfy { $0.value == ratio },
                      "demo 告警百分比必须与同一预算计算口径一致")

        let quota = try store.latestQuota(accountId: "demo-openrouter")
        XCTAssertNotNil(quota)
        let cnyBalances = try store.latestBalances(accountId: "demo-deepseek")
        XCTAssertNotNil(cnyBalances["CNY"])
        let usdBalances = try store.latestBalances(accountId: "demo-deepseek-usd")
        XCTAssertNotNil(usdBalances["USD"])
    }

    func testDemoDisclaimerIsComplete() {
        XCTAssertTrue(DemoMode.disclaimer.contains("模拟数据"))
        XCTAssertTrue(DemoMode.disclaimer.contains("不会连接任何厂商接口"))
        XCTAssertTrue(DemoMode.shortBadge.contains("演示数据"))
    }
}
