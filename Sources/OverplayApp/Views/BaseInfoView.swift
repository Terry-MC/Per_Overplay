import SwiftUI
import OverplayCore

struct BaseInfoView: View {
    @ObservedObject var model: AppModel
    var onEdit: (Account) -> Void
    var onDelete: (Account) -> Void

    private let metricColumns = [GridItem(.adaptive(minimum: 230), spacing: 14)]

    private var selectedDetailAccount: Binding<Account?> {
        Binding(
            get: { model.accounts.first { $0.id == model.selectedProviderDetailAccountId } },
            set: { model.selectedProviderDetailAccountId = $0?.id }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.accounts.isEmpty {
                platformFilterBar
                if let platform = model.overviewPlatformFilter,
                   model.overviewPlatformAccounts.count > 1 {
                    accountFilterChips(platform: platform)
                }
            }

            AnalysisRangeControls(model: model)

            if model.analysisAccounts.contains(where: { $0.provider == .openrouter }),
               CalendarDay.days(from: model.currentRange).count > 30 {
                Label(
                    "OpenRouter 仅提供约 30 个 UTC 日窗口；超出部分不会显示，也不补 0。",
                    systemImage: "clock.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            summaryCards

            providerSection

            MessageCenterEntryCard(model: model)

            Text("统计只使用本地已同步的厂商数据；缺失数据不补零。token 总量不包含未提供 token 的厂商，费用分币种展示且不做汇率换算。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(item: selectedDetailAccount) { account in
            ProviderDetailView(model: model, account: account)
        }
    }

    private var summaryCards: some View {
        let coverage = model.analysisTokenCoverage
        let tokenStatus: DataStatus = coverage.accountsWithTokens == 0
            ? .missing("所选范围没有提供实际 token 数据的账户")
            : .actual
        let costStatus: DataStatus = model.analysisCosts.isEmpty
            ? .missing("所选范围没有费用数据")
            : .actual
        let requestStatus: DataStatus = model.analysisRequestTotal == nil
            ? .missing("当前记录的厂商未提供请求数字段")
            : .actual
        let lastSync = model.analysisAccounts.compactMap(\.lastSuccessAt).max()
        let staleCount = model.analysisAccounts.filter { model.isStale($0) }.count
        let abnormalCount = model.analysisAccounts.filter {
            let health = model.health(for: $0)
            return health == .failed || health == .invalidCredential || health == .accountAbnormal
        }.count

        return LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 14) {
            MetricCard(
                title: "Token 总消耗",
                valueLines: coverage.accountsWithTokens == 0
                    ? []
                    : [(Money.formatCompactInteger(model.analysisTokenTotal), "tokens")],
                footnote: "覆盖 \(coverage.accountsWithTokens) / \(coverage.totalAccounts) 个账户 · \(coverage.providersWithTokens) / \(coverage.totalProviders) 个厂商提供 token；不含无 token 数据的厂商。",
                symbol: "number",
                isDemo: model.isDemo,
                status: tokenStatus
            )
            MetricCard(
                title: "费用",
                valueLines: model.analysisCosts.isEmpty ? [] : UIFormat.costLines(model.analysisCosts),
                footnote: "分币种展示，不跨币种合并；仅含提供费用字段的厂商。",
                symbol: "dollarsign.circle",
                isDemo: model.isDemo,
                status: costStatus
            )
            MetricCard(
                title: "请求数",
                valueLines: model.analysisRequestTotal.map { [(Money.formatCompactInteger($0), "次")] } ?? [],
                footnote: model.analysisRequestTotal == nil
                    ? "厂商未提供请求数字段，不显示 0。"
                    : "仅累加提供请求数字段的记录。",
                symbol: "arrow.left.arrow.right",
                isDemo: model.isDemo,
                status: requestStatus
            )
            MetricCard(
                title: "数据新鲜度",
                valueLines: [
                    (lastSync.map { DateFormatters.shortTime.string(from: $0) } ?? "尚未同步", "最近成功"),
                    ("\(staleCount)", "过期账户"),
                    ("\(abnormalCount)", "异常账户")
                ],
                footnote: "告警未确认 \(model.unacknowledgedAlertCount) 条；过期阈值为 2 个刷新周期。",
                symbol: "clock.badge.checkmark",
                isDemo: model.isDemo,
                status: lastSync == nil ? .missing("尚未完成任何成功同步") : .actual
            )
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("厂商概览")
                    .font(.title3.weight(.semibold))
                Text("\(model.analysisAccounts.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let platform = model.overviewPlatformFilter {
                    Text("仅显示 \(platform.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("点击卡片进入厂商详情")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if model.analysisAccounts.isEmpty {
                SectionCard {
                    EmptyStateView(
                        symbol: "rectangle.stack.badge.plus",
                        title: model.accounts.isEmpty ? "暂无厂商账户" : "当前筛选没有账户",
                        message: model.accounts.isEmpty
                            ? "使用窗口右上角“添加账户”，或切换到演示模式查看各平台数据。"
                            : "清除平台 / 账户筛选，或切换到其他时间范围。"
                    ) {
                        if !model.accounts.isEmpty {
                            Button("清除筛选") {
                                model.overviewPlatformFilter = nil
                                model.overviewAccountFilter = nil
                            }
                        }
                    }
                }
            } else {
                ForEach(model.analysisAccounts) { account in
                    ProviderOverviewCard(
                        model: model,
                        account: account,
                        onDetail: { model.selectedProviderDetailAccountId = account.id },
                        onEdit: { onEdit(account) },
                        onDelete: { onDelete(account) }
                    )
                }
            }
        }
    }

    // MARK: - Filters

    private var platformFilterBar: some View {
        let presentProviders = ProviderKind.allCases.filter { provider in
            model.accounts.contains { $0.provider == provider }
        }
        return VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                platformButton(nil, title: "All", symbol: "square.grid.2x2")
                ForEach(presentProviders) { provider in
                    platformButton(for: provider)
                }
            }
            HStack(spacing: 8) {
                Text(model.overviewPlatformFilter.map { "仅显示 \($0.displayName)" } ?? "全部 AI 平台")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if presentProviders.count > 3 {
                    Label("窗口较窄时平台标签自动换行", systemImage: "arrow.turn.down.left")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func platformButton(for provider: ProviderKind) -> some View {
        let style = providerStyle(for: provider)
        return platformButton(provider, title: provider.displayName, letter: style.abbreviation, color: style.color)
    }

    private func accountFilterChips(platform: ProviderKind) -> some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            accountChip(nil, title: "全部 \(platform.displayName) 账户")
            ForEach(model.overviewPlatformAccounts) { account in
                accountChip(account.id, title: account.displayName)
            }
        }
    }

    private func accountChip(_ accountId: String?, title: String) -> some View {
        let selected = model.overviewAccountFilter == accountId
        return Button {
            model.overviewAccountFilter = accountId
        } label: {
            Text(title)
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func platformButton(
        _ platform: ProviderKind?,
        title: String,
        symbol: String? = nil,
        letter: String? = nil,
        color: Color = .accentColor
    ) -> some View {
        let selected = model.overviewPlatformFilter == platform
        return Button {
            model.overviewPlatformFilter = platform
        } label: {
            HStack(spacing: 6) {
                if let platform, let brandIcon = BrandIconCatalog.image(for: platform) {
                    Image(nsImage: brandIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .padding(3)
                        .background(Circle().fill(Color.white.opacity(0.94)))
                        .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.caption)
                } else if let letter {
                    Text(letter)
                        .font(.system(size: letter.count > 1 ? 7 : 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(color))
                }
                Text(title)
                    .fixedSize()
            }
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.accentColor : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Provider card

private struct ProviderOverviewCard: View {
    @ObservedObject var model: AppModel
    let account: Account
    let onDetail: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var health: AccountHealth { model.health(for: account) }
    private var totals: ProviderUsageTotals { model.providerTotals(for: account) }
    private var forceUnavailable: Bool {
        !account.enabled || health == .failed || health == .invalidCredential
            || health == .accountAbnormal || health == .stale || health == .partial
            || health == .connectedNoData || health == .neverSynced
    }
    private var organizationTag: Bool {
        [.openai, .anthropic].contains(account.provider)
    }

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                metrics
                progressSection
                if let issue = model.dataIssue(for: account) {
                    AnomalyNotice(message: issue)
                }
                if model.isStale(account) {
                    Label("数据已过期；仍展示最近一次有效数据。", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                footer
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onDetail)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            ProviderMark(provider: account.provider, iconName: account.iconName)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.displayName)
                        .font(.headline)
                    if model.isDemo || account.isDemo { DemoTag() }
                    if organizationTag { OrganizationTag() }
                    if !account.enabled { StatusTag(text: "已禁用", color: .secondary) }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(account.credentialInvalid ? .red : .secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            accountAlertBadge
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
            .disabled(
                model.isDemo || !account.enabled || model.isSyncing(account)
                    || model.isRefreshCoolingDown(account)
            )
            .help(refreshHelp)

            Menu {
                Button("打开详情", action: onDetail)
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

    private var subtitle: String {
        [
            account.provider.displayName,
            account.officialName.map { "官方 \($0)" },
            model.currencyLabel(for: account),
            account.capabilities.summary
        ].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var accountAlertBadge: some View {
        let unacknowledged = model.alerts.filter {
            $0.accountId == account.id && !$0.acknowledged
        }
        let critical = unacknowledged.contains {
            [.budgetExceeded, .balanceLow, .credentialInvalid, .syncFailed, .lineCritical].contains($0.kind)
        }
        let warning = unacknowledged.contains {
            [.budgetWarning, .dataStale, .lineWarning].contains($0.kind)
        }
        if critical {
            Label("警戒", systemImage: "exclamationmark.octagon.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.red)
        } else if warning {
            Label("告知", systemImage: "exclamationmark.circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }


    private var refreshHelp: String {
        if let reason = model.refreshBlockedReason(for: account) { return reason }
        if model.isSyncing(account) { return "正在同步该账户" }
        if model.isDemo { return "演示模式不发起网络请求" }
        if !account.enabled { return "账户已禁用，请先启用" }
        return "立即刷新该账户"
    }

    @ViewBuilder
    private var metrics: some View {
        if account.capabilities.balance && !account.capabilities.usage {
            balanceMetric
        } else if account.capabilities.credits || account.capabilities.usage {
            quotaAndUsageMetric
        } else {
            Text("该厂商当前没有可展示的用量、费用或额度指标。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var balanceMetric: some View {
        let balances = model.latestBalances(for: account)
        let status = model.balanceDataStatus(for: account).prefixed("官方余额")
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                if balances.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("官方余额").font(.caption).foregroundStyle(.secondary)
                        DataValueLabel(
                            text: "无数据",
                            status: status,
                            font: .system(size: 24, weight: .semibold, design: .rounded)
                        )
                    }
                } else {
                    ForEach(balances) { balance in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("官方余额 · \(balance.currency)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            DataValueLabel(
                                text: Money.formatBalance(balance.total, currency: balance.currency),
                                status: status,
                                font: .system(size: 24, weight: .semibold, design: .rounded)
                            )
                            if let threshold = account.balanceThreshold, threshold.currency == balance.currency {
                                Text(
                                    balance.total < threshold.amount
                                        ? "低于阈值 \(Money.formatBalance(threshold.amount, currency: threshold.currency))"
                                        : "高于阈值 \(Money.formatBalance(threshold.amount, currency: threshold.currency))"
                                )
                                .font(.caption2)
                                .foregroundStyle(balance.total < threshold.amount ? .orange : .green)
                            }
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("所选范围 token").font(.caption2).foregroundStyle(.secondary)
                    Text("厂商未提供").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            Text("余额型厂商：无百分比分母，不显示伪造进度；详情展示余额快照曲线。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var quotaAndUsageMetric: some View {
        let quota = model.latestQuota(for: account)
        let quotaStatus = model.creditDataStatus(for: account).prefixed("官方额度")
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 22) {
                if let quota {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.provider == .openrouter ? "credits 剩余" : "官方额度剩余")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DataValueLabel(
                            text: Money.formatBalance(quota.remaining, currency: quota.currency),
                            status: quotaStatus,
                            font: .system(size: 24, weight: .semibold, design: .rounded)
                        )
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("官方额度").font(.caption).foregroundStyle(.secondary)
                        DataValueLabel(
                            text: "无数据",
                            status: quotaStatus,
                            font: .system(size: 20, weight: .semibold, design: .rounded)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("所选范围").font(.caption2).foregroundStyle(.secondary)
                    if totals.tokensAvailable {
                        Text("\(Money.formatCompactInteger(totals.totalTokens)) tokens")
                            .font(.callout.weight(.semibold))
                    } else {
                        Text("Token：厂商未提供").font(.caption).foregroundStyle(.secondary)
                    }
                    if totals.costAvailable {
                        Text(UIFormat.costLines(totals.costs).map { $0.0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("费用：厂商未提供").font(.caption2).foregroundStyle(.secondary)
                    }
                    if totals.requestsAvailable {
                        Text("\(Money.formatCompactInteger(totals.requests)) 次请求")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let quota, quotaStatus.isActual, let percent = quota.usagePercent, !forceUnavailable {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("官方额度使用率").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(Money.percent(percent)).font(.caption.weight(.semibold))
                    }
                    ProgressView(value: min(max(NSDecimalNumber(decimal: percent).doubleValue / 100, 0), 1))
                        .tint(.blue)
                    Text("中性使用率；告警线在“新增厂商”页按账户配置，未启用时不显示告知 / 警戒标记。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if forceUnavailable {
            EmptyView()
        } else {
            if let budget = account.budget, let ratio = model.budgetRatio(for: account) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("本地预算使用率（本机自然月）").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(Money.percent(ratio)).font(.caption.weight(.semibold))
                    }
                    ProgressView(value: min(max(NSDecimalNumber(decimal: ratio).doubleValue / 100, 0), 1))
                        .tint(.blue)
                    Text("预算 \(Money.formatBalance(budget.amount, currency: budget.currency)) · 与官方额度分开。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            alertRuleSummary
        }
    }

    @ViewBuilder
    private var alertRuleSummary: some View {
        if account.alertConfig == nil {
            if account.budget != nil || account.balanceThreshold != nil {
                Text("旧阈值兼容：预算 80% / 100%\(account.balanceThreshold.map { " · 余额 \(Money.formatBalance($0.amount, currency: $0.currency))" } ?? "")；新告警线默认关闭。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            let rules = (account.alertConfig ?? .off).resolved(public: model.settings.publicAlertConfig)
            if !rules.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                        Text("\(rule.severity == .warning ? "告知线" : "警戒线")：\(rule.metric.label) \(thresholdText(rule)) · \(rule.source)")
                            .font(.caption2)
                            .foregroundStyle(rule.severity == .warning ? .orange : .red)
                    }
                }
            }
        }
    }

    private func thresholdText(_ rule: ResolvedAlertRule) -> String {
        switch rule.metric {
        case .budgetPercent, .quotaPercent:
            return Money.percent(rule.threshold)
        case .balanceAbsolute:
            return "≤ \(Money.formatBalance(rule.threshold, currency: rule.currency ?? account.provider.defaultCurrency))"
        case .tokenAbsolute:
            return "≥ \(Money.formatCompactInteger(NSDecimalNumber(decimal: rule.threshold).intValue)) tokens"
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: model.isStale(account) ? "clock.badge.exclamationmark" : "clock")
                .foregroundStyle(model.isStale(account) ? .orange : .secondary)
            Text(model.lastSyncText(for: account))
                .font(.caption)
                .foregroundStyle(model.isStale(account) ? .orange : .secondary)
            Spacer()
            Button("查看详情", action: onDetail)
                .buttonStyle(.link)
                .font(.caption)
            Text(capabilityFootnote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private var capabilityFootnote: String {
        if account.provider == .deepseek {
            return "来源：DeepSeek 余额快照 · 非逐请求 token"
        }
        if account.provider == .openrouter {
            return "来源：OpenRouter activity · 约 30 天 UTC 日桶"
        }
        if account.provider == .genericHTTP {
            return "来源：通用 HTTP · 仅映射字段"
        }
        if account.isDemo || model.isDemo {
            return "来源：演示数据 · 不联网"
        }
        return "来源：\(account.provider.displayName) 官方只读接口"
    }
}

private struct OrganizationTag: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "building.2")
            Text("组织级")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.blue)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.blue.opacity(0.12)))
        .accessibilityLabel("组织级数据")
    }
}

private struct StatusTag: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}
