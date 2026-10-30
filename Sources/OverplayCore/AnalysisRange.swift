import Foundation

// MARK: - Shared analysis range

public enum AnalysisRangePreset: String, CaseIterable, Identifiable, Sendable {
    case today
    case thisWeek
    case thisMonth
    case thisYear
    case last7Days
    case last30Days
    case last90Days
    case custom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .today: return "今天"
        case .thisWeek: return "本周"
        case .thisMonth: return "本月"
        case .thisYear: return "今年"
        case .last7Days: return "近 7 天"
        case .last30Days: return "近 30 天"
        case .last90Days: return "近 90 天"
        case .custom: return "自定义"
        }
    }

    public var isCustom: Bool { self == .custom }

    public var isNatural: Bool {
        switch self {
        case .today, .thisWeek, .thisMonth, .thisYear:
            return true
        default:
            return false
        }
    }
}

public enum AnalysisRangeError: Error, Equatable, Sendable {
    case startAfterEnd
    case exceedsRetention(days: Int)

    public var message: String {
        switch self {
        case .startAfterEnd:
            return "开始时间不能晚于结束时间"
        case .exceedsRetention(let days):
            return "自定义区间超出本地 \(days) 天保留期"
        }
    }
}

public struct AnalysisRange: Equatable, Sendable {
    public let preset: AnalysisRangePreset
    public let start: Date
    public let end: Date
    public let dayRange: DayRange
    public let isCustom: Bool

    public init(
        preset: AnalysisRangePreset,
        start: Date,
        end: Date,
        dayRange: DayRange,
        isCustom: Bool
    ) {
        self.preset = preset
        self.start = start
        self.end = end
        self.dayRange = dayRange
        self.isCustom = isCustom
    }

    public var interval: DateInterval {
        DateInterval(start: start, end: end)
    }

    public var label: String {
        if isCustom {
            let formatter = Self.customFormatter
            return "\(formatter.string(from: start)) 至 \(formatter.string(from: end))（本机时区）"
        }
        return "\(preset.label) · \(dayRange.label)"
    }

    /// 自然单位按本机时区计算；厂商用量记录仍按其 UTC 日桶存储。
    public static func make(
        preset: AnalysisRangePreset,
        customStart: Date = Date(),
        customEnd: Date = Date(),
        now: Date = Date(),
        timeZone: TimeZone = .current,
        calendar baseCalendar: Calendar = .current
    ) throws -> AnalysisRange {
        var calendar = baseCalendar
        calendar.timeZone = timeZone
        switch preset {
        case .custom:
            guard customStart <= customEnd else {
                throw AnalysisRangeError.startAfterEnd
            }
            let retentionStart = calendar.date(byAdding: .day, value: -365, to: now) ?? now
            if customStart < retentionStart {
                throw AnalysisRangeError.exceedsRetention(days: 365)
            }
            return AnalysisRange(
                preset: preset,
                start: customStart,
                end: customEnd,
                dayRange: dayRange(start: customStart, end: customEnd, timeZone: timeZone, calendar: calendar),
                isCustom: true
            )
        case .today:
            let start = calendar.startOfDay(for: now)
            let today = CalendarDay.string(for: now, timeZone: timeZone, calendar: calendar)
            return AnalysisRange(
                preset: preset,
                start: start,
                end: now,
                dayRange: DayRange(startDay: today, endDay: today),
                isCustom: false
            )
        case .thisWeek:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start
                ?? calendar.startOfDay(for: now)
            return AnalysisRange(
                preset: preset,
                start: start,
                end: now,
                dayRange: dayRange(start: start, end: now, timeZone: timeZone, calendar: calendar),
                isCustom: false
            )
        case .thisMonth:
            let start = calendar.dateInterval(of: .month, for: now)?.start
                ?? calendar.startOfDay(for: now)
            return AnalysisRange(
                preset: preset,
                start: start,
                end: now,
                dayRange: dayRange(start: start, end: now, timeZone: timeZone, calendar: calendar),
                isCustom: false
            )
        case .thisYear:
            let start = calendar.dateInterval(of: .year, for: now)?.start
                ?? calendar.startOfDay(for: now)
            return AnalysisRange(
                preset: preset,
                start: start,
                end: now,
                dayRange: dayRange(start: start, end: now, timeZone: timeZone, calendar: calendar),
                isCustom: false
            )
        case .last7Days, .last30Days, .last90Days:
            let days = preset == .last7Days ? 7 : preset == .last30Days ? 30 : 90
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
            return AnalysisRange(
                preset: preset,
                start: start,
                end: now,
                dayRange: CalendarDay.range(
                    preset: AnalysisPreset(rawValue: days) ?? .thirty,
                    now: now,
                    timeZone: timeZone,
                    calendar: calendar
                ),
                isCustom: false
            )
        }
    }

