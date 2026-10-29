import XCTest
@testable import OverplayCore

final class StatusItemPresentationTests: XCTestCase {
    private func alert(_ kind: AlertKind, acknowledged: Bool = false) -> AlertEvent {
        AlertEvent(
            accountId: "acct-1",
            accountName: "Demo",
            kind: kind,
            firedAt: TestClock.date(),
            value: "1",
            threshold: "2",
            metric: "test",
            periodKey: "2026-10",
            acknowledged: acknowledged
        )
    }

    func testDemoBadgeIsShownWithoutAlerts() {
        let presentation = StatusItemPresentation.make(isDemo: true, alerts: [])
        XCTAssertTrue(presentation.showsDemoBadge)
        XCTAssertEqual(presentation.severity, .normal)
        XCTAssertTrue(presentation.accessibilityLabel.contains("演示数据"))
    }

    func testDemoBadgeSurvivesFailureAlert() {
        let presentation = StatusItemPresentation.make(
            isDemo: true,
            alerts: [alert(.syncFailed)]
        )
        XCTAssertTrue(presentation.showsDemoBadge)
        XCTAssertEqual(presentation.severity, .failure)
        XCTAssertEqual(presentation.symbolName, "xmark.octagon.fill")
        XCTAssertTrue(presentation.accessibilityLabel.contains("演示数据"))
    }

    func testDemoBadgeSurvivesWarningAlert() {
        let presentation = StatusItemPresentation.make(
            isDemo: true,
            alerts: [alert(.budgetWarning)]
        )
        XCTAssertTrue(presentation.showsDemoBadge)
        XCTAssertEqual(presentation.severity, .warning)
        XCTAssertTrue(presentation.accessibilityLabel.contains("演示数据"))
    }

    func testRealModeNeverShowsDemoBadge() {
        let alerts = [
            alert(.balanceLow),
            alert(.dataStale),
            alert(.credentialInvalid)
        ]
        let presentation = StatusItemPresentation.make(isDemo: false, alerts: alerts)
        XCTAssertFalse(presentation.showsDemoBadge)
        XCTAssertFalse(presentation.accessibilityLabel.contains("演示数据"))
    }

    func testAcknowledgedAlertsDoNotDriveSeverity() {
        let presentation = StatusItemPresentation.make(
            isDemo: false,
            alerts: [alert(.syncFailed, acknowledged: true)]
        )
        XCTAssertEqual(presentation.severity, .normal)
        XCTAssertEqual(presentation.symbolName, "chart.bar.xaxis")
    }
}
