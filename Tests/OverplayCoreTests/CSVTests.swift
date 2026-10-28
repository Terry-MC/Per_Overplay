import XCTest
@testable import OverplayCore

final class CSVTests: XCTestCase {
    func testCSVContainsSourceRangeAndNoCredential() {
        let record = UsageRecord(
            accountId: "a",
            accountName: "测试账户",
            provider: .openrouter,
            day: "2026-10-27",
            model: "model,with,commas",
            providerName: "OpenAI",
            promptTokens: 100,
            completionTokens: 50,
            reasoningTokens: 10,
            requests: 2,
            cost: Decimal(string: "0.42")!,
            currency: "USD",
            source: "OpenRouter 官方 API · GET /activity",
            updatedAt: TestClock.date()
        )
        let csv = CSVExport.makeCSV(
            records: [record],
            range: DayRange(startDay: "2026-10-01", endDay: "2026-10-28"),
            generatedAt: TestClock.date(2026, 10, 28, 13),
            isDemo: false
        )
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
        XCTAssertTrue(csv.contains("OpenRouter 官方 API"))
        XCTAssertTrue(csv.contains("2026-10-01 至 2026-10-28"))
        XCTAssertTrue(csv.contains("\"model,with,commas\""))
        XCTAssertTrue(csv.contains("0.42"))
        XCTAssertFalse(csv.contains("sk-"))
    }

    func testDemoCSVIsMarked() {
        let csv = CSVExport.makeCSV(records: [], range: nil, isDemo: true)
        XCTAssertTrue(csv.contains("是否演示数据"))
        XCTAssertTrue(csv.contains("演示数据"))
        let filename = CSVExport.suggestedFilename(range: nil, generatedAt: TestClock.date(), isDemo: true)
        XCTAssertTrue(filename.contains("demo"))
        XCTAssertTrue(filename.hasSuffix(".csv"))
    }

    func testCSVQuotesAndEscapes() {
        let record = UsageRecord(
            accountId: "a",
            accountName: "name \"quoted\"",
            provider: .openrouter,
            day: "2026-10-27",
            model: "m\nline",
            source: "source",
            updatedAt: TestClock.date()
        )
        let csv = CSVExport.makeCSV(records: [record], range: nil, isDemo: false)
        XCTAssertTrue(csv.contains("\"name \"\"quoted\"\"\""))
        XCTAssertTrue(csv.contains("\"m\nline\""))
    }

    func testMissingValuesAreNotZero() {
        let record = UsageRecord(
            accountId: "a",
            accountName: "a",
            provider: .openrouter,
            day: "2026-10-27",
            model: "m",
            source: "source",
            updatedAt: TestClock.date()
        )
        let csv = CSVExport.makeCSV(records: [record], range: nil, isDemo: false)
        XCTAssertTrue(csv.contains("未提供"))
        XCTAssertFalse(csv.contains(",0,"))
    }

    func testUsageGroupingByModel() {
        let records = [
            UsageRecord(
                accountId: "a", accountName: "A", provider: .openrouter, day: "2026-10-27",
                model: "m1", promptTokens: 10, cost: 1, currency: "USD", source: "s",
                updatedAt: TestClock.date()
            ),
            UsageRecord(
                accountId: "a", accountName: "A", provider: .openrouter, day: "2026-10-26",
                model: "m1", promptTokens: 20, cost: 2, currency: "USD", source: "s",
                updatedAt: TestClock.date()
            ),
            UsageRecord(
                accountId: "a", accountName: "A", provider: .openrouter, day: "2026-10-26",
                model: "m2", promptTokens: 5, cost: 4, currency: "USD", source: "s",
                updatedAt: TestClock.date()
            )
        ]
        let grouped = UsageMath.groupByModel(records)
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped.first?.model, "m2")
        XCTAssertEqual(grouped.first?.cost, 4)
        XCTAssertEqual(grouped.first { $0.model == "m1" }?.promptTokens, 30)
        XCTAssertEqual(grouped.first { $0.model == "m1" }?.cost, 3)
    }
}

extension CSVTests {
    func testModelUsageAggregatesExtendedFieldsAndFlags() throws {
        let records = [
            UsageRecord(
                accountId: "a", accountName: "A", provider: .openrouter, day: "2026-10-27",
                model: "m1", promptTokens: 100, completionTokens: 50, reasoningTokens: 20,
                cachedTokens: 10, requests: 3, cost: Decimal(string: "0.5")!, currency: "USD",
                source: "s", updatedAt: TestClock.date()
            ),
            UsageRecord(
                accountId: "a", accountName: "A", provider: .openrouter, day: "2026-10-26",
                model: "m1", promptTokens: 50, completionTokens: 25, reasoningTokens: 5,
                cachedTokens: 2, requests: 2, cost: Decimal(string: "0.25")!, currency: "USD",
                source: "s", updatedAt: TestClock.date()
            ),
            UsageRecord(
                accountId: "a", accountName: "A", provider: .openrouter, day: "2026-10-25",
                model: "m2", cost: Decimal(string: "0.1")!, currency: "USD",
                source: "s", updatedAt: TestClock.date()
            )
        ]
        let grouped = UsageMath.groupByModel(records)
        let m1 = try XCTUnwrap(grouped.first { $0.model == "m1" })
        XCTAssertEqual(m1.promptTokens, 150)
        XCTAssertEqual(m1.completionTokens, 75)
        XCTAssertEqual(m1.reasoningTokens, 25)
        XCTAssertEqual(m1.cachedTokens, 12)
        XCTAssertEqual(m1.requests, 5)
        XCTAssertTrue(m1.promptAvailable)
        XCTAssertTrue(m1.completionAvailable)
        XCTAssertTrue(m1.reasoningAvailable)
        XCTAssertTrue(m1.cachedAvailable)
        XCTAssertTrue(m1.requestsAvailable)

        let m2 = try XCTUnwrap(grouped.first { $0.model == "m2" })
        XCTAssertFalse(m2.promptAvailable)
        XCTAssertFalse(m2.completionAvailable)
        XCTAssertFalse(m2.reasoningAvailable)
        XCTAssertFalse(m2.cachedAvailable)
        XCTAssertFalse(m2.requestsAvailable)
    }
}
