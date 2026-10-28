import SwiftUI
import OverplayCore

struct OverviewView: View {
    @ObservedObject var model: AppModel
    var onEdit: (Account) -> Void
    var onDelete: (Account) -> Void

    private let metricColumns = [GridItem(.adaptive(minimum: 250), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 14) {
                MetricCard(
                    title: "今日费用",
                    valueLines: model.todayCosts.isEmpty ? [] : UIFormat.costLines(model.todayCosts),
                    footnote: "按厂商 UTC 日桶统计；无数据时不显示 0。",
                    symbol: "sun.max",
                    isDemo: model.isDemo
                )
                MetricCard(
                    title: "本月至今费用",
                    valueLines: model.monthCosts.isEmpty ? [] : UIFormat.costLines(model.monthCosts),
                    footnote: "自然月按本机时区；按厂商日桶聚合，分币种展示，不跨币种求和。",
                    symbol: "calendar",
                    isDemo: model.isDemo
                )
                MetricCard(
                    title: "近 30 天 tokens",
                    valueLines: tokenLines,
                    footnote: tokenFootnote,
                    symbol: "number",
                    isDemo: model.isDemo
                )
                MetricCard(
                    title: "官方额度剩余",
                    valueLines: model.officialCreditsRemaining.isEmpty
                        ? [] : UIFormat.costLines(model.officialCreditsRemaining),
                    footnote: "OpenRouter credits（官方）· total_credits − total_usage。",
                    symbol: "gauge.with.dots.needle.50percent",
                    isDemo: model.isDemo
                )
                MetricCard(
                    title: "官方余额",
                    valueLines: model.officialBalances.isEmpty
                        ? [] : UIFormat.costLines(model.officialBalances),
                    footnote: "DeepSeek 余额快照；仅反映官方余额，不代表 token 消耗。",
                    symbol: "creditcard",
                    isDemo: model.isDemo
                )
                MetricCard(
                    title: "本地预算剩余",
                    valueLines: budgetRemainingLines,
                    footnote: "本地预算，不冒充官方额度；无预算或未同步时不计算。",
                    symbol: "target",
                    isDemo: model.isDemo
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("账户")
                        .font(.title3.weight(.semibold))
                    Text("\(model.accounts.count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !model.accounts.isEmpty {
                        Button {
                            model.refreshAll()
                        } label: {
                            Label("刷新全部", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.isDemo)
                    }
                }
                ForEach(model.accounts) { account in
                    AccountCardView(
                        model: model,
                        account: account,
                        onEdit: { onEdit(account) },
                        onDelete: { onDelete(account) }
                    )
                }
            }

            alertsSection
        }
    }

    private var tokenLines: [(String, String?)] {
        let summary = model.tokenSummary
        guard summary.providersWithTokens > 0 else { return [] }
        return [(Money.formatCompactInteger(summary.total), "tokens")]
    }

    private var tokenFootnote: String {
        let summary = model.tokenSummary
        if summary.providersWithTokens == 0 {
            return "厂商未提供 token 数据；不将缺失数据当作 0。"
        }
        return "覆盖 \(summary.providersWithTokens) / \(summary.totalAccounts) 个账户；仅含提供实际 token 数据的厂商。"
    }

    private var budgetRemainingLines: [(String, String?)] {
        var totals: [String: Decimal] = [:]
        for account in model.accounts {
            guard let budget = account.budget,
                  let remaining = model.budgetRemaining(for: account) else { continue }
            totals[budget.currency, default: 0] += remaining
        }
        return totals.keys.sorted().map { code in
            let value = totals[code] ?? 0
            if value < 0 {
                return (Money.formatBalance(-value, currency: code), "已超支")
            }
            return (Money.formatBalance(value, currency: code), "剩余")
        }
    }

