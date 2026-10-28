import XCTest
@testable import OverplayCore

final class ToastCenterTests: XCTestCase {
    private let now = TestClock.date(2026, 10, 28, 12)

    private func toast(
        _ id: String,
        style: NoticeStyle = .info,
        autoDismiss: Bool = true,
        alertId: String? = nil
    ) -> ToastMessage {
        ToastMessage(
            id: id,
            title: "标题",
            message: "内容",
            style: style,
            alertId: alertId,
            duration: 8,
            autoDismiss: autoDismiss
        )
    }

    private func alert(kind: AlertKind, id: String = "alert") -> AlertEvent {
        AlertEvent(
            id: id,
            accountId: "a",
            accountName: "账户 A",
            kind: kind,
            firedAt: now,
            value: "85%",
            threshold: "80%",
            metric: "预算",
            periodKey: "2026-10"
        )
    }

    func testQueueShowsAtMostThreeAndPromotesPending() {
        var queue = ToastQueue(maxVisible: 3)
        let promoted = [
            queue.enqueue(toast("1"), now: now),
            queue.enqueue(toast("2"), now: now),
            queue.enqueue(toast("3"), now: now),
            queue.enqueue(toast("4"), now: now)
        ]
        XCTAssertEqual(promoted.map { $0.count }, [1, 1, 1, 0])
        XCTAssertEqual(queue.visible.map(\.id), ["1", "2", "3"])
        XCTAssertEqual(queue.pending.map(\.id), ["4"])
        XCTAssertTrue(queue.visible.allSatisfy { $0.expiresAt != nil })

        let promotedAfterExpiry = queue.expire(id: "1", now: now)
        XCTAssertEqual(promotedAfterExpiry.map(\.id), ["4"])
        XCTAssertEqual(queue.visible.map(\.id), ["2", "3", "4"])
    }

    func testErrorToastIsPrioritizedAndNeverAutoExpires() {
        var queue = ToastQueue(maxVisible: 2)
        _ = queue.enqueue(toast("info-1"), now: now)
        _ = queue.enqueue(toast("info-2"), now: now)
        let promoted = queue.enqueue(
            toast("error", style: .error, autoDismiss: false),
            now: now
        )
        XCTAssertTrue(promoted.isEmpty)
        XCTAssertEqual(queue.pending.first?.id, "error")

        let afterExpiry = queue.expire(id: "info-1", now: now)
        XCTAssertEqual(afterExpiry.map(\.id), ["error"])
        XCTAssertEqual(queue.visible.map(\.id), ["info-2", "error"])

        XCTAssertTrue(queue.expire(id: "error", now: now).isEmpty)
        XCTAssertTrue(queue.visible.contains { $0.id == "error" })

        _ = queue.dismiss(id: "error", now: now)
        XCTAssertFalse(queue.visible.contains { $0.id == "error" })
    }

    func testAlertPolicyMatchesSeverityDecisions() {
        XCTAssertEqual(AlertNoticePolicy.style(for: .budgetWarning), .info)
        XCTAssertTrue(AlertNoticePolicy.autoDismiss(for: .budgetWarning))

        for kind in [AlertKind.budgetExceeded, .balanceLow, .credentialInvalid, .syncFailed] {
            XCTAssertEqual(AlertNoticePolicy.style(for: kind), .error)
            XCTAssertFalse(AlertNoticePolicy.autoDismiss(for: kind))
        }
        XCTAssertEqual(AlertNoticePolicy.style(for: .dataStale), .warning)
        XCTAssertTrue(AlertNoticePolicy.autoDismiss(for: .dataStale))

        let warning = AlertNoticePolicy.toast(for: alert(kind: .budgetWarning))
        XCTAssertTrue(warning.autoDismiss)
        XCTAssertTrue(warning.isAlert)
        XCTAssertEqual(warning.style, .info)

        let exceeded = AlertNoticePolicy.toast(for: alert(kind: .budgetExceeded))
        XCTAssertFalse(exceeded.autoDismiss)
        XCTAssertEqual(exceeded.style, .error)
    }

    func testWarningArchivesWhileAlertRemainsUnacknowledged() {
        let warning = alert(kind: .budgetWarning)
        var queue = ToastQueue(maxVisible: 3)
        _ = queue.enqueue(AlertNoticePolicy.toast(for: warning), now: now)
        XCTAssertEqual(queue.visible.count, 1)
        XCTAssertTrue(queue.visible[0].autoDismiss)

        _ = queue.expire(id: queue.visible[0].id, now: now)
        XCTAssertTrue(queue.visible.isEmpty)
        XCTAssertEqual(MessageCenter.unacknowledgedCount([warning]), 1,
                       "顶部提示归档后消息仍保留在消息中心")
    }

    func testRemoveAlertDropsVisibleAndPendingCopies() {
        var queue = ToastQueue(maxVisible: 1)
        _ = queue.enqueue(toast("visible", alertId: "a"), now: now)
        _ = queue.enqueue(toast("pending", alertId: "b"), now: now)
        _ = queue.removeAlert(alertId: "b", now: now)
        XCTAssertEqual(queue.pending.count, 0)
        XCTAssertEqual(queue.visible.map(\.id), ["visible"])
        _ = queue.removeAlert(alertId: "a", now: now)
        XCTAssertTrue(queue.visible.isEmpty)
    }
}
