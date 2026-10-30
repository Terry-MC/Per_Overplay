import XCTest
@testable import OverplayCore

final class AnalysisRangeTests: XCTestCase {
    private let now = TestClock.date(2026, 10, 28, 12)

    func testNaturalRangesUseLocalCalendar() throws {
        let today = try AnalysisRange.make(
            preset: .today, now: now, timeZone: TestClock.utc, calendar: TestClock.calendar
        )
        XCTAssertEqual(today.dayRange.startDay, "2026-10-28")
        XCTAssertEqual(today.dayRange.endDay, "2026-10-28")
        XCTAssertTrue(today.start < today.end)

        let month = try AnalysisRange.make(
            preset: .thisMonth, now: now, timeZone: TestClock.utc, calendar: TestClock.calendar
        )
        XCTAssertEqual(month.dayRange.startDay, "2026-10-01")
        XCTAssertEqual(month.dayRange.endDay, "2026-10-28")

        let last30 = try AnalysisRange.make(
            preset: .last30Days, now: now, timeZone: TestClock.utc, calendar: TestClock.calendar
        )
        XCTAssertEqual(last30.dayRange.startDay, "2026-09-29")
        XCTAssertEqual(last30.dayRange.endDay, "2026-10-28")
        XCTAssertEqual(
            CalendarDay.days(from: last30.dayRange, timeZone: TestClock.utc, calendar: TestClock.calendar).count,
            30
        )
    }

    func testCustomRangeKeepsMinutePrecision() throws {
        let start = TestClock.date(2026, 10, 27, 9, 30)
        let end = TestClock.date(2026, 10, 28, 11, 45)
        let range = try AnalysisRange.make(
            preset: .custom,
            customStart: start,
            customEnd: end,
            now: now,
            timeZone: TestClock.utc,
            calendar: TestClock.calendar
        )
        XCTAssertEqual(range.start, start)
        XCTAssertEqual(range.end, end)
        XCTAssertEqual(range.dayRange.startDay, "2026-10-27")
        XCTAssertEqual(range.dayRange.endDay, "2026-10-28")
        XCTAssertTrue(range.isCustom)
    }

    func testCustomRangeValidation() {
        XCTAssertThrowsError(
            try AnalysisRange.make(
                preset: .custom,
                customStart: now,
                customEnd: now.addingTimeInterval(-60),
                now: now,
                timeZone: TestClock.utc,
                calendar: TestClock.calendar
            )
        ) { error in
            XCTAssertEqual(error as? AnalysisRangeError, .startAfterEnd)
        }

        XCTAssertThrowsError(
            try AnalysisRange.make(
                preset: .custom,
                customStart: now.addingTimeInterval(-366 * 86_400),
                customEnd: now,
                now: now,
                timeZone: TestClock.utc,
                calendar: TestClock.calendar
            )
        ) { error in
            XCTAssertEqual(error as? AnalysisRangeError, .exceedsRetention(days: 365))
        }
    }