    @ViewBuilder
    private var alertsSection: some View {
        SectionCard(
            title: "告警",
            subtitle: model.unacknowledgedAlerts.isEmpty ? "无未确认告警" : "\(model.unacknowledgedAlerts.count) 条未确认",
            isDemo: model.isDemo
        ) {
            if model.unacknowledgedAlerts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("当前没有未确认的告警。预算 / 余额 / 同步异常会记录在此。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(model.unacknowledgedAlerts.prefix(4)) { alert in
                    AlertRowView(
                        alert: alert,
                        isDemo: model.isDemo,
                        onAcknowledge: { model.acknowledge(alert) }
                    )
                    if alert.id != model.unacknowledgedAlerts.prefix(4).last?.id {
                        Divider()
                    }
                }
                if model.unacknowledgedAlerts.count > 4 {
                    Button("查看全部告警") {
                        model.selectedTab = .quota
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}

struct AccountCardView: View {
    @ObservedObject var model: AppModel
    let account: Account
    var onEdit: () -> Void
    var onDelete: () -> Void

    private var health: AccountHealth { model.health(for: account) }

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                metrics
                if let error = account.lastError, !error.isEmpty {
                    errorDetails(error)
                }
                footer
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ProviderMark(provider: account.provider)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.displayName)
                        .font(.headline)
                    if model.isDemo || account.isDemo { DemoTag() }
                }
                Text(account.provider.displayName + " · " + model.capabilitySummary(for: account))
                    .font(.caption)
                    .foregroundStyle(account.credentialInvalid ? .red : .secondary)
            }
            Spacer()
            HealthBadge(health: health)
            Button {
                model.refresh(account: account)
            } label: {
                if model.isSyncing(account) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isDemo || !account.enabled || model.isSyncing(account))
            .help(model.isDemo ? "演示模式不发起网络请求" : "立即刷新该账户")

            Menu {
                Button("编辑账户", action: onEdit)
                Button(account.enabled ? "禁用账户" : "启用账户") {
                    model.setAccountEnabled(account, enabled: !account.enabled)
                }
                Divider()
                Button("删除账户", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .disabled(model.isDemo)
            .help("账户操作")
        }
    }

    @ViewBuilder
    private var metrics: some View {
        switch account.provider {
        case .deepseek:
            deepSeekMetrics
        case .openrouter:
            openRouterMetrics
        }
    }

    @ViewBuilder
    private var deepSeekMetrics: some View {
        let balances = model.latestBalances(for: account)
        if balances.isEmpty {
            HStack {
                Image(systemName: "tray")
                    .foregroundStyle(.secondary)
                Text(health == .neverSynced ? "尚未同步。添加后可自动测试余额接口。" : "厂商未提供余额数据。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(balances) { balance in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("官方余额")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Money.formatBalance(balance.total, currency: balance.currency))
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let granted = balance.granted {
                            Text("赠送 \(Money.formatBalance(granted, currency: balance.currency))")
                        }
                        if let toppedUp = balance.toppedUp {
                            Text("充值 \(Money.formatBalance(toppedUp, currency: balance.currency))")
                        }
                        Text("快照 \(UIFormat.compactDate(balance.asOf))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    thresholdStatus(for: balance)
                }
            }
            Text("余额快照，非逐请求 token 统计；DeepSeek 官方不提供历史用量 / 费用。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func thresholdStatus(for balance: BalanceSnapshot) -> some View {
        if let threshold = account.balanceThreshold, threshold.currency == balance.currency {
            let low = balance.total < threshold.amount
            VStack(alignment: .trailing, spacing: 3) {
                Label(
                    low ? "低于阈值" : "高于阈值",
                    systemImage: low ? "exclamationmark.triangle.fill" : "checkmark.circle"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(low ? .orange : .green)
                Text("阈值 \(Money.formatBalance(threshold.amount, currency: threshold.currency))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var openRouterMetrics: some View {
        let quota = model.latestQuota(for: account)
        if let quota {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("credits 剩余")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Money.formatBalance(quota.remaining, currency: quota.currency))
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("总额 \(Money.formatBalance(quota.totalCredits, currency: quota.currency))")
                    Text("已用 \(Money.formatBalance(quota.totalUsage, currency: quota.currency))")
                    if let percent = quota.usagePercent {
                        Text("使用率 \(Money.percent(percent))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("官方 credits")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(UIFormat.compactDate(quota.asOf))
                        .font(.caption)
                }
            }
            BudgetSummaryView(model: model, account: account)
        } else {
            HStack {
                Image(systemName: "tray")
                    .foregroundStyle(.secondary)
                Text(health == .neverSynced ? "尚未同步 credits。" : "暂未获取到 credits。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorDetails(_ error: String) -> some View {
        DisclosureGroup {
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if account.credentialInvalid {
                Button("重新输入 API Key", action: onEdit)
                    .buttonStyle(.link)
                    .font(.caption)
                Text("凭据失效后已暂停自动重试，手动刷新仍可尝试。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label("查看错误详情", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(account.credentialInvalid ? Color.red : Color.orange)
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            let stale = model.isStale(account)
            Image(systemName: stale ? "clock.badge.exclamationmark" : "clock")
                .foregroundStyle(stale ? .orange : .secondary)
            Text(model.lastSyncText(for: account))
                .font(.caption)
                .foregroundStyle(stale ? .orange : .secondary)
            if stale {
                Text("已过期").font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text("来源：\(account.provider.displayName) 官方 API")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct BudgetSummaryView: View {
    @ObservedObject var model: AppModel
    let account: Account

    var body: some View {
        if let budget = account.budget {
            let spend = model.budgetSpend(for: account)
            let ratio = model.budgetRatio(for: account)
            let remaining = model.budgetRemaining(for: account)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("本地预算")
                        .font(.caption.weight(.semibold))
                    Text("\(Money.formatBalance(spend ?? 0, currency: budget.currency)) / \(Money.formatBalance(budget.amount, currency: budget.currency))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let ratio {
                        Text("\(Money.percent(ratio))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ratio >= 100 ? .red : ratio >= 80 ? .orange : .green)
                    } else {
                        Text("暂无用量数据").font(.caption).foregroundStyle(.secondary)
                    }
                }
                BudgetProgressBar(ratio: ratio, isDemo: model.isDemo)
                HStack {
                    Text("本月已用 · 按厂商日桶，可能不含今天")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let remaining {
                        Text(
                            remaining < 0
                                ? "已超支 \(Money.formatBalance(-remaining, currency: budget.currency))"
                                : "剩余 \(Money.formatBalance(remaining, currency: budget.currency))"
                        )
                        .font(.caption2)
                        .foregroundStyle(remaining < 0 ? Color.red : Color.secondary)
                    }
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "target").foregroundStyle(.secondary)
                Text("未设置本地月度预算（不等于官方额度）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
