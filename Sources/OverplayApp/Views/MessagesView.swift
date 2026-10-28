import SwiftUI
import OverplayCore

struct MessagesView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""
    @State private var typeFilter: MessageTypeFilter = .all
    @State private var accountFilter: String?
    @State private var statusFilter: MessageStatusFilter = .all
    @State private var timeFilter: MessageTimeFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionCard(
                title: "消息汇总",
                subtitle: summary,
                isDemo: model.isDemo
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜索账户 / 类型 / 数值 / 阈值…", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                        if filtersActive {
                            Button("清除筛选") { resetFilters() }
                                .buttonStyle(.link)
                        }
                    }
                    HStack(spacing: 14) {
                        Picker("类型", selection: $typeFilter) {
                            ForEach(MessageTypeFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.menu)
                        Picker("账户", selection: $accountFilter) {
                            Text("全部账户").tag(String?.none)
                            ForEach(accountOptions, id: \.id) { option in
                                Text(option.name).tag(Optional(option.id))
                            }
                        }
                        .pickerStyle(.menu)
                        Picker("状态", selection: $statusFilter) {
                            ForEach(MessageStatusFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.menu)
                        Picker("时间", selection: $timeFilter) {
                            ForEach(MessageTimeFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.menu)
                        Spacer()
                        Text("显示 \(filteredAlerts.count) / \(model.alerts.count) 条")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if model.alerts.isEmpty {
                SectionCard(isDemo: model.isDemo) {
                    EmptyStateView(
                        symbol: "tray",
                        title: "暂无消息",
                        message: "预算、余额、同步失败、凭据失效和数据过期告警会汇总在这里。"
                    )
                }
            } else if filteredAlerts.isEmpty {
                SectionCard(isDemo: model.isDemo) {
                    EmptyStateView(
                        symbol: "line.3.horizontal.decrease.circle",
                        title: "没有匹配的消息",
                        message: "试试清除筛选或调整关键词。"
                    ) {
                        Button("清除筛选") { resetFilters() }
                    }
                }
            } else {
                SectionCard(isDemo: model.isDemo) {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredAlerts.enumerated()), id: \.element.id) { index, alert in
                            AlertRowView(
                                alert: alert,
                                isDemo: model.isDemo,
                                onAcknowledge: { model.acknowledge(alert) }
                            )
                            if index < filteredAlerts.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                if model.alerts.count >= 200 {
                    Text("最多显示最近 200 条消息；完整记录保存在本地数据库。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("顶部提示倒计时结束后会归档到这里；关闭顶部提示不会删除消息。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var summary: String {
        if model.alerts.isEmpty {
            return "暂无消息"
        }
        var parts = ["共 \(model.alerts.count) 条", "未确认 \(model.unacknowledgedAlerts.count) 条"]
        if filtersActive {
            parts.append("筛选后 \(filteredAlerts.count) 条")
        }
        return parts.joined(separator: " · ")
    }

    private var filteredAlerts: [AlertEvent] {
        model.alerts
            .filter { alert in
                typeFilter.matches(alert.kind)
                    && statusFilter.matches(alert)
                    && (accountFilter.map { $0 == alert.accountId } ?? true)
                    && timeFilter.matches(alert.firedAt, now: model.now)
                    && matchesSearch(alert)
            }
            .sorted { $0.firedAt > $1.firedAt }
    }

    private var accountOptions: [(id: String, name: String)] {
        var seen: [String: String] = [:]
        for alert in model.alerts {
            seen[alert.accountId] = alert.accountName
        }
        return seen.map { (id: $0.key, name: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private var filtersActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || typeFilter != .all
            || accountFilter != nil
            || statusFilter != .all
            || timeFilter != .all
    }

    private func matchesSearch(_ alert: AlertEvent) -> Bool {
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

    private func resetFilters() {
        searchText = ""
        typeFilter = .all
        accountFilter = nil
        statusFilter = .all
        timeFilter = .all
    }
}

private enum MessageTypeFilter: String, CaseIterable, Identifiable {
    case all
    case budget
    case balance
    case sync
    case credential
    case stale

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部类型"
        case .budget: return "预算"
        case .balance: return "余额"
        case .sync: return "同步失败"
        case .credential: return "凭据"
        case .stale: return "数据过期"
        }
    }

    func matches(_ kind: AlertKind) -> Bool {
        switch self {
        case .all: return true
        case .budget: return kind == .budgetWarning || kind == .budgetExceeded
        case .balance: return kind == .balanceLow
        case .sync: return kind == .syncFailed
        case .credential: return kind == .credentialInvalid
        case .stale: return kind == .dataStale
        }
    }
}

private enum MessageStatusFilter: String, CaseIterable, Identifiable {
    case all
    case unread
    case read

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部状态"
        case .unread: return "未确认"
        case .read: return "已确认"
        }
    }

    func matches(_ alert: AlertEvent) -> Bool {
        switch self {
        case .all: return true
        case .unread: return !alert.acknowledged
        case .read: return alert.acknowledged
        }
    }
}

private enum MessageTimeFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部时间"
        case .today: return "今天"
        case .week: return "近 7 天"
        case .month: return "近 30 天"
        }
    }

    func matches(_ date: Date, now: Date) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            return Calendar.current.isDate(date, inSameDayAs: now)
        case .week:
            return date >= now.addingTimeInterval(-7 * 86_400)
        case .month:
            return date >= now.addingTimeInterval(-30 * 86_400)
        }
    }
}
