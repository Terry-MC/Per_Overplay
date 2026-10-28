import XCTest
@testable import OverplayCore

final class TimeRangeTests: XCTestCase {
    private let now = TestClock.date(2026, 10, 28, 12)

    func testPresetRangesUseLocalTodayInclusive() {
        let range = CalendarDay.range(
            preset: .seven,
            now: now,
            timeZone: TestClock.utc,
            calendar: TestClock.calendar
        )
        XCTAssertEqual(range.startDay, "2026-10-22")
        XCTAssertEqual(range.endDay, "2026-10-28")
        XCTAssertEqual(
            CalendarDay.days(from: range, timeZone: TestClock.utc, calendar: TestClock.calendar).count,
            7
        )
    }

    func testMonthRangeAndKey() {
        let (key, range) = CalendarDay.monthRange(
            now: now, timeZone: TestClock.utc, calendar: TestClock.calendar
        )
        XCTAssertEqual(key, "2026-10")
        XCTAssertEqual(range.startDay, "2026-10-01")
        XCTAssertEqual(range.endDay, "2026-10-31")
        XCTAssertEqual(
            CalendarDay.days(from: range, timeZone: TestClock.utc, calendar: TestClock.calendar).count,
            31
        )
    }

    func testMonthRangeAcrossTimezoneBoundary() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let instant = TestClock.date(2026, 11, 1, 2, 30)
        let (key, range) = CalendarDay.monthRange(
            now: instant, timeZone: newYork, calendar: Calendar(identifier: .gregorian)
        )
        XCTAssertEqual(key, "2026-10")
        XCTAssertEqual(range.startDay, "2026-10-01")
        XCTAssertEqual(range.endDay, "2026-10-31")
    }

    func testDayStringUsesRequestedTimezone() {
        let instant = TestClock.date(2026, 10, 28, 1)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(
            CalendarDay.string(for: instant, timeZone: tokyo, calendar: TestClock.calendar),
            "2026-10-28"
        )
        XCTAssertEqual(
            CalendarDay.string(for: instant, timeZone: losAngeles, calendar: TestClock.calendar),
            "2026-10-27"
        )
    }

    func testForecastMonthSpend() {
        let forecast = UsageMath.forecastMonthSpend(
            monthToDate: Decimal(50),
            now: now,
            timeZone: TestClock.utc,
            calendar: TestClock.calendar
        )
        XCTAssertEqual(forecast.map { Money.rounded($0, scale: 2) }, Decimal(string: "55.36"))
    }

    func testSummaryDoesNotTreatMissingTokensAsZero() {
        let records = [
            UsageRecord(
                accountId: "a", accountName: "A", provider: .openrouter, day: "2026-10-27",
                model: "m", promptTokens: 100, completionTokens: 50, reasoningTokens: 10,
                requests: 2, cost: Decimal(string: "0.25")!, currency: "USD", source: "test"
            ),
            UsageRecord(
                accountId: "b", accountName: "B", provider: .deepseek, day: "2026-10-27",
                model: "unavailable", source: "test"
            )
        ]
        let summary = UsageMath.summarize(records)
        XCTAssertEqual(summary.promptTokens, 100)
        XCTAssertEqual(summary.completionTokens, 50)
        XCTAssertEqual(summary.reasoningTokens, 10)
        XCTAssertEqual(summary.totalTokens, 150)
        XCTAssertEqual(summary.costsByCurrency["USD"], Decimal(string: "0.25"))
        XCTAssertTrue(summary.tokensAvailable)
    }
}
