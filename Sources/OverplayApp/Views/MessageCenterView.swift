import SwiftUI
import OverplayCore

/// 消息中心面板：从顶部消息或基础信息进入，不占用独立 Tab。
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
                    Text(L10n.t("messages.6ef1e2d287")).font(.title3.weight(.semibold))
                    if model.isDemo { DemoTag() }
                }
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(L10n.t("messages.beb9ea28db"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button(L10n.t("common.close")) { dismiss() }
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
                    TextField(L10n.t("messages.0abed08677"), text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    if filtersActive {
                        Button(L10n.t("messages.4bbc4e5fd9"), action: resetFilters)
                            .buttonStyle(.link)
                    }
                }
                HStack(spacing: 14) {
                    Picker(L10n.t("messages.e4e46c7235"), selection: $typeFilter) {
                        ForEach(MessageTypeFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker(L10n.t("core.csv.c3d92b20c8"), selection: $accountFilter) {
                        Text(L10n.t("messages.c5e5d57837")).tag(String?.none)
                        ForEach(accountOptions) { option in
                            Text(option.name).tag(Optional(option.id))
                        }
                    }
                    .pickerStyle(.menu)
                    Picker(L10n.t("messages.62e951a692"), selection: $statusFilter) {
                        ForEach(MessageStatusFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker(L10n.t("messages.89b4aa6364"), selection: $timeFilter) {
                        ForEach(MessageTimeFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Text(L10n.f("messages.930635c27e", filteredAlerts.count, model.alerts.count))
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
                    title: L10n.t("messages.30dfbcb488"),
                    message: L10n.t("messages.796532a3c4")
                )
            }
        } else if filteredAlerts.isEmpty {
            SectionCard(isDemo: model.isDemo) {
                EmptyStateView(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: L10n.t("messages.bcc3236928"),
                    message: L10n.t("messages.d9f404ddc2")
                ) {
                    Button(L10n.t("messages.4bbc4e5fd9"), action: resetFilters)
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
                Text(L10n.t("messages.9587aaaeed"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(L10n.t("messages.f5e6f09a3b"))
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
            return L10n.t("messages.30dfbcb488")
        }
        var parts = [
            L10n.f("messages.c3ba901cd9", model.alerts.count),
            L10n.f("messages.af497fcb34", model.unacknowledgedAlertCount)
        ]
        if filtersActive {
            parts.append(L10n.f("messages.2eaf5c376d", filteredAlerts.count))
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