    private static func dayRange(
        start: Date,
        end: Date,
        timeZone: TimeZone,
        calendar: Calendar
    ) -> DayRange {
        let effectiveEnd = end > start ? end.addingTimeInterval(-0.001) : end
        return DayRange(
            startDay: CalendarDay.string(for: start, timeZone: timeZone, calendar: calendar),
            endDay: CalendarDay.string(for: effectiveEnd, timeZone: timeZone, calendar: calendar)
        )
    }

    private static var customFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.timeZone = .current
        return formatter
    }
}

// MARK: - Granularity

public enum AnalysisGranularity: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case minute
    case hour
    case day
    case month
    case year

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .automatic: return "自动"
        case .minute: return "分"
        case .hour: return "时"
        case .day: return "日"
        case .month: return "月"
        case .year: return "年"
        }
    }
}

public enum AnalysisGranularitySupport {
    /// 用量记录只存厂商 UTC 日桶，因此 token / 费用 / 请求数不能提供分钟或小时点。
    /// 余额快照带真实时间戳，可以按分钟 / 小时 / 日 / 月 / 年聚合。
    public static func available(
        for provider: ProviderKind,
        isDemo: Bool
    ) -> [AnalysisGranularity] {
        if provider == .deepseek {
            return [.automatic, .minute, .hour, .day, .month, .year]
        }
        if isDemo {
            return [.automatic, .day, .month, .year]
        }
        switch provider {
        case .openrouter:
            return [.automatic, .day, .month, .year]
        default:
            return [.automatic, .day, .month, .year]
        }
    }

    public static func supports(
        _ granularity: AnalysisGranularity,
        provider: ProviderKind,
        isDemo: Bool
    ) -> Bool {
        available(for: provider, isDemo: isDemo).contains(granularity)
    }
}

// MARK: - Provider totals and coverage

public struct ProviderUsageTotals: Equatable, Sendable {
    public var accountId: String
    public var accountName: String
    public var provider: ProviderKind
    public var recordCount: Int
    public var tokenRecordCount: Int
    public var totalTokens: Int
    public var promptTokens: Int
    public var completionTokens: Int
    public var reasoningTokens: Int
    public var cachedTokens: Int
    public var requests: Int
    public var costs: [String: Decimal]
    public var tokensAvailable: Bool
    public var requestsAvailable: Bool
    public var costAvailable: Bool
    public var firstDay: String?
    public var lastDay: String?
    public var lastUpdated: Date?

    public init(
        accountId: String,
        accountName: String,
        provider: ProviderKind,
        recordCount: Int = 0,
        tokenRecordCount: Int = 0,
        totalTokens: Int = 0,
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        reasoningTokens: Int = 0,
        cachedTokens: Int = 0,
        requests: Int = 0,
        costs: [String: Decimal] = [:],
        tokensAvailable: Bool = false,
        requestsAvailable: Bool = false,
        costAvailable: Bool = false,
        firstDay: String? = nil,
        lastDay: String? = nil,
        lastUpdated: Date? = nil
    ) {
        self.accountId = accountId
        self.accountName = accountName
        self.provider = provider
        self.recordCount = recordCount
        self.tokenRecordCount = tokenRecordCount
        self.totalTokens = totalTokens
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
        self.cachedTokens = cachedTokens
        self.requests = requests
        self.costs = costs
        self.tokensAvailable = tokensAvailable
        self.requestsAvailable = requestsAvailable
        self.costAvailable = costAvailable
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.lastUpdated = lastUpdated
    }
}

public struct TokenCoverage: Equatable, Sendable {
    public var totalAccounts: Int
    public var accountsWithTokens: Int
    public var totalProviders: Int
    public var providersWithTokens: Int
    public var accountsWithCost: Int
    public var accountsWithRequests: Int

    public init(
        totalAccounts: Int,
        accountsWithTokens: Int,
        totalProviders: Int,
        providersWithTokens: Int,
        accountsWithCost: Int,
        accountsWithRequests: Int
    ) {
        self.totalAccounts = totalAccounts
        self.accountsWithTokens = accountsWithTokens
        self.totalProviders = totalProviders
        self.providersWithTokens = providersWithTokens
        self.accountsWithCost = accountsWithCost
        self.accountsWithRequests = accountsWithRequests
    }
}

