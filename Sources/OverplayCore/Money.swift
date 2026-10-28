import Foundation

public enum Money {
    public static func symbol(for currency: String) -> String {
        switch currency.uppercased() {
        case "USD": return "$"
        case "CNY": return "¥"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY": return "¥"
        default: return currency.uppercased() + " "
        }
    }

    public static func format(
        _ amount: Decimal,
        currency: String,
        minimumFractionDigits: Int = 2,
        maximumFractionDigits: Int = 6
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.roundingMode = .halfUp
        let number = NSDecimalNumber(decimal: amount)
        let text = formatter.string(from: number) ?? "\(amount)"
        return symbol(for: currency) + text
    }

    public static func formatBalance(_ amount: Decimal, currency: String) -> String {
        format(amount, currency: currency, minimumFractionDigits: 2, maximumFractionDigits: 2)
    }

    public static func formatCost(_ amount: Decimal, currency: String) -> String {
        if amount != 0 && abs(amount) < Decimal(string: "0.01")! {
            return format(amount, currency: currency, minimumFractionDigits: 2, maximumFractionDigits: 6)
        }
        return format(amount, currency: currency, minimumFractionDigits: 2, maximumFractionDigits: 2)
    }

    public static func formatPlain(_ amount: Decimal, fractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = fractionDigits
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }

    public static func formatInteger(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    public static func formatCompactInteger(_ value: Int) -> String {
        let magnitude = abs(value)
        if magnitude >= 1_000_000_000 {
            return formatDecimal(Double(value) / 1_000_000_000.0) + "B"
        }
        if magnitude >= 1_000_000 {
            return formatDecimal(Double(value) / 1_000_000.0) + "M"
        }
        if magnitude >= 10_000 {
            return formatDecimal(Double(value) / 1_000.0) + "K"
        }
        return formatInteger(value)
    }

    private static func formatDecimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", rounded)
    }

    public static func percent(_ value: Decimal, fractionDigits: Int = 1) -> String {
        formatPlain(value, fractionDigits: fractionDigits) + "%"
    }

    public static func parse(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func rounded(_ value: Decimal, scale: Int = 2) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, .plain)
        return output
    }

    /// Groups amounts by currency without ever summing across currencies.
    public static func sumByCurrency(_ values: [(Decimal, String)]) -> [String: Decimal] {
        var result: [String: Decimal] = [:]
        for (amount, currency) in values {
            result[currency, default: 0] += amount
        }
        return result
    }

    public static func ratio(_ numerator: Decimal, _ denominator: Decimal) -> Decimal? {
        guard denominator > 0 else { return nil }
        return numerator / denominator * 100
    }
}
