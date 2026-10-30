import Foundation

public enum MessageTypeFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case budget
    case balance
    case threshold
    case sync
    case credential
    case stale

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "全部类型"
        case .budget: return "预算"
        case .balance: return "余额"
        case .threshold: return "告警线"
        case .sync: return "同步失败"
        case .credential: return "凭据"
        case .stale: return "数据过期"
        }
    }

    public func matches(_ kind: AlertKind) -> Bool {
        switch self {
        case .all: return true
        case .budget: return kind == .budgetWarning || kind == .budgetExceeded
        case .balance: return kind == .balanceLow
        case .threshold: return kind == .lineWarning || kind == .lineCritical
        case .sync: return kind == .syncFailed
        case .credential: return kind == .credentialInvalid
        case .stale: return kind == .dataStale
        }
    }
}

public enum MessageStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case unread
    case read

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "全部状态"
        case .unread: return "未确认"
        case .read: return "已确认"
        }
    }

    public func matches(_ alert: AlertEvent) -> Bool {
        switch self {
        case .all: return true
        case .unread: return !alert.acknowledged
        case .read: return alert.acknowledged
        }
    }
}

public enum MessageTimeFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case today
    case week
    case month

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "全部时间"
        case .today: return "今天"
        case .week: return "近 7 天"
        case .month: return "近 30 天"
        }
    }

    public func matches(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .week:
            return date >= now.addingTimeInterval(-7 * 86_400)
        case .month:
            return date >= now.addingTimeInterval(-30 * 86_400)
        }
    }
}

public struct MessageFilterCriteria: Equatable, Sendable {
    public var searchText: String
    public var type: MessageTypeFilter
    public var accountId: String?
    public var status: MessageStatusFilter
    public var time: MessageTimeFilter

    public init(
        searchText: String = "",
        type: MessageTypeFilter = .all,
        accountId: String? = nil,
        status: MessageStatusFilter = .all,
        time: MessageTimeFilter = .all
    ) {
        self.searchText = searchText
        self.type = type
        self.accountId = accountId
        self.status = status
        self.time = time
    }

    public var isActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || type != .all
            || accountId != nil
            || status != .all
            || time != .all
    }
}

public struct MessageAccountOption: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum MessageCenter {
    public static func unacknowledgedCount(_ alerts: [AlertEvent]) -> Int {
        alerts.lazy.filter { !$0.acknowledged }.count
    }

    public static func accountOptions(_ alerts: [AlertEvent]) -> [MessageAccountOption] {
        var seen: [String: String] = [:]
        for alert in alerts where seen[alert.accountId] == nil {
            seen[alert.accountId] = alert.accountName
        }
        return seen.map { MessageAccountOption(id: $0.key, name: $0.value) }
            .sorted { $0.name < $1.name }
    }

    public static func filteredAlerts(
        _ alerts: [AlertEvent],
        criteria: MessageFilterCriteria,
        now: Date,
        calendar: Calendar = .current
    ) -> [AlertEvent] {
        alerts
            .filter { alert in
                criteria.type.matches(alert.kind)
                    && criteria.status.matches(alert)
                    && (criteria.accountId.map { $0 == alert.accountId } ?? true)
                    && criteria.time.matches(alert.firedAt, now: now, calendar: calendar)
                    && matchesSearch(alert, searchText: criteria.searchText)
            }
            .sorted { $0.firedAt > $1.firedAt }
    }

    public static func matchesSearch(_ alert: AlertEvent, searchText: String) -> Bool {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return [
            alert.kind.title,
            alert.accountName,
            alert.value,
            alert.threshold,
            alert.metric
        ].contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}
