import XCTest
@testable import OverplayCore

final class MoneyTests: XCTestCase {
    func testCurrencyFormatting() {
        XCTAssertEqual(Money.formatBalance(Decimal(string: "1234.5")!, currency: "USD"), "$1,234.50")
        XCTAssertEqual(Money.formatBalance(Decimal(string: "12.345")!, currency: "CNY"), "¥12.35")
        XCTAssertEqual(Money.formatBalance(Decimal(string: "0.0001")!, currency: "USD"), "$0.00")
        XCTAssertEqual(Money.formatCost(Decimal(string: "0.0001")!, currency: "USD"), "$0.0001")
        XCTAssertEqual(Money.formatBalance(Decimal(string: "10")!, currency: "EUR"), "€10.00")
    }

    func testPercentAndCompactTokens() {
        XCTAssertEqual(Money.percent(Decimal(string: "85.25")!), "85.3%")
        XCTAssertEqual(Money.percent(Decimal(80), fractionDigits: 0), "80%")
        XCTAssertEqual(Money.formatCompactInteger(999), "999")
        XCTAssertEqual(Money.formatCompactInteger(12_500), "12.5K")
        XCTAssertEqual(Money.formatCompactInteger(2_000_000), "2M")
        XCTAssertEqual(Money.formatInteger(1234567), "1,234,567")
    }

    func testDecimalAggregationHasNoCrossCurrencySum() {
        let sums = Money.sumByCurrency([
            (Decimal(string: "1.10")!, "USD"),
            (Decimal(string: "2.20")!, "USD"),
            (Decimal(string: "3.30")!, "CNY")
        ])
        XCTAssertEqual(sums["USD"], Decimal(string: "3.30"))
        XCTAssertEqual(sums["CNY"], Decimal(string: "3.30"))
        XCTAssertEqual(sums.count, 2)
    }

    func testDecimalAdditionIsExact() {
        var total = Decimal(string: "0.1")!
        for _ in 0..<10 {
            total += Decimal(string: "0.1")!
        }
        XCTAssertEqual(total, Decimal(string: "1.1"))
    }

    func testRatio() {
        XCTAssertEqual(Money.ratio(Decimal(85), Decimal(100)), Decimal(85))
        XCTAssertNil(Money.ratio(Decimal(1), Decimal(0)))
    }

    func testRounding() {
        XCTAssertEqual(Money.rounded(Decimal(string: "1.005")!, scale: 2), Decimal(string: "1.01"))
        XCTAssertEqual(Money.rounded(Decimal(string: "1.004")!, scale: 2), Decimal(string: "1.00"))
    }
}
