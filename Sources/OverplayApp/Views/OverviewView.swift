import SwiftUI
import OverplayCore

struct OverviewView: View {
    @ObservedObject var model: AppModel
    var onEdit: (Account) -> Void
    var onDelete: (Account) -> Void

    private let metricColumns = [GridItem(.adaptive(minimum: 250), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !model.balanceAccounts.isEmpty {
                balanceAccountPicker
            }
            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 14) {
                MetricCard(
                    title: "今日费用",
                    valueLines: model.todayCosts.isEmpty ? [] : UIFormat.costLines(model.todayCosts),
                    footnote: todayFootnote,
                    symbol: "sun.max",
                    isDemo: model.isDemo,
                    emptyText: "0",
                    status: model.costDataStatus(forToday: true).prefixed("今日费用")
                )
                MetricCard(
                    title: "本月至今费用",
                    valueLines: model.monthCosts.isEmpty ? [] : UIFormat.costLines(model.monthCosts),
                    footnote: "自然月按本机时区；按厂商日桶聚合，分币种展示，不跨币种求和。",
                    symbol: "calendar",
                    isDemo: model.isDemo,
                    emptyText: "0",
                    status: model.costDataStatus(forToday: false).prefixed("本月费用")
                )
                MetricCard(
                    title: "近 30 天 tokens",
                    valueLines: tokenLines,
                    footnote: tokenFootnote,
                    symbol: "number",
                    isDemo: model.isDemo,
                    emptyText: "0",
                    status: model.tokenDataStatus().prefixed("tokens")
                )
                MetricCard(
                    title: "官方额度剩余",
                    valueLines: model.officialCreditsRemaining.isEmpty
                        ? [] : UIFormat.costLines(model.officialCreditsRemaining),
                    footnote: "OpenRouter credits（官方）· total_credits − total_usage。",
                    symbol: "gauge.with.dots.needle.50percent",
                    isDemo: model.isDemo,
                    emptyText: "0",
                    status: model.creditDataStatus().prefixed("官方 credits")
                )
                MetricCard(
                    title: "官方余额",
                    valueLines: model.officialBalances.isEmpty
                        ? [] : UIFormat.costLines(model.officialBalances),
                    footnote: officialBalanceFootnote,
                    symbol: "creditcard",
                    isDemo: model.isDemo,
                    emptyText: "0",
                    status: officialBalanceStatus,
                    accessory: model.availableBalanceCurrencies.isEmpty
                        ? nil
                        : AnyView(officialBalanceCurrencyPicker)
                )
                MetricCard(
                    title: "本地预算剩余",
                    valueLines: budgetRemainingLines,
                    footnote: "同币种账户净额，可能含超支账户抵扣；本地预算按本机自然月，与用量页所选范围分开；无完整数据不计算。",
                    symbol: "target",
                    isDemo: model.isDemo,
                    emptyText: "0",
                    status: model.budgetRemainingDataStatus().prefixed("本地预算")
                )
            }
            HStack(spacing: 14) {
                Label("0 + ?：该数字缺失，悬浮查看原因", systemImage: "questionmark.circle")
                Label("橙色警告：该卡片数据异常，悬浮查看具体原因", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

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

    private var balanceAccountPicker: some View {
        HStack(spacing: 10) {
            Label("官方余额账户", systemImage: "creditcard")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("官方余额账户", selection: $model.balanceAccountFilter) {
                Text("全部 DeepSeek 账户").tag(String?.none)
                ForEach(model.balanceAccounts) { account in
                    Text("\(account.displayName) · \(model.currencyLabel(for: account))")
                        .tag(Optional(account.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 260)
            if model.selectedBalanceAccount != nil {
                Text("已选择该账户；币种在卡片内切换")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("全部 DeepSeek 账户；币种在卡片内切换")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var officialBalanceCurrencyPicker: some View {
        if !model.availableBalanceCurrencies.isEmpty {
            Picker("币种", selection: $model.balanceCurrencyFilter) {
                ForEach(model.availableBalanceCurrencies, id: \.self) { code in
                    Text("\(Money.symbol(for: code)) \(code)")
                        .tag(Optional(code))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("切换 DeepSeek 官方余额币种")
        }
    }

    private var officialBalanceFootnote: String {
        if let code = model.balanceCurrencyFilter {
            return "当前仅显示 \(Money.symbol(for: code)) \(code) 的官方余额；可在卡片内切换币种。"
        }
        return "选择 DeepSeek 账户与币种查看官方余额。"
    }

    private var officialBalanceStatus: DataStatus {
        if let code = model.balanceCurrencyFilter, model.officialBalances.isEmpty {
            return .missing("当前筛选的 \(Money.symbol(for: code)) \(code) 暂无余额数据；0 仅为占位")
                .prefixed("官方余额")
        }
        return model.balanceDataStatus(for: model.selectedBalanceAccount).prefixed("官方余额")
    }

    private var todayFootnote: String {
        switch model.costDataStatus(forToday: true) {
        case .actual:
            return "按厂商 UTC 日桶统计；0 为实际零消费。"
        case .missing(let reason), .anomaly(let reason):
            return reason.replacingOccurrences(of: "；0 仅为占位", with: "")
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
            switch model.tokenDataStatus() {
            case .actual:
                return "所选范围没有 token 记录。"
            case .missing(let reason), .anomaly(let reason):
                return reason.replacingOccurrences(of: "；0 仅为占位", with: "")
            }
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
            title: "消息",
            subtitle: model.unacknowledgedAlerts.isEmpty
                ? "无未确认消息"
                : "\(model.unacknowledgedAlerts.count) 条未确认",
            isDemo: model.isDemo
        ) {
            HStack(spacing: 10) {
                Image(systemName: model.unacknowledgedAlerts.isEmpty ? "bell" : "bell.badge")
                    .foregroundStyle(model.unacknowledgedAlerts.isEmpty ? Color.secondary : Color.orange)
                Text(
                    model.unacknowledgedAlerts.isEmpty
                        ? "暂无未确认消息。"
                        : "顶部提示会在倒计时结束后归档到消息页。"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                Spacer()
                Button("查看全部消息") {
                    model.selectedTab = .messages
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

    private var accountSubtitle: String {
        [
            account.provider.displayName,
            model.currencyLabel(for: account),
            model.capabilitySummary(for: account)
        ].joined(separator: " · ")
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
                Text(accountSubtitle)
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
        let status = model.balanceDataStatus(for: account).prefixed("官方余额")
        if balances.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("官方余额 · \(model.currencyLabel(for: account))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DataValueLabel(
                    text: "0",
                    status: status,
                    font: .system(size: 25, weight: .semibold, design: .rounded)
                )
                statusMessage(status)
            }
        } else {
            ForEach(balances) { balance in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("官方余额 · \(balance.currency)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DataValueLabel(
                            text: Money.formatBalance(balance.total, currency: balance.currency),
                            status: status,
                            font: .system(size: 25, weight: .semibold, design: .rounded)
                        )
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
            if case .anomaly = status {
                statusMessage(status)
            }
            Text("余额快照，非逐请求 token 统计；DeepSeek 官方不提供历史用量 / 费用。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func statusMessage(_ status: DataStatus) -> some View {
        switch status {
        case .actual:
            EmptyView()
        case .missing(let reason):
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .anomaly(let reason):
            AnomalyNotice(message: reason)
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
        let status = model.creditDataStatus(for: account).prefixed("credits 剩余")
        if let quota {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("credits 剩余")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DataValueLabel(
                        text: Money.formatBalance(quota.remaining, currency: quota.currency),
                        status: status,
                        font: .system(size: 25, weight: .semibold, design: .rounded)
                    )
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
            if case .anomaly = status {
                statusMessage(status)
            }
            BudgetSummaryView(model: model, account: account)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("credits 剩余 · \(model.currencyLabel(for: account))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DataValueLabel(
                    text: "0",
                    status: status,
                    font: .system(size: 25, weight: .semibold, design: .rounded)
                )
                statusMessage(status)
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
            Label("数据异常 · 查看详情", systemImage: "exclamationmark.triangle")
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
            let spendStatus = model.budgetSpendDataStatus(for: account).prefixed("本月已用")
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("本地预算")
                        .font(.caption.weight(.semibold))
                    Text(Money.formatBalance(budget.amount, currency: budget.currency))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let spend, let ratio {
                        Text("已用 \(Money.formatCost(spend, currency: budget.currency))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Money.percent(ratio))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ratio >= 100 ? .red : ratio >= 80 ? .orange : .green)
                    } else {
                        Text("已用")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DataValueLabel(
                            text: "0",
                            status: spendStatus,
                            font: .caption.weight(.semibold)
                        )
                    }
                }
                if let ratio {
                    BudgetProgressBar(ratio: ratio, isDemo: model.isDemo)
                } else {
                    Text(spendStatus.reason ?? "本月用量数据不完整；0 仅为占位，不计算使用率 / 剩余 / 预估。")
                        .font(.caption2)
                        .foregroundStyle(spendStatus.isAnomaly ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text("本月已用 · 本机自然月 · 厂商日桶可能不含今天")
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
