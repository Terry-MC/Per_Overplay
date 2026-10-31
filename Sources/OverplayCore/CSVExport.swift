import Foundation

public enum CSVExport {
    public static func makeCSV(
        records: [UsageRecord],
        range: DayRange?,
        generatedAt: Date = Date(),
        isDemo: Bool
    ) -> String {
        let headers = [
            L10n.t("core.csv.c3d92b20c8"), L10n.t("core.csv.0c131e3964"), L10n.t("core.csv.0544015b02"), L10n.t("core.csv.98fd0cbd9c"), L10n.t("core.csv.703c9eb0f0"),
            "Prompt tokens", "Completion tokens", "Reasoning tokens", "Cached tokens",
            L10n.t("core.analysisRange.b28376ff80"), L10n.t("metric.cost"), L10n.t("core.csv.a81ab5e100"), L10n.t("core.csv.b878cd977f"), L10n.t("core.csv.c63f79e636"), L10n.t("core.csv.1a811ce2ce"),
            L10n.t("core.csv.174fd6f85c"), L10n.t("core.csv.3f24ec10a5"), L10n.t("core.csv.d4e077f9d4")
        ]
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = CalendarDay.utc
        let generatedText = formatter.string(from: generatedAt)
        var lines = [headers.map(escape).joined(separator: ",")]
        for record in records {
            let values: [String] = [
                record.accountName,
                record.provider.displayName,
                record.day,
                record.model,
                record.providerName,
                record.promptTokens.map(String.init) ?? L10n.t("core.csv.071fb244ea"),
                record.completionTokens.map(String.init) ?? L10n.t("core.csv.071fb244ea"),
                record.reasoningTokens.map(String.init) ?? L10n.t("core.csv.071fb244ea"),
                record.cachedTokens.map(String.init) ?? L10n.t("core.csv.071fb244ea"),
                record.requests.map(String.init) ?? L10n.t("core.csv.071fb244ea"),
                record.cost.map { Money.formatPlain($0, fractionDigits: 6) } ?? L10n.t("core.csv.071fb244ea"),
                record.currency ?? L10n.t("core.csv.071fb244ea"),
                record.byokCost.map { Money.formatPlain($0, fractionDigits: 6) } ?? L10n.t("core.csv.071fb244ea"),
                record.source,
                formatter.string(from: record.updatedAt),
                range?.label ?? L10n.t("core.csv.8936ccc663"),
                isDemo ? L10n.t("core.csv.fa217b9faa") : L10n.t("common.no"),
                generatedText
            ]
            lines.append(values.map(escape).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    public static func suggestedFilename(range: DayRange?, generatedAt: Date, isDemo: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let suffix = isDemo ? "-demo" : ""
        return "overplay-usage-\(formatter.string(from: generatedAt))\(suffix).csv"
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
