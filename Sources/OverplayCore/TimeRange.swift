import Foundation

public enum AnalysisPreset: Int, CaseIterable, Identifiable {
    case seven = 7
    case thirty = 30
    case ninety = 90

    public var id: Int { rawValue }
    public var label: String { "\(rawValue) 天" }
}

public struct DayRange: Equatable, Sendable {
    public let startDay: String
    public let endDay: String

    public init(startDay: String, endDay: String) {
        self.startDay = startDay
        self.endDay = endDay
    }

    public func contains(_ day: String) -> Bool {
        day >= startDay && day <= endDay
    }

    public var label: String { "\(startDay) 至 \(endDay)" }
}

public enum CalendarDay {
    public static let utc: TimeZone = TimeZone(secondsFromGMT: 0)!

    public static func string(
        for date: Date,
        timeZone: TimeZone = .current,
        calendar baseCalendar: Calendar = .current
    ) -> String {
        var calendar = baseCalendar
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func date(
        from text: String,
        timeZone: TimeZone = .current,
        calendar baseCalendar: Calendar = .current
    ) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = baseCalendar
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }

    public static func range(
        preset: AnalysisPreset,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        calendar baseCalendar: Calendar = .current
    ) -> DayRange {
        var calendar = baseCalendar
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(preset.rawValue - 1), to: today) ?? today
        return DayRange(
            startDay: string(for: start, timeZone: timeZone, calendar: calendar),
            endDay: string(for: today, timeZone: timeZone, calendar: calendar)
        )
    }

    public static func today(
        now: Date = Date(),
        timeZone: TimeZone = .current,
        calendar baseCalendar: Calendar = .current
    ) -> String {
        string(for: now, timeZone: timeZone, calendar: baseCalendar)
    }

    public static func monthRange(
        now: Date = Date(),
        timeZone: TimeZone = .current,
        calendar baseCalendar: Calendar = .current
    ) -> (monthKey: String, range: DayRange) {
        var calendar = baseCalendar
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month], from: now)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? now
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) ?? now
        let end = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? now
        return (
            String(format: "%04d-%02d", year, month),
            DayRange(
                startDay: string(for: start, timeZone: timeZone, calendar: calendar),
                endDay: string(for: end, timeZone: timeZone, calendar: calendar)
            )
        )
    }

    public static func days(
        from range: DayRange,
        timeZone: TimeZone = .current,
        calendar baseCalendar: Calendar = .current
    ) -> [String] {
        guard var cursor = date(from: range.startDay, timeZone: timeZone, calendar: baseCalendar),
              let end = date(from: range.endDay, timeZone: timeZone, calendar: baseCalendar),
              cursor <= end else { return [] }
        var calendar = baseCalendar
        calendar.timeZone = timeZone
        var result: [String] = []
        while cursor <= end {
            result.append(string(for: cursor, timeZone: timeZone, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    public static func daysElapsedInMonth(
        now: Date = Date(),
        timeZone: TimeZone = .current,
        calendar baseCalendar: Calendar = .current
    ) -> Int {
        var calendar = baseCalendar
        calendar.timeZone = timeZone
        return calendar.component(.day, from: now)
    }

    public static func daysInMonth(
        now: Date = Date(),
        timeZone: TimeZone = .current,
        calendar baseCalendar: Calendar = .current
    ) -> Int {
        var calendar = baseCalendar
        calendar.timeZone = timeZone
        guard let range = calendar.range(of: .day, in: .month, for: now) else { return 30 }
        return range.count
    }
}

public enum UsageMath {
    public static func summarize(_ records: [UsageRecord]) -> UsageSummary {
        var prompt = 0
        var completion = 0
        var reasoning = 0
        var requests = 0
        var costs: [String: Decimal] = [:]
        var tokensAvailable = false

        for record in records {
            if let promptTokens = record.promptTokens {
                prompt += promptTokens
                tokensAvailable = true
            }
            if let completionTokens = record.completionTokens {
                completion += completionTokens
                tokensAvailable = true
            }
            reasoning += record.reasoningTokens ?? 0
            requests += record.requests ?? 0
            if let cost = record.cost, let currency = record.currency {
                costs[currency, default: 0] += cost
            }
        }

        return UsageSummary(
            promptTokens: prompt,
            completionTokens: completion,
            reasoningTokens: reasoning,
            requests: requests,
            costsByCurrency: costs,
            records: records.count,
            tokensAvailable: tokensAvailable
        )
    }

    public static func groupByDay(_ records: [UsageRecord]) -> [(day: String, cost: Decimal, currency: String)] {
        var totals: [String: Decimal] = [:]
        var currency = ""
        for record in records {
            guard let cost = record.cost, let recordCurrency = record.currency else { continue }
            let key = "\(record.day)|\(recordCurrency)"
            totals[key, default: 0] += cost
            if currency.isEmpty { currency = recordCurrency }
        }
        return totals.compactMap { key, value in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0], value, parts[1])
        }
        .sorted { $0.day < $1.day }
    }

    public static func groupByModel(_ records: [UsageRecord]) -> [ModelUsage] {
        var grouped: [String: ModelUsage] = [:]
        for record in records {
            let key = "\(record.accountId)|\(record.model)|\(record.currency ?? "")"
            var usage = grouped[key] ?? ModelUsage(
                accountId: record.accountId,
                accountName: record.accountName,
                model: record.model,
                currency: record.currency,
                promptTokens: 0,
                completionTokens: 0,
                reasoningTokens: 0,
                cachedTokens: 0,
                requests: 0,
                cost: 0,
                byokCost: 0,
                promptAvailable: false,
                completionAvailable: false,
                reasoningAvailable: false,
                cachedAvailable: false,
                requestsAvailable: false,
                costAvailable: false,
                byokAvailable: false,
                lastUpdated: record.updatedAt,
                source: record.source
            )
            if let prompt = record.promptTokens {
                usage.promptTokens += prompt
                usage.promptAvailable = true
            }
            if let completion = record.completionTokens {
                usage.completionTokens += completion
                usage.completionAvailable = true
            }
            if let reasoning = record.reasoningTokens {
                usage.reasoningTokens += reasoning
                usage.reasoningAvailable = true
            }
            if let cached = record.cachedTokens {
                usage.cachedTokens += cached
                usage.cachedAvailable = true
            }
            if let requests = record.requests {
                usage.requests += requests
                usage.requestsAvailable = true
            }
            if let cost = record.cost {
                usage.cost += cost
                usage.costAvailable = true
            }
            if let byok = record.byokCost {
                usage.byokCost += byok
                usage.byokAvailable = true
            }
            usage.lastUpdated = max(usage.lastUpdated, record.updatedAt)
            grouped[key] = usage
        }
        return grouped.values.sorted { first, second in
            if first.cost != second.cost { return first.cost > second.cost }
            return first.model < second.model
        }
    }

    public static func forecastMonthSpend(
        monthToDate: Decimal,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> Decimal? {
        let elapsed = CalendarDay.daysElapsedInMonth(now: now, timeZone: timeZone, calendar: calendar)
        let total = CalendarDay.daysInMonth(now: now, timeZone: timeZone, calendar: calendar)
        guard elapsed > 0, total > 0 else { return nil }
        return monthToDate * Decimal(total) / Decimal(elapsed)
    }
}

public struct ModelUsage: Identifiable, Equatable {
    public var accountId: String
    public var accountName: String
    public var model: String
    public var currency: String?
    public var promptTokens: Int
    public var completionTokens: Int
    public var reasoningTokens: Int
    public var cachedTokens: Int
    public var requests: Int
    public var cost: Decimal
    public var byokCost: Decimal
    public var promptAvailable: Bool
    public var completionAvailable: Bool
    public var reasoningAvailable: Bool
    public var cachedAvailable: Bool
    public var requestsAvailable: Bool
    public var costAvailable: Bool
    public var byokAvailable: Bool
    public var lastUpdated: Date
    public var source: String

    public var id: String { "\(accountId)|\(model)|\(currency ?? "")" }
    public var totalTokens: Int { promptTokens + completionTokens }
    public var tokensAvailable: Bool { promptAvailable || completionAvailable }
}