public enum ProviderAnalysisMetrics {
    public static func totals(
        records: [UsageRecord],
        account: Account
    ) -> ProviderUsageTotals {
        var result = ProviderUsageTotals(
            accountId: account.id,
            accountName: account.displayName,
            provider: account.provider
        )
        for record in records where record.accountId == account.id {
            result.recordCount += 1
            result.firstDay = min(result.firstDay ?? record.day, record.day)
            result.lastDay = max(result.lastDay ?? record.day, record.day)
            result.lastUpdated = max(result.lastUpdated ?? record.updatedAt, record.updatedAt)

            if let prompt = record.promptTokens {
                result.promptTokens += prompt
                result.tokensAvailable = true
            }
            if let completion = record.completionTokens {
                result.completionTokens += completion
                result.tokensAvailable = true
            }
            if record.promptTokens != nil || record.completionTokens != nil {
                result.totalTokens += record.totalTokens ?? 0
                result.tokenRecordCount += 1
            }
            if let reasoning = record.reasoningTokens {
                result.reasoningTokens += reasoning
            }
            if let cached = record.cachedTokens {
                result.cachedTokens += cached
            }
            if let requests = record.requests {
                result.requests += requests
                result.requestsAvailable = true
            }
            if let cost = record.cost, let currency = record.currency {
                result.costs[currency, default: 0] += cost
                result.costAvailable = true
            }
        }
        return result
    }

    public static func coverage(
        accounts: [Account],
        records: [UsageRecord]
    ) -> TokenCoverage {
        let accountIds = Set(accounts.map(\.id))
        let scoped = records.filter { accountIds.contains($0.accountId) }
        let tokenAccountIds = Set(scoped.filter {
            $0.promptTokens != nil || $0.completionTokens != nil
        }.map(\.accountId))
        let costAccountIds = Set(scoped.filter { $0.cost != nil && $0.currency != nil }.map(\.accountId))
        let requestAccountIds = Set(scoped.filter { $0.requests != nil }.map(\.accountId))
        let providers = Set(accounts.map(\.provider))
        return TokenCoverage(
            totalAccounts: accounts.count,
            accountsWithTokens: tokenAccountIds.count,
            totalProviders: providers.count,
            providersWithTokens: Set(scoped.filter {
                $0.promptTokens != nil || $0.completionTokens != nil
            }.map(\.provider)).count,
            accountsWithCost: costAccountIds.count,
            accountsWithRequests: requestAccountIds.count
        )
    }

    public static func coverageLabel(_ coverage: TokenCoverage) -> String {
        "\(coverage.accountsWithTokens) / \(coverage.totalAccounts) 个账户提供 token 数据"
    }
}

// MARK: - Chart math

public enum UsageMetric: String, CaseIterable, Identifiable, Sendable {
    case tokens
    case cost
    case requests

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .tokens: return "Token"
        case .cost: return "费用"
        case .requests: return "请求数"
        }
    }
}

public struct UsageChartPoint: Identifiable, Equatable, Sendable {
    public var key: String
    public var value: Double
    public var segment: Int

    public var id: String { "\(segment)|\(key)" }

    public init(key: String, value: Double, segment: Int) {
        self.key = key
        self.value = value
        self.segment = segment
    }
}

public struct BalanceChartPoint: Identifiable, Equatable, Sendable {
    public var currency: String
    public var date: Date
    public var value: Double

    public var id: String { "\(currency)|\(date.timeIntervalSince1970)" }

    public init(currency: String, date: Date, value: Double) {
        self.currency = currency
        self.date = date
        self.value = value
    }
}

public enum AnalysisChartMath {
    /// 把日级记录聚合成图表值。分钟 / 小时不受支持，调用方应先检查能力矩阵。
    public static func dailyValues(
        records: [UsageRecord],
        metric: UsageMetric,
        currency: String? = nil
    ) -> [String: Double] {
        var values: [String: Double] = [:]
        for record in records {
            if let currency, record.currency != currency { continue }
            switch metric {
            case .tokens:
                if let total = record.totalTokens {
                    values[record.day, default: 0] += Double(total)
                }
            case .cost:
                if let cost = record.cost {
                    values[record.day, default: 0] += NSDecimalNumber(decimal: cost).doubleValue
                }
            case .requests:
                if let requests = record.requests {
                    values[record.day, default: 0] += Double(requests)
                }
            }
        }
        return values
    }

