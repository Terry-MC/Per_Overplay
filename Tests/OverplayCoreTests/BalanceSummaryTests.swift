import XCTest
@testable import OverplayCore

final class BalanceSummaryTests: XCTestCase {
    private func snapshot(
        accountId: String,
        currency: String,
        total: Decimal
    ) -> BalanceSnapshot {
        BalanceSnapshot(
            accountId: accountId,
            currency: currency,
            total: total,
            asOf: Date(timeIntervalSince1970: 0),
            source: "test"
        )
    }

    private func balances() -> [String: [String: BalanceSnapshot]] {
        [
            "account-cny-a": [
                "CNY": snapshot(accountId: "account-cny-a", currency: "CNY", total: 100)
            ],
            "account-cny-b": [
                "CNY": snapshot(accountId: "account-cny-b", currency: "CNY", total: 50)
            ],
            "account-usd": [
                "USD": snapshot(accountId: "account-usd", currency: "USD", total: 20)
            ]
        ]
    }

    func testTotalsAreGroupedByCurrencyAndNeverMixed() {
        let totals = BalanceSummary.totalsByCurrency(
            balances: balances(),
            accountIds: ["account-cny-a", "account-cny-b", "account-usd"]
        )
        XCTAssertEqual(totals["CNY"], Decimal(150))
        XCTAssertEqual(totals["USD"], Decimal(20))
        XCTAssertEqual(Set(totals.keys), Set(["CNY", "USD"]))
    }

    func testSameCurrencyAccountsAreSummedWithinThatCurrency() {
        let totals = BalanceSummary.totalsByCurrency(
            balances: balances(),
            accountIds: ["account-cny-a", "account-cny-b"]
        )
        XCTAssertEqual(totals, ["CNY": Decimal(150)])
    }

    func testAccountFilterOnlyIncludesSelectedAccountCurrency() {
        let totals = BalanceSummary.totalsByCurrency(
            balances: balances(),
            accountIds: ["account-usd"]
        )
        XCTAssertEqual(totals, ["USD": Decimal(20)])
        XCTAssertNil(totals["CNY"])
    }

    func testUnknownOrEmptyAccountSelectionReturnsEmpty() {
        XCTAssertTrue(
            BalanceSummary.totalsByCurrency(
                balances: balances(),
                accountIds: ["missing"]
            ).isEmpty
        )
        XCTAssertTrue(
            BalanceSummary.totalsByCurrency(
                balances: balances(),
                accountIds: []
            ).isEmpty
        )
    }

    func testCurrenciesAreSortedAndUnique() {
        let snapshots = [
            snapshot(accountId: "a", currency: "USD", total: 1),
            snapshot(accountId: "a", currency: "CNY", total: 2),
            snapshot(accountId: "a", currency: "USD", total: 3)
        ]
        XCTAssertEqual(BalanceSummary.currencies(for: snapshots), ["CNY", "USD"])
        XCTAssertTrue(BalanceSummary.currencies(for: []).isEmpty)
    }
}