    func testCustomRetentionBoundaryUsesCalendarAcrossDST() throws {
        let newYork = TimeZone(identifier: "America/New_York")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 8, hour: 12, minute: 0
        ))!
        let start = calendar.date(byAdding: .day, value: -365, to: now)!
        XCTAssertNoThrow(
            try AnalysisRange.make(
                preset: .custom,
                customStart: start,
                customEnd: now,
                now: now,
                timeZone: newYork,
                calendar: calendar
            )
        )
    }

    func testGranularitySupportFollowsProviderCapabilities() {
        XCTAssertTrue(
            AnalysisGranularitySupport.available(for: .deepseek, isDemo: false).contains(.minute)
        )
        XCTAssertFalse(
            AnalysisGranularitySupport.available(for: .openrouter, isDemo: false).contains(.minute)
        )
        XCTAssertFalse(
            AnalysisGranularitySupport.available(for: .openrouter, isDemo: true).contains(.hour)
        )
        XCTAssertEqual(
            AnalysisGranularitySupport.available(for: .openrouter, isDemo: false),
            [.automatic, .day, .month, .year]
        )
        XCTAssertTrue(
            AnalysisChartMath.granuleSupportsUsage(.day)
        )
        XCTAssertFalse(
            AnalysisChartMath.granuleSupportsUsage(.hour)
        )
    }

    func testProviderTotalsAndCoverageDoNotTreatMissingAsZero() {
        let openRouter = Account(
            id: "or", provider: .openrouter, name: "OpenRouter", isDemo: false
        )
        let deepSeek = Account(
            id: "ds", provider: .deepseek, name: "DeepSeek", isDemo: false
        )
        let records = [
            UsageRecord(
                accountId: openRouter.id,
                accountName: openRouter.name,
                provider: .openrouter,
                day: "2026-10-27",
                model: "m1",
                promptTokens: 100,
                completionTokens: 50,
                reasoningTokens: 10,
                cachedTokens: 20,
                requests: 3,
                cost: Decimal(string: "0.25")!,
                currency: "USD",
                source: "test"
            ),
            UsageRecord(
                accountId: openRouter.id,
                accountName: openRouter.name,
                provider: .openrouter,
                day: "2026-10-28",
                model: "m2",
                source: "test"
            )
        ]

        let totals = ProviderAnalysisMetrics.totals(records: records, account: openRouter)
        XCTAssertTrue(totals.tokensAvailable)
        XCTAssertEqual(totals.totalTokens, 150)
        XCTAssertEqual(totals.requests, 3)
        XCTAssertEqual(totals.costs, ["USD": Decimal(string: "0.25")!])
        XCTAssertEqual(totals.recordCount, 2)
        XCTAssertEqual(totals.tokenRecordCount, 1)

        let coverage = ProviderAnalysisMetrics.coverage(
            accounts: [openRouter, deepSeek],
            records: records
        )
        XCTAssertEqual(coverage.totalAccounts, 2)
        XCTAssertEqual(coverage.accountsWithTokens, 1)
        XCTAssertEqual(coverage.accountsWithCost, 1)
        XCTAssertEqual(coverage.accountsWithRequests, 1)
        XCTAssertEqual(coverage.totalProviders, 2)
        XCTAssertEqual(coverage.providersWithTokens, 1)
    }

    func testUsageSegmentsBreakAtMissingDaysAndAggregateMonths() {
        let days = ["2026-10-01", "2026-10-02", "2026-10-04", "2026-10-05", "2026-12-01"]
        let values = [
            "2026-10-01": 10.0,
            "2026-10-02": 20.0,
            "2026-10-04": 40.0,
            "2026-10-05": 50.0,
            "2026-12-01": 5.0
        ]

        let daily = AnalysisChartMath.segments(days: days, values: values, granularity: .day)
        XCTAssertEqual(daily.count, 3)
        XCTAssertEqual(daily[0].count, 2)
        XCTAssertEqual(daily[1].count, 2)
        XCTAssertEqual(daily[2].count, 1)
        XCTAssertFalse(daily.flatMap { $0 }.contains { $0.key == "2026-10-03" })

        let monthly = AnalysisChartMath.segments(days: days, values: values, granularity: .month)
        XCTAssertEqual(monthly.count, 2)
        XCTAssertEqual(monthly[0].first?.key, "2026-10")
        XCTAssertEqual(monthly[0].map(\.value).reduce(0, +), 120)
        XCTAssertEqual(monthly[1].first?.value, 5)
    }

    func testBalanceGranularityKeepsLastSnapshotPerBucket() {
        let snapshots = [
            BalanceSnapshot(
                id: "1", accountId: "ds", currency: "CNY", total: 100,
                asOf: TestClock.date(2026, 10, 28, 10, 5), source: "test"
            ),
            BalanceSnapshot(
                id: "2", accountId: "ds", currency: "CNY", total: 90,
                asOf: TestClock.date(2026, 10, 28, 10, 45), source: "test"
            ),
            BalanceSnapshot(
                id: "3", accountId: "ds", currency: "CNY", total: 80,
                asOf: TestClock.date(2026, 10, 28, 11, 10), source: "test"
            )
        ]

        let raw = AnalysisChartMath.balancePoints(
            snapshots: snapshots,
            granularity: .automatic,
            timeZone: TestClock.utc,
            calendar: TestClock.calendar
        )
        XCTAssertEqual(raw.count, 3)

        let hourly = AnalysisChartMath.balancePoints(
            snapshots: snapshots,
            granularity: .hour,
            timeZone: TestClock.utc,
            calendar: TestClock.calendar
        )
        XCTAssertEqual(hourly.count, 2)
        XCTAssertEqual(hourly[0].value, 90)
        XCTAssertEqual(hourly[1].value, 80)
    }

    func testBalanceGranularityKeepsLastSnapshotPerCurrencyInSameBucket() {
        let snapshots = [
            BalanceSnapshot(
                id: "cny-1", accountId: "ds", currency: "CNY", total: 100,
                asOf: TestClock.date(2026, 10, 28, 10, 5), source: "test"
            ),
            BalanceSnapshot(
                id: "usd-1", accountId: "ds", currency: "USD", total: 50,
                asOf: TestClock.date(2026, 10, 28, 10, 10), source: "test"
            ),
            BalanceSnapshot(
                id: "cny-2", accountId: "ds", currency: "CNY", total: 90,
                asOf: TestClock.date(2026, 10, 28, 10, 45), source: "test"
            ),
            BalanceSnapshot(
                id: "usd-2", accountId: "ds", currency: "USD", total: 40,
                asOf: TestClock.date(2026, 10, 28, 10, 50), source: "test"
            )
        ]

        let hourly = AnalysisChartMath.balancePoints(
            snapshots: snapshots,
            granularity: .hour,
            timeZone: TestClock.utc,
            calendar: TestClock.calendar
        )
        XCTAssertEqual(hourly.count, 2)
        XCTAssertEqual(hourly.filter { $0.currency == "CNY" }.first?.value, 90)
        XCTAssertEqual(hourly.filter { $0.currency == "USD" }.first?.value, 40)
    }
}
