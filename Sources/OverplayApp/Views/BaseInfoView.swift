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
                    L10n.t("baseInfo.7fa9347c55"),
                    systemImage: "clock.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            summaryCards

            providerSection

            MessageCenterEntryCard(model: model)

            Text(L10n.t("baseInfo.8629ca7a54"))
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
            ? .missing(L10n.t("baseInfo.f634ec739a"))
            : .actual
        let costStatus: DataStatus = model.analysisCosts.isEmpty
            ? .missing(L10n.t("baseInfo.9f08b89d94"))
            : .actual
        let requestStatus: DataStatus = model.analysisRequestTotal == nil
            ? .missing(L10n.t("usage.3f20509e5f"))
            : .actual
        let lastSync = model.analysisAccounts.compactMap(\.lastSuccessAt).max()
        let staleCount = model.analysisAccounts.filter { model.isStale($0) }.count
        let abnormalCount = model.analysisAccounts.filter {
            let health = model.health(for: $0)
            return health == .failed || health == .invalidCredential || health == .accountAbnormal
        }.count

        return LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 14) {
            MetricCard(
                title: L10n.t("baseInfo.7fb9613799"),
                valueLines: coverage.accountsWithTokens == 0
                    ? []
                    : [(Money.formatCompactInteger(model.analysisTokenTotal), "tokens")],
                footnote: L10n.f("baseInfo.7c53ee3c6b", coverage.accountsWithTokens, coverage.totalAccounts, coverage.providersWithTokens, coverage.totalProviders),
                symbol: "number",
                isDemo: model.isDemo,
                status: tokenStatus
            )
            MetricCard(
                title: L10n.t("metric.cost"),
                valueLines: model.analysisCosts.isEmpty ? [] : UIFormat.costLines(model.analysisCosts),
                footnote: L10n.t("baseInfo.24b771484b"),
                symbol: "dollarsign.circle",
                isDemo: model.isDemo,
                status: costStatus
            )
            MetricCard(
                title: L10n.t("core.analysisRange.b28376ff80"),
                valueLines: model.analysisRequestTotal.map { [(Money.formatCompactInteger($0), L10n.t("usage.5e5b8169ee"))] } ?? [],
                footnote: model.analysisRequestTotal == nil
                    ? L10n.t("baseInfo.88a40571d3")
                    : L10n.t("baseInfo.18c1baa4c4"),
                symbol: "arrow.left.arrow.right",
                isDemo: model.isDemo,
                status: requestStatus
            )
            MetricCard(
                title: L10n.t("baseInfo.ce72378885"),
                valueLines: [
                    (lastSync.map { DateFormatters.shortTime.string(from: $0) } ?? L10n.t("health.neverSynced"), L10n.t("baseInfo.35b15d3f3f")),
                    ("\(staleCount)", L10n.t("baseInfo.0191542e9c")),
                    ("\(abnormalCount)", L10n.t("baseInfo.4f50336f57"))
                ],
                footnote: L10n.f("baseInfo.8cbcd8ac1a", model.unacknowledgedAlertCount),
                symbol: "clock.badge.checkmark",
                isDemo: model.isDemo,
                status: lastSync == nil ? .missing(L10n.t("baseInfo.665be664fe")) : .actual
            )
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L10n.t("baseInfo.40fbaed843"))
                    .font(.title3.weight(.semibold))
                Text("\(model.analysisAccounts.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let platform = model.overviewPlatformFilter {
                    Text(L10n.f("baseInfo.60f3dec380", platform.displayName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(L10n.t("baseInfo.f7bc664f3f"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if model.analysisAccounts.isEmpty {
                SectionCard {
                    EmptyStateView(
                        symbol: "rectangle.stack.badge.plus",
                        title: model.accounts.isEmpty ? L10n.t("baseInfo.1d54343fa9") : L10n.t("baseInfo.cd266e99f9"),
                        message: model.accounts.isEmpty
                            ? L10n.t("baseInfo.76b012fb15")
                            : L10n.t("baseInfo.ee2f9d97b0")
                    ) {
                        if !model.accounts.isEmpty {
                            Button(L10n.t("messages.4bbc4e5fd9")) {
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
                platformButton(nil, title: L10n.t("common.all"), symbol: "square.grid.2x2")
                ForEach(presentProviders) { provider in
                    platformButton(for: provider)
                }
            }
            HStack(spacing: 8) {
                Text(model.overviewPlatformFilter.map { L10n.f("baseInfo.60f3dec380", $0.displayName) } ?? L10n.t("baseInfo.2d85b1ea90"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if presentProviders.count > 3 {
                    Label(L10n.t("baseInfo.400505d1d9"), systemImage: "arrow.turn.down.left")
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
            accountChip(nil, title: L10n.f("baseInfo.e77b86c074", platform.displayName))
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
                    Label(L10n.t("baseInfo.c11c8a772e"), systemImage: "clock.badge.exclamationmark")
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
                    if !account.enabled { StatusTag(text: L10n.t("health.disabled"), color: .secondary) }
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
                Button(L10n.t("baseInfo.0d428278d9"), action: onDetail)
                Button(L10n.t("accountEditor.608f93e8ea"), action: onEdit)
                Button(account.enabled ? L10n.t("baseInfo.b9794fa830") : L10n.t("settings.ae0ba48faa")) {
                    model.setAccountEnabled(account, enabled: !account.enabled)
                }
                Divider()
                Button(L10n.t("deleteAccount.9259840611"), role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .disabled(model.isDemo)
            .help(L10n.t("baseInfo.ef38c6c524"))
        }
    }

    private var subtitle: String {
        [
            account.provider.displayName,
            account.officialName.map { L10n.f("common.officialName", $0) },
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
            Label(L10n.t("baseInfo.5cb58536e5"), systemImage: "exclamationmark.octagon.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.red)
        } else if warning {
            Label(L10n.t("baseInfo.d55a864f5c"), systemImage: "exclamationmark.circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }


    private var refreshHelp: String {
        if let reason = model.refreshBlockedReason(for: account) { return L10n.t(reason) }
        if model.isSyncing(account) { return L10n.t("baseInfo.8560e9be4e") }
        if model.isDemo { return L10n.t("floating.280880b4de") }
        if !account.enabled { return L10n.t("baseInfo.6f96432f99") }
        return L10n.t("providerDetail.03e03ba84f")
    }

    @ViewBuilder
    private var metrics: some View {
        if account.capabilities.balance && !account.capabilities.usage {
            balanceMetric
        } else if account.capabilities.credits || account.capabilities.usage {
            quotaAndUsageMetric
        } else {
            Text(L10n.t("baseInfo.dc9cdca5c4"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var balanceMetric: some View {
        let balances = model.latestBalances(for: account)
        let status = model.balanceDataStatus(for: account).prefixed(L10n.t("core.floatingSummary.f5f1ad2311"))
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                if balances.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("core.floatingSummary.f5f1ad2311")).font(.caption).foregroundStyle(.secondary)
                        DataValueLabel(
                            text: L10n.t("dataStatus.6ffa7e6d35"),
                            status: status,
                            font: .system(size: 24, weight: .semibold, design: .rounded)
                        )
                    }
                } else {
                    ForEach(balances) { balance in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.f("quota.e0544e29c7", balance.currency))
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
                                        ? L10n.f("baseInfo.0626c3bc1b", Money.formatBalance(threshold.amount, currency: threshold.currency))
                                        : L10n.f("baseInfo.eabd8c1ea6", Money.formatBalance(threshold.amount, currency: threshold.currency))
                                )
                                .font(.caption2)
                                .foregroundStyle(balance.total < threshold.amount ? .orange : .green)
                            }
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L10n.t("baseInfo.4a6fb8eefc")).font(.caption2).foregroundStyle(.secondary)
                    Text(L10n.t("providerDetail.567cdafa2a")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            Text(L10n.t("baseInfo.c0a161ce12"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var quotaAndUsageMetric: some View {
        let quota = model.latestQuota(for: account)
        let quotaStatus = model.creditDataStatus(for: account).prefixed(L10n.t("core.floatingSummary.f625451199"))
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 22) {
                if let quota {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.provider == .openrouter ? L10n.t("baseInfo.6bd2bad8b1") : L10n.t("baseInfo.682ca815ac"))
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
                        Text(L10n.t("core.floatingSummary.f625451199")).font(.caption).foregroundStyle(.secondary)
                        DataValueLabel(
                            text: L10n.t("dataStatus.6ffa7e6d35"),
                            status: quotaStatus,
                            font: .system(size: 20, weight: .semibold, design: .rounded)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("baseInfo.8bb2d0af98")).font(.caption2).foregroundStyle(.secondary)
                    if totals.tokensAvailable {
                        Text("\(Money.formatCompactInteger(totals.totalTokens)) tokens")
                            .font(.callout.weight(.semibold))
                    } else {
                        Text(L10n.t("baseInfo.f5a04ffd39")).font(.caption).foregroundStyle(.secondary)
                    }
                    if totals.costAvailable {
                        Text(UIFormat.costLines(totals.costs).map { $0.0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.t("baseInfo.ecbf87414d")).font(.caption2).foregroundStyle(.secondary)
                    }
                    if totals.requestsAvailable {
                        Text(L10n.f("floating.9c7b978970", Money.formatCompactInteger(totals.requests)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let quota, quotaStatus.isActual, let percent = quota.usagePercent, !forceUnavailable {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.t("quota.9bfba85a1b")).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(Money.percent(percent)).font(.caption.weight(.semibold))
                    }
                    ProgressView(value: min(max(NSDecimalNumber(decimal: percent).doubleValue / 100, 0), 1))
                        .tint(.blue)
                    Text(L10n.t("baseInfo.9ffcfa3aec"))
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
                        Text(L10n.t("baseInfo.d29c4f346f")).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(Money.percent(ratio)).font(.caption.weight(.semibold))
                    }
                    ProgressView(value: min(max(NSDecimalNumber(decimal: ratio).doubleValue / 100, 0), 1))
                        .tint(.blue)
                    Text(L10n.f("baseInfo.8b1f22e1ab", Money.formatBalance(budget.amount, currency: budget.currency)))
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
                Text(L10n.f("baseInfo.4403282cda", account.balanceThreshold.map { L10n.f("baseInfo.legacyBalanceSuffix", Money.formatBalance($0.amount, currency: $0.currency)) } ?? ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            let rules = (account.alertConfig ?? .off).resolved(public: model.settings.publicAlertConfig)
            if !rules.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                        Text("\(rule.severity == .warning ? L10n.t("addProvider.35f0803018") : L10n.t("addProvider.8d56556021"))：\(rule.metric.label) \(thresholdText(rule)) · \(rule.source)")
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
            Button(L10n.t("baseInfo.faea8c1db9"), action: onDetail)
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
            return L10n.t("baseInfo.e8bf4ef6d0")
        }
        if account.provider == .openrouter {
            return L10n.t("baseInfo.5871102d85")
        }
        if account.provider == .genericHTTP {
            return L10n.t("baseInfo.d40c85e679")
        }
        if account.isDemo || model.isDemo {
            return L10n.t("baseInfo.e828a09325")
        }
        return L10n.f("baseInfo.b27a18c7a0", account.provider.displayName)
    }
}

private struct OrganizationTag: View {
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "building.2")
            Text(L10n.t("providerDetail.9e4000b2b7"))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.blue)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.blue.opacity(0.12)))
        .accessibilityLabel(L10n.t("baseInfo.d6b4cae72b"))
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
