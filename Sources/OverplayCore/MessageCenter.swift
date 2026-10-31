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
        case .all: return L10n.t("core.messages.fa6968d9f0")
        case .budget: return L10n.t("metric.budget")
        case .balance: return L10n.t("metric.balance")
        case .threshold: return L10n.t("metric.alertLine")
        case .sync: return L10n.t("metric.syncFailure")
        case .credential: return L10n.t("metric.credential")
        case .stale: return L10n.t("metric.stale")
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
        case .all: return L10n.t("core.messages.1a4c26d92d")
        case .unread: return L10n.t("core.messages.0642fa2988")
        case .read: return L10n.t("core.messages.d9fea67ad2")
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
        case .all: return L10n.t("core.messages.2d25878062")
        case .today: return L10n.t("core.messages.17e83cc25e")
        case .week: return L10n.t("core.messages.f297b996de")
        case .month: return L10n.t("core.messages.00a0a58be6")
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
            alert.renderedTitle,
            alert.accountName,
            alert.value,
            alert.threshold,
            alert.renderedValue,
            alert.renderedThreshold,
            alert.metric,
            AlertMetricText.localized(alert.metric)
        ].contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}
