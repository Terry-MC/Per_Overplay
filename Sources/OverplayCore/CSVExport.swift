import Foundation

public enum CSVExport {
    public static func makeCSV(
        records: [UsageRecord],
        range: DayRange?,
        generatedAt: Date = Date(),
        isDemo: Bool
    ) -> String {
        let headers = [
            "账户", "厂商", "日期（厂商 UTC 日）", "模型", "供应商",
            "Prompt tokens", "Completion tokens", "Reasoning tokens", "Cached tokens",
            "请求数", "费用", "币种", "BYOK 费用", "来源", "数据更新时间",
            "统计范围", "是否演示数据", "导出时间"
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
                record.promptTokens.map(String.init) ?? "未提供",
                record.completionTokens.map(String.init) ?? "未提供",
                record.reasoningTokens.map(String.init) ?? "未提供",
                record.cachedTokens.map(String.init) ?? "未提供",
                record.requests.map(String.init) ?? "未提供",
                record.cost.map { Money.formatPlain($0, fractionDigits: 6) } ?? "未提供",
                record.currency ?? "未提供",
                record.byokCost.map { Money.formatPlain($0, fractionDigits: 6) } ?? "未提供",
                record.source,
                formatter.string(from: record.updatedAt),
                range?.label ?? "当前筛选",
                isDemo ? "是（演示数据）" : "否",
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