    /// 按共享时间范围内的完整日期序列切段；缺失日期不补 0，而是断开折线。
    public static func segments(
        days: [String],
        values: [String: Double],
        granularity: AnalysisGranularity
    ) -> [[UsageChartPoint]] {
        guard granuleSupportsUsage(granularity) else { return [] }
        var buckets: [String: Double] = [:]
        var order: [String] = []
        for day in days {
            guard let value = values[day] else { continue }
            let key = bucketKey(day: day, granularity: granularity)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: 0] += value
        }
        guard !order.isEmpty else { return [] }

        var segments: [[(key: String, value: Double)]] = []
        var current: [(key: String, value: Double)] = []
        for key in order {
            if let previous = current.last, !areAdjacent(previous.key, key, granularity: granularity) {
                segments.append(current)
                current = []
            }
            current.append((key, buckets[key] ?? 0))
        }
        if !current.isEmpty { segments.append(current) }
        return segments.enumerated().map { segmentIndex, points in
            points.map {
                UsageChartPoint(key: $0.key, value: $0.value, segment: segmentIndex)
            }
        }
    }

    public static func bucketKey(day: String, granularity: AnalysisGranularity) -> String {
        switch granularity {
        case .month:
            return String(day.prefix(7))
        case .year:
            return String(day.prefix(4))
        default:
            return day
        }
    }

    public static func granuleSupportsUsage(_ granularity: AnalysisGranularity) -> Bool {
        switch granularity {
        case .automatic, .day, .month, .year:
            return true
        case .minute, .hour:
            return false
        }
    }

    public static func areAdjacent(
        _ lhs: String,
        _ rhs: String,
        granularity: AnalysisGranularity
    ) -> Bool {
        switch granularity {
        case .month:
            return nextMonth(lhs) == rhs
        case .year:
            return (Int(lhs) ?? 0) + 1 == (Int(rhs) ?? 0)
        default:
            guard let lhsDate = CalendarDay.date(from: lhs, timeZone: CalendarDay.utc) else {
                return false
            }
            return day(after: lhsDate) == rhs
        }
    }

    private static func day(after date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = CalendarDay.utc
        let next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return CalendarDay.string(for: next, timeZone: CalendarDay.utc, calendar: calendar)
    }

    private static func nextMonth(_ key: String) -> String? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let year = parts[0]
        let month = parts[1]
        if month == 12 { return String(format: "%04d-01", year + 1) }
        return String(format: "%04d-%02d", year, month + 1)
    }

    public static func balancePoints(
        snapshots: [BalanceSnapshot],
        granularity: AnalysisGranularity,
        timeZone: TimeZone = .current,
        calendar baseCalendar: Calendar = .current
    ) -> [BalanceChartPoint] {
        var calendar = baseCalendar
        calendar.timeZone = timeZone
        guard granularity != .automatic else {
            return snapshots.map {
                BalanceChartPoint(
                    currency: $0.currency,
                    date: $0.asOf,
                    value: NSDecimalNumber(decimal: $0.total).doubleValue
                )
            }
        }
        var buckets: [String: BalanceSnapshot] = [:]
        for snapshot in snapshots {
            let key = bucketKey(date: snapshot.asOf, granularity: granularity, calendar: calendar)
            if let existing = buckets[key], existing.asOf >= snapshot.asOf { continue }
            buckets[key] = snapshot
        }
        return buckets.values.sorted { $0.asOf < $1.asOf }.map {
            BalanceChartPoint(
                currency: $0.currency,
                date: $0.asOf,
                value: NSDecimalNumber(decimal: $0.total).doubleValue
            )
        }
    }

    public static func bucketKey(
        date: Date,
        granularity: AnalysisGranularity,
        calendar: Calendar
    ) -> String {
        let components: Set<Calendar.Component>
        switch granularity {
        case .minute:
            components = [.year, .month, .day, .hour, .minute]
        case .hour:
            components = [.year, .month, .day, .hour]
        case .day:
            components = [.year, .month, .day]
        case .month:
            components = [.year, .month]
        case .year:
            components = [.year]
        case .automatic:
            components = [.year, .month, .day, .hour, .minute, .second]
        }
        let values = calendar.dateComponents(components, from: date)
        return [
            values.year, values.month, values.day,
            values.hour, values.minute, values.second
        ].map { $0.map(String.init) ?? "-" }.joined(separator: "-")
    }
}
