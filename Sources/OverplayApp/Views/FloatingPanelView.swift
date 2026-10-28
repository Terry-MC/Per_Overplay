import SwiftUI
import OverplayCore

struct FloatingPanelView: View {
    @ObservedObject var model: AppModel
    let density: FloatingDensity
    let onClose: () -> Void
    let onToggleDensity: () -> Void
    let onCollapse: () -> Void
    let onOpenMain: () -> Void
    let onOpenMessages: () -> Void

    private var summary: FloatingSummary {
        FloatingSummaryBuilder.make(
            accounts: model.accounts,
            usageRecords: model.usageRecords,
            balances: model.balances,
            quotas: model.quotas,
            alerts: model.alerts,
            now: model.now
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    globalSummary
                    accountsSection
                    footer
                }
                .padding(14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(nil)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.headline)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("Overplay").font(.headline.weight(.bold))
                    if model.isDemo { DemoTag() }
                }
                Text(headerSubtitle)
                    .font(.caption2)
                    .foregroundStyle(headerIsStale ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .help(headerSubtitle)
            }
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                panelButton(
                    symbol: "xmark",
                    help: "退出 Overplay",
                    action: onClose
                )
                panelButton(
                    symbol: density == .expanded ? "chevron.up" : "chevron.down",
                    help: density == .expanded ? "折叠为压缩视图" : "展开为完整视图",
                    action: onToggleDensity
                )
                panelButton(
                    symbol: "minus.circle",
                    help: "收起悬浮窗到菜单栏",
                    action: onCollapse
                )
                panelButton(
                    symbol: "arrow.up.right.square",
                    help: "打开完整版主窗口",
                    action: onOpenMain
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var headerSubtitle: String {
        var parts: [String] = []
        if model.accounts.isEmpty {
            parts.append("暂无账户")
        } else {
            parts.append("\(summary.activeAccountCount) 个启用账户")
            if summary.disabledAccountCount > 0 {
                parts.append("\(summary.disabledAccountCount) 个禁用")
            }
        }
        if let lastSync = summary.lastSyncAt {
            parts.append("更新 \(DateFormatters.shortTime.string(from: lastSync))")
        } else {
            parts.append("尚未同步")
        }
        return parts.joined(separator: " · ")
    }

    private var headerIsStale: Bool {
        guard let lastSync = summary.lastSyncAt else { return false }
        return model.now.timeIntervalSince(lastSync) > model.settings.refreshInterval * 2
    }

    private func panelButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var globalSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Text("今日费用")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        if !summary.todayStatus.isActual, let icon = summary.todayStatus.iconName {
                            Image(systemName: icon)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(summary.todayStatus.tint)
                                .help(summary.todayStatus.reason ?? "")
                        }
                    }
                    if summary.todayStatus.isActual, !summary.todayCosts.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            ForEach(summary.todayCosts.keys.sorted(), id: \.self) { currency in
                                Text(Money.formatCost(summary.todayCosts[currency] ?? 0, currency: currency))
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                            }
                        }
                    } else {
                        HStack(spacing: 5) {
                            Text(summary.todayStatus.isMissing ? "今日无记录" : summary.todayStatus.emptyLabel)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Image(systemName: summary.todayStatus.iconName ?? "tray")
                                .font(.caption)
                                .foregroundStyle(summary.todayStatus.tint)
                        }
                        .help(summary.todayStatus.reason ?? summary.todayStatus.emptyLabel)
                    }
                }
                Spacer(minLength: 0)
                alertSummary
            }
            Divider().opacity(0.45)
            HStack(alignment: .top, spacing: 0) {
                snapshotColumn(
                    title: "官方余额",
                    symbol: "creditcard",
                    status: summary.balancesStatus,
                    rows: balanceRows
                )
                Divider().frame(height: 52).padding(.horizontal, 10)
                snapshotColumn(
                    title: "官方额度",
                    symbol: "gauge.with.dots.needle.50percent",
                    status: summary.creditsStatus,
                    rows: creditRows
                )
                Divider().frame(height: 52).padding(.horizontal, 10)
                tokenColumn
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private var alertSummary: some View {
        Group {
            if summary.unacknowledgedAlertCount > 0 {
                Button(action: onOpenMessages) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Label(
                            "\(summary.unacknowledgedAlertCount)",
                            systemImage: summary.criticalAlertCount > 0
                                ? "exclamationmark.triangle.fill"
                                : "bell.badge"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(summary.criticalAlertCount > 0 ? Color.red : Color.orange)
                        Text(summary.criticalAlertCount > 0 ? "警戒 / 未确认" : "未确认")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("打开消息中心")
                .accessibilityLabel("未确认消息 \(summary.unacknowledgedAlertCount) 条")
            } else {
                Label("无告警", systemImage: "checkmark.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func snapshotColumn(
        title: String,
        symbol: String,
        status: DataStatus,
        rows: [(String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                if !status.isActual, let icon = status.iconName {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(status.tint)
                }
            }
            if status.isActual, !rows.isEmpty {
                ForEach(Array(rows.prefix(2).enumerated()), id: \.offset) { _, row in
                    Text(row.1)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .help(row.0)
                }
            } else {
                Text(status.isActual ? "无数据" : status.emptyLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(status.reason ?? "")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tokenColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: "number")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text("Token / 请求")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                if !summary.tokenStatus.isActual, let icon = summary.tokenStatus.iconName {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(summary.tokenStatus.tint)
                }
            }
            if summary.tokenStatus.isActual {
                Text("\(Money.formatCompactInteger(summary.tokenTotal)) tokens")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text("覆盖 \(summary.tokenAccounts)/\(summary.totalAccounts)")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                Text(summary.requestsAvailable
                     ? "\(Money.formatCompactInteger(summary.requestCount)) 次请求"
                     : "请求数未提供")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            } else {
                Text(summary.tokenStatus.emptyLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .help(summary.tokenStatus.reason ?? "")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var balanceRows: [(String, String)] {
        summary.balances.keys.sorted().map { currency in
            (currency, Money.formatBalance(summary.balances[currency] ?? 0, currency: currency))
        }
    }

    private var creditRows: [(String, String)] {
        summary.creditsRemaining.keys.sorted().map { currency in
            (currency, Money.formatBalance(summary.creditsRemaining[currency] ?? 0, currency: currency))
        }
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("账户").font(.subheadline.weight(.semibold))
                Text("\(model.accounts.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.refreshAll()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .disabled(model.isDemo || model.accounts.isEmpty)
                .help(model.isDemo ? "演示模式不发起网络请求" : "刷新全部账户")
            }
            if model.accounts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("暂无监控账户").font(.callout.weight(.semibold))
                    Text("在完整版中添加 DeepSeek 或 OpenRouter 账户后，悬浮窗会显示今日费用、余额与告警。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("打开完整版", action: onOpenMain)
                        .buttonStyle(.link)
                        .font(.caption)
                }
                .padding(.vertical, 12)
            } else {
                if summary.activeAccountCount == 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                        Text("所有账户均已禁用；后台不会刷新或告警。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("打开完整版", action: onOpenMain)
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.orange.opacity(0.08))
                    )
                }
                LazyVStack(spacing: 6) {
                    ForEach(summary.rows) { row in
                        accountRow(row)
                    }
                }
            }
        }
    }

    private func accountRow(_ row: FloatingAccountRow) -> some View {
        VStack(alignment: .leading, spacing: density == .expanded ? 5 : 3) {
            HStack(spacing: 7) {
                ProviderMark(provider: row.provider)
                    .scaleEffect(0.72)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(row.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    HStack(spacing: 5) {
                        primaryStatusLabel(row.primaryStatus)
                        if row.unacknowledgedAlerts > 0 {
                            Label("\(row.unacknowledgedAlerts)", systemImage: row.criticalAlerts > 0 ? "exclamationmark.triangle.fill" : "bell")
                                .foregroundStyle(row.criticalAlerts > 0 ? Color.red : Color.orange)
                        }
                        if !row.enabled {
                            Text("已禁用").foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 9))
                }
                Spacer(minLength: 2)
                Button {
                    if let account = model.accounts.first(where: { $0.id == row.id }) {
                        model.refresh(account: account)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(model.isDemo || !row.enabled)
                .help(model.isDemo ? "演示模式不发起网络请求" : "刷新 \(row.name)")
                .accessibilityLabel("刷新 \(row.name)")
            }

            if row.primaryStatus.isActual, !row.primaryLines.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    ForEach(Array(row.primaryLines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            if row.primaryLines.count > 1 {
                                Text(line.currency)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            Text(Money.formatBalance(line.value, currency: line.currency))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
            } else {
                DataValueLabel(
                    text: row.primaryStatus.emptyLabel,
                    status: row.primaryStatus,
                    font: .caption.weight(.medium)
                )
                .help(row.primaryStatus.reason ?? "")
            }

            if density == .expanded {
                if row.secondaryStatus != nil, !row.secondaryLines.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(row.secondaryLines.enumerated()), id: \.offset) { _, line in
                            Text("\(line.label) \(Money.formatBalance(line.value, currency: line.currency))")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        if let ratio = row.budgetRatio {
                            ProgressView(value: min(max(NSDecimalNumber(decimal: ratio).doubleValue / 100, 0), 1))
                                .frame(width: 48)
                                .tint(ratio >= 100 ? .red : ratio >= 80 ? .orange : .green)
                        }
                    }
                }
                if let error = row.errorSummary {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                if let last = row.lastSuccessAt {
                    Text("更新 \(DateFormatters.shortTime.string(from: last))")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, density == .expanded ? 7 : 5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func primaryStatusLabel(_ status: DataStatus) -> some View {
        HStack(spacing: 2) {
            Image(systemName: status.isActual ? "checkmark.circle.fill" : (status.iconName ?? "tray"))
                .foregroundStyle(status.isActual ? Color.green : status.tint)
            Text(status.isActual ? "正常" : status.emptyLabel)
                .foregroundStyle(status.isActual ? Color.secondary : status.tint)
        }
        .help(status.reason ?? "")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("打开完整版", action: onOpenMain)
                .buttonStyle(.link)
                .font(.caption)
            Spacer()
            Text("\(model.settings.refreshIntervalMinutes) 分钟自动刷新")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

}
