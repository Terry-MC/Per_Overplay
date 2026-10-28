import XCTest
@testable import OverplayCore

final class DataStatusTests: XCTestCase {
    private func account(
        id: String = "acct",
        provider: ProviderKind = .deepseek,
        enabled: Bool = true,
        lastSuccessAt: Date? = Date(),
        credentialInvalid: Bool = false,
        lastError: String? = nil,
        budget: Budget? = nil
    ) -> Account {
        Account(
            id: id,
            provider: provider,
            name: "测试账户",
            enabled: enabled,
            lastSuccessAt: lastSuccessAt,
            credentialInvalid: credentialInvalid,
            lastError: lastError,
            budget: budget
        )
    }

    private func balance(accountId: String = "acct", currency: String = "CNY", total: Decimal) -> BalanceSnapshot {
        BalanceSnapshot(
            accountId: accountId,
            currency: currency,
            total: total,
            asOf: Date(),
            source: "test"
        )
    }

    private func quota(accountId: String = "acct", currency: String = "USD", remaining: Decimal = 10) -> QuotaSnapshot {
        QuotaSnapshot(
            accountId: accountId,
            totalCredits: remaining + 5,
            totalUsage: 5,
            remaining: remaining,
            currency: currency,
            asOf: Date(),
            source: "test"
        )
    }

    private func usage(accountId: String, provider: ProviderKind, day: String = "2026-10-27") -> UsageRecord {
        UsageRecord(
            accountId: accountId,
            accountName: "测试账户",
            provider: provider,
            day: day,
            model: "test-model",
            cost: 0,
            currency: "USD",
            source: "test"
        )
    }

    func testActualZeroIsARealValueNotAnEmptyState() {
        XCTAssertEqual(DataStatus.actual.valueText("0"), "0")
        XCTAssertEqual(DataStatus.actual.valueText("¥0.00"), "¥0.00")

        let zeroBalance = AccountDataStatus.balance(
            account: account(),
            balances: [balance(total: 0)]
        )
        XCTAssertEqual(zeroBalance, .actual)
        XCTAssertEqual(zeroBalance.valueText("¥0.00"), "¥0.00")

        let zeroQuota = AccountDataStatus.quota(
            account: account(provider: .openrouter),
            quota: quota(remaining: 0)
        )
        XCTAssertEqual(zeroQuota, .actual)

        let zeroSpend = AccountDataStatus.budget(
            account: account(budget: Budget(amount: 100, currency: "CNY")),
            spend: 0
        )
        XCTAssertEqual(zeroSpend, .actual)
        XCTAssertEqual(zeroSpend.valueText("0"), "0")
    }

    func testMissingDataNeverDisplaysZero() {
        let statuses: [DataStatus] = [
            .missing("无记录"),
            .unavailable("不支持"),
            .partial("部分成功"),
            .failed("同步失败"),
            .anomaly("账户异常")
        ]
        for status in statuses {
            XCTAssertFalse(status.isActual)
            XCTAssertNotEqual(status.valueText("0"), "0", "缺失数据不得借用 0")
            XCTAssertEqual(status.valueText("0"), status.emptyLabel)
        }

        let missingBalance = AccountDataStatus.balance(
            account: account(lastSuccessAt: nil),
            balances: []
        )
        XCTAssertTrue(missingBalance.isMissing)
        XCTAssertEqual(missingBalance.valueText("0"), "无数据")

        let missingQuota = AccountDataStatus.quota(
            account: account(provider: .openrouter),
            quota: nil
        )
        XCTAssertTrue(missingQuota.isMissing)

        let missingUsage = AccountDataStatus.usage(
            account: account(provider: .openrouter),
            records: []
        )
        XCTAssertTrue(missingUsage.isMissing)
    }

    func testUnavailableForUnsupportedAndDisabledAccounts() {
        XCTAssertEqual(
            AccountDataStatus.balance(
                account: account(provider: .openrouter),
                balances: []
            ),
            .unavailable("OpenRouter 不提供官方余额")
        )
        XCTAssertEqual(
            AccountDataStatus.quota(
                account: account(provider: .deepseek),
                quota: nil
            ),
            .unavailable("DeepSeek 不提供官方额度")
        )
        XCTAssertEqual(
            AccountDataStatus.quota(
                account: account(provider: .openrouter, enabled: false),
                quota: quota()
            ),
            .unavailable("该账户已禁用")
        )
        XCTAssertEqual(
            AccountDataStatus.usage(
                account: account(provider: .deepseek),
                records: []
            ),
            .unavailable("DeepSeek 不提供历史用量")
        )
    }

    func testPartialSuccessAndFailureAreDistinct() {
        let partial = AccountDataStatus.balance(
            account: account(lastError: "网络超时"),
            balances: [balance(total: 5)]
        )
        XCTAssertTrue(partial.isPartial)
        XCTAssertEqual(partial.valueText("¥5.00"), "暂无完整数据")

        let failedWithoutData = AccountDataStatus.balance(
            account: account(lastError: "网络超时"),
            balances: []
        )
        XCTAssertTrue(failedWithoutData.isFailed)

        let invalidCredential = AccountDataStatus.quota(
            account: account(provider: .openrouter, credentialInvalid: true, lastError: "401"),
            quota: quota()
        )
        XCTAssertTrue(invalidCredential.isFailed)

        let partialBudget = AccountDataStatus.budget(
            account: account(budget: Budget(amount: 100, currency: "CNY")),
            spend: nil
        )
        XCTAssertTrue(partialBudget.isPartial)
        XCTAssertEqual(partialBudget.valueText("0%"), "暂无完整数据")
    }

    func testAccountAbnormalBalanceIsAnomaly() {
        let status = AccountDataStatus.balance(
            account: account(),
            balances: [
                BalanceSnapshot(
                    accountId: "acct",
                    currency: "CNY",
                    total: 10,
                    isAvailable: false,
                    asOf: Date(),
                    source: "test"
                )
            ]
        )
        XCTAssertTrue(status.isAnomaly)
    }

    func testUsageAggregateDistinguishesActualPartialMissingAndFailed() {
        let good = account(id: "good", provider: .openrouter)
        let bad = account(id: "bad", provider: .openrouter, credentialInvalid: true, lastError: "401")
        let missing = account(id: "missing", provider: .openrouter, lastSuccessAt: nil)
        let records = [usage(accountId: "good", provider: .openrouter)]

        XCTAssertEqual(
            AccountDataStatus.usage(accounts: [good], records: records, emptyReason: "none"),
            .actual
        )
        XCTAssertTrue(
            AccountDataStatus.usage(accounts: [good, bad], records: records, emptyReason: "none").isPartial
        )
        XCTAssertTrue(
            AccountDataStatus.usage(accounts: [bad], records: records, emptyReason: "none").isFailed
        )
        XCTAssertTrue(
            AccountDataStatus.usage(accounts: [missing], records: records, emptyReason: "none").isMissing
        )
        XCTAssertTrue(
            AccountDataStatus.usage(
                accounts: [account(id: "disabled", provider: .openrouter, enabled: false)],
                records: records,
                emptyReason: "none"
            ).isUnavailable
        )
        XCTAssertEqual(
            AccountDataStatus.usage(accounts: [], records: records, emptyReason: "没有账户"),
            .missing("没有账户")
        )
    }
}
