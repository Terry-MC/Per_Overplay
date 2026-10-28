import XCTest
@testable import OverplayCore

final class MessageCenterTests: XCTestCase {
    private let now = TestClock.date(2026, 10, 28, 12)

    private func alert(
        id: String,
        kind: AlertKind,
        account: String = "账户 A",
        accountId: String = "a",
        firedAt: Date,
        value: String = "80%",
        acknowledged: Bool = false
    ) -> AlertEvent {
        AlertEvent(
            id: id,
            accountId: accountId,
            accountName: account,
            kind: kind,
            firedAt: firedAt,
            value: value,
            threshold: "80%",
            metric: "本地预算月度使用率",
            periodKey: "2026-10",
            acknowledged: acknowledged
        )
    }

    func testFiltersByTypeAccountStatusAndSearch() {
        let alerts = [
            alert(id: "1", kind: .budgetWarning, firedAt: now.addingTimeInterval(-60)),
            alert(id: "2", kind: .budgetExceeded, account: "账户 B", accountId: "b",
                  firedAt: now.addingTimeInterval(-120), acknowledged: true),
            alert(id: "3", kind: .balanceLow, account: "账户 B", accountId: "b",
                  firedAt: now.addingTimeInterval(-180)),
            alert(id: "4", kind: .syncFailed, firedAt: now.addingTimeInterval(-5 * 86_400))
        ]

        let budget = MessageCenter.filteredAlerts(
            alerts,
            criteria: MessageFilterCriteria(type: .budget),
            now: now
        )
        XCTAssertEqual(budget.map(\.id), ["1", "2"])

        let accountB = MessageCenter.filteredAlerts(
            alerts,
            criteria: MessageFilterCriteria(accountId: "b"),
            now: now
        )
        XCTAssertEqual(accountB.map(\.id), ["2", "3"])

        let unread = MessageCenter.filteredAlerts(
            alerts,
            criteria: MessageFilterCriteria(status: .unread),
            now: now
        )
        XCTAssertEqual(unread.map(\.id), ["1", "3", "4"])

        let search = MessageCenter.filteredAlerts(
            alerts,
            criteria: MessageFilterCriteria(searchText: "账户 b"),
            now: now
        )
        XCTAssertEqual(search.map(\.id), ["2", "3"])
    }

    func testTimeFiltersAndSorting() {
        let alerts = [
            alert(id: "today", kind: .balanceLow, firedAt: now.addingTimeInterval(-60)),
            alert(id: "week", kind: .syncFailed, firedAt: now.addingTimeInterval(-3 * 86_400)),
            alert(id: "month", kind: .dataStale, firedAt: now.addingTimeInterval(-10 * 86_400))
        ]
        XCTAssertEqual(
            MessageCenter.filteredAlerts(
                alerts,
                criteria: MessageFilterCriteria(time: .today),
                now: now,
                calendar: TestClock.calendar
            ).map(\.id),
            ["today"]
        )
        XCTAssertEqual(
            MessageCenter.filteredAlerts(
                alerts,
                criteria: MessageFilterCriteria(time: .week),
                now: now,
                calendar: TestClock.calendar
            ).map(\.id),
            ["today", "week"]
        )
        XCTAssertEqual(
            MessageCenter.filteredAlerts(
                alerts,
                criteria: MessageFilterCriteria(time: .month),
                now: now,
                calendar: TestClock.calendar
            ).map(\.id),
            ["today", "week", "month"],
            "结果按触发时间倒序"
        )
    }

    func testUnacknowledgedCountAndAccountOptions() {
        let alerts = [
            alert(id: "1", kind: .budgetWarning, account: "账户 B", accountId: "b", firedAt: now),
            alert(id: "2", kind: .balanceLow, account: "账户 A", accountId: "a", firedAt: now, acknowledged: true),
            alert(id: "3", kind: .syncFailed, account: "账户 A", accountId: "a", firedAt: now)
        ]
        XCTAssertEqual(MessageCenter.unacknowledgedCount(alerts), 2)
        XCTAssertEqual(
            MessageCenter.accountOptions(alerts),
            [
                MessageAccountOption(id: "a", name: "账户 A"),
                MessageAccountOption(id: "b", name: "账户 B")
            ]
        )
    }

    func testEmptyCriteriaMatchesEverything() {
        let alerts = [
            alert(id: "1", kind: .budgetWarning, firedAt: now),
            alert(id: "2", kind: .credentialInvalid, firedAt: now.addingTimeInterval(-60))
        ]
        XCTAssertFalse(MessageFilterCriteria().isActive)
        XCTAssertEqual(
            MessageCenter.filteredAlerts(alerts, criteria: MessageFilterCriteria(), now: now)
                .map(\.id),
            ["1", "2"]
        )
    }
}
