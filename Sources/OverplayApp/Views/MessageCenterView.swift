import SwiftUI
import OverplayCore

/// 消息中心面板：从顶部消息或总览进入，不占用独立 Tab。
struct MessageCenterView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var typeFilter: MessageTypeFilter = .all
    @State private var accountFilter: String?
    @State private var statusFilter: MessageStatusFilter = .all
    @State private var timeFilter: MessageTimeFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filterCard
                    content
                }
                .padding(20)
            }
        }
        .frame(width: 920, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("消息中心").font(.title3.weight(.semibold))
                    if model.isDemo { DemoTag() }
                }
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("顶部提示最多同时显示 3 条")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button("关闭") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private var filterCard: some View {
        SectionCard(isDemo: model.isDemo) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索账户 / 类型 / 数值 / 阈值…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    if filtersActive {
                        Button("清除筛选", action: resetFilters)
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
                        ForEach(accountOptions) { option in
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
    }

    @ViewBuilder
    private var content: some View {
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
                    Button("清除筛选", action: resetFilters)
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

    private var criteria: MessageFilterCriteria {
        MessageFilterCriteria(
            searchText: searchText,
            type: typeFilter,
            accountId: accountFilter,
            status: statusFilter,
            time: timeFilter
        )
    }

    private var filteredAlerts: [AlertEvent] {
        MessageCenter.filteredAlerts(model.alerts, criteria: criteria, now: model.now)
    }

    private var accountOptions: [MessageAccountOption] {
        MessageCenter.accountOptions(model.alerts)
    }

    private var filtersActive: Bool {
        criteria.isActive
    }

    private var summary: String {
        if model.alerts.isEmpty {
            return "暂无消息"
        }
        var parts = [
            "共 \(model.alerts.count) 条",
            "未确认 \(model.unacknowledgedAlertCount) 条"
        ]
        if filtersActive {
            parts.append("筛选后 \(filteredAlerts.count) 条")
        }
        return parts.joined(separator: " · ")
    }

    private func resetFilters() {
        searchText = ""
        typeFilter = .all
        accountFilter = nil
        statusFilter = .all
        timeFilter = .all
    }
}
