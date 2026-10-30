import Charts
import SwiftUI
import OverplayCore

struct QuotaView: View {
    @ObservedObject var model: AppModel
    @State private var budgetAccount: Account?
    @State private var thresholdAccount: Account?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error = model.analysisRangeError {
                InlineErrorView(message: error.message)
            }
            if model.accounts.isEmpty {
                EmptyStateView(
                    symbol: "gauge.with.dots.needle.50percent",
                    title: "暂无账户",
                    message: "添加 DeepSeek 或 OpenRouter 真实账户，或切换到演示模式查看各平台虚拟额度、用量与本地预算。"
                )
            } else {
                ForEach(model.accounts) { account in
                    accountSection(account)
                }
                MessageCenterEntryCard(model: model)
            }
        }
        .sheet(item: $budgetAccount) { account in
            BudgetEditorView(model: model, account: account, kind: .budget)
        }
        .sheet(item: $thresholdAccount) { account in
            BudgetEditorView(model: model, account: account, kind: .threshold)
        }
    }

    @ViewBuilder
    private func accountSection(_ account: Account) -> some View {
        SectionCard(
            title: nil,
            subtitle: nil,
            isDemo: model.isDemo
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    ProviderMark(provider: account.provider, iconName: account.iconName)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(account.displayName).font(.headline)
                            if model.isDemo || account.isDemo { DemoTag() }
                        }
                        Text(accountSubtitle(account))
                            .font(.caption)
                            .foregroundStyle(account.credentialInvalid ? .red : .secondary)
                    }
                    Spacer()
                    HealthBadge(health: model.health(for: account))
                    Button {
                        model.refresh(account: account)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isDemo || !account.enabled || model.isSyncing(account))
                }

                if let issue = model.dataIssue(for: account) {
                    AnomalyNotice(message: issue)
                }

                if account.capabilities.balance {
                    deepSeekSection(account)
                } else {
                    openRouterSection(account)
                }
            }
        }
    }

    private func accountSubtitle(_ account: Account) -> String {
        [
            account.provider.displayName,
            account.officialName.map { "官方 \($0)" },
            model.currencyLabel(for: account),
            model.capabilitySummary(for: account)
        ].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private func statusMessage(_ status: DataStatus) -> some View {
        switch status {
        case .actual, .anomaly:
            EmptyView()
        case .missing(let reason), .unavailable(let reason):
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .partial(let reason), .failed(let reason):
            Text(reason)
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func deepSeekSection(_ account: Account) -> some View {
        let balances = model.latestBalances(for: account)
        let status = model.balanceDataStatus(for: account).prefixed("官方余额")
        Divider()
        if balances.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("官方余额 · \(model.currencyLabel(for: account))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DataValueLabel(
                            text: "无数据",
                            status: status,
                            font: .system(size: 30, weight: .semibold, design: .rounded)
                        )
                    }
                    Spacer()
                }
                statusMessage(status)
            }
        } else {
            ForEach(balances) { balance in
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("官方余额 · \(balance.currency)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DataValueLabel(
                            text: Money.formatBalance(balance.total, currency: balance.currency),
                            status: status,
                            font: .system(size: 30, weight: .semibold, design: .rounded)
                        )
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let granted = balance.granted {
                            Text("赠送余额 \(Money.formatBalance(granted, currency: balance.currency))")
                        }
                        if let toppedUp = balance.toppedUp {
                            Text("充值余额 \(Money.formatBalance(toppedUp, currency: balance.currency))")
                        }
                        Text("同步于 \(UIFormat.compactDate(balance.asOf))")
                        Text("来源：\(balance.source)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    if let isAvailable = balance.isAvailable {
                        Label(
                            isAvailable ? "官方标记可用" : "官方标记账户异常",
                            systemImage: isAvailable ? "checkmark.circle" : "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(isAvailable ? .green : .orange)
                    }
                }
                balanceChart(account: account, currency: balance.currency)
            }
        }

        Divider()
        thresholdSection(account)
    }

    @ViewBuilder
    private func balanceChart(account: Account, currency: String) -> some View {
        let series = model.balanceSnapshots(for: account)
            .first { $0.currency == currency }?.snapshots ?? []
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("余额快照曲线")
                    .font(.subheadline.weight(.semibold))
                if series.count < 2 {
                    Text("至少两次成功同步后显示曲线")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if series.count >= 2 {
                Chart(series) { snapshot in
                    LineMark(
                        x: .value("时间", snapshot.asOf),
                        y: .value("余额", NSDecimalNumber(decimal: snapshot.total).doubleValue)
                    )
                    PointMark(
                        x: .value("时间", snapshot.asOf),
                        y: .value("余额", NSDecimalNumber(decimal: snapshot.total).doubleValue)
                    )
                    .symbolSize(12)
                }
                .frame(height: 150)
                Text("余额快照，非逐请求 token 统计；每个点来自一次成功同步。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func thresholdSection(_ account: Account) -> some View {
        let threshold = account.balanceThreshold
        let balances = model.latestBalances(for: account)
        let relevant = balances.first { $0.currency == threshold?.currency }
        let status = model.balanceDataStatus(for: account)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("余额低水位阈值").font(.subheadline.weight(.semibold))
                if let threshold {
                    Text("阈值 \(Money.formatBalance(threshold.amount, currency: threshold.currency)) · 仅用于本地告警，不是官方限额")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if status.isActual, let relevant {
                        Text(
                            relevant.total < threshold.amount
                                ? "当前已低于阈值：\(Money.formatBalance(relevant.total, currency: relevant.currency))"
                                : "当前高于阈值：\(Money.formatBalance(relevant.total, currency: relevant.currency))"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(relevant.total < threshold.amount ? .orange : .green)
                    } else if !status.isActual {
                        Text("暂不评估阈值：\(status.reason ?? status.emptyLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !balances.isEmpty {
                        Text("该账户当前余额币种为 \(model.currencyLabel(for: account))，请重新设置阈值币种。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("未设置。阈值跟随账户币种；低于阈值时产生本地告警，回升到阈值以上后才重新布防。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(threshold == nil ? "设置阈值" : "编辑阈值") {
                thresholdAccount = account
            }
            .disabled(model.isDemo)
            if threshold != nil {
                Button("清除") {
                    do { try model.clearThreshold(account: account) }
                    catch { model.showBanner(error.localizedDescription, style: .error) }
                }
                .disabled(model.isDemo)
            }
        }
    }

    @ViewBuilder
    private func openRouterSection(_ account: Account) -> some View {
        Divider()
        let quota = model.latestQuota(for: account)
        let quotaName = account.provider == .openrouter ? "credits" : "额度"
        let status = model.creditDataStatus(for: account).prefixed("官方 \(quotaName)")
        if let quota {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("官方 \(quotaName) 剩余").font(.caption).foregroundStyle(.secondary)
                        DataValueLabel(
                            text: Money.formatBalance(quota.remaining, currency: quota.currency),
                            status: status,
                            font: .system(size: 30, weight: .semibold, design: .rounded)
                        )
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("总充值 \(Money.formatBalance(quota.totalCredits, currency: quota.currency))")
                        Text("总使用 \(Money.formatBalance(quota.totalUsage, currency: quota.currency))")
                        Text("同步于 \(UIFormat.compactDate(quota.asOf))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    if status.isActual, let percent = quota.usagePercent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("官方额度使用率").font(.caption).foregroundStyle(.secondary)
                            Text(Money.percent(percent))
                                .font(.headline)
                                .foregroundStyle(percent >= Decimal(90) ? .orange : .primary)
                        }
                    }
                }
                if status.isActual, let percent = quota.usagePercent {
                    ProgressView(
                        value: min(max(NSDecimalNumber(decimal: percent).doubleValue / 100.0, 0), 1)
                    )
                    .tint(percent >= 90 ? .orange : .blue)
                    Text("官方额度（total_credits − total_usage），不是本地预算。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !status.isActual {
                    statusMessage(status)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("官方 \(quotaName) 剩余").font(.caption).foregroundStyle(.secondary)
                        DataValueLabel(
                            text: "无数据",
                            status: status,
                            font: .system(size: 30, weight: .semibold, design: .rounded)
                        )
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("官方额度使用率").font(.caption).foregroundStyle(.secondary)
                        DataValueLabel(
                            text: "无数据",
                            status: status,
                            font: .headline
                        )
                    }
                }
                statusMessage(status)
            }
        }

        Divider()
        budgetSection(account)
    }

    @ViewBuilder
    private func budgetSection(_ account: Account) -> some View {
        let budget = account.budget
        let spend = model.budgetSpend(for: account)
        let ratio = model.budgetRatio(for: account)
        let remaining = model.budgetRemaining(for: account)
        let forecast = model.budgetForecast(for: account)
        let month = CalendarDay.monthRange(now: model.now)
        let analysisRange = model.currentRange
        let spendStatus = model.budgetSpendDataStatus(for: account).prefixed("本月已用")
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("本地预算", systemImage: "target")
                    .font(.subheadline.weight(.semibold))
                Text("按本机自然月 · 本地预算，不冒充官方额度")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(budget == nil ? "设置月度预算" : "编辑预算") {
                    budgetAccount = account
                }
                .disabled(model.isDemo)
                if budget != nil {
                    Button("清除") {
                        do { try model.clearBudget(account: account) }
                        catch { model.showBanner(error.localizedDescription, style: .error) }
                    }
                    .disabled(model.isDemo)
                }
            }
            if let budget {
                if let spend {
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("本月已用").font(.caption).foregroundStyle(.secondary)
                            Text(Money.formatCost(spend, currency: budget.currency))
                                .font(.title3.weight(.semibold))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("预算").font(.caption).foregroundStyle(.secondary)
                            Text(Money.formatBalance(budget.amount, currency: budget.currency))
                                .font(.title3.weight(.semibold))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text((remaining ?? 0) < 0 ? "超支" : "剩余")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(
                                remaining.map { Money.formatBalance(abs($0), currency: budget.currency) } ?? "—"
                            )
                            .font(.title3.weight(.semibold))
                            .foregroundStyle((remaining ?? 0) < 0 ? .red : .primary)
                        }
                        Spacer()
                        if let ratio {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("使用率").font(.caption).foregroundStyle(.secondary)
                                Text(Money.percent(ratio))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(ratio >= 100 ? .red : ratio >= 80 ? .orange : .green)
                            }
                        }
                    }
                    if let ratio {
                        BudgetProgressBar(ratio: ratio, isDemo: model.isDemo)
                    }
                    HStack {
                        Text("告知线 80% · 警戒线 100%（目标标记）")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let forecast {
                            Text("预估月末 \(Money.formatBalance(forecast, currency: budget.currency)) · 线性外推，仅供参考")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("本月已用按本机自然月 \(month.range.startDay) 至 \(month.range.endDay) 的厂商 UTC 日桶统计，可能不含今天且仅覆盖约 30 天窗口；不完整时不触发预算告警。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("本月已用").font(.caption).foregroundStyle(.secondary)
                            DataValueLabel(
                                text: "无数据",
                                status: spendStatus,
                                font: .title3.weight(.semibold)
                            )
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("预算").font(.caption).foregroundStyle(.secondary)
                            Text(Money.formatBalance(budget.amount, currency: budget.currency))
                                .font(.title3.weight(.semibold))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("剩余").font(.caption).foregroundStyle(.secondary)
                            DataValueLabel(
                                text: "—",
                                status: spendStatus,
                                font: .title3.weight(.semibold)
                            )
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("使用率").font(.caption).foregroundStyle(.secondary)
                            DataValueLabel(
                                text: "无数据",
                                status: spendStatus,
                                font: .title3.weight(.semibold)
                            )
                        }
                    }
                    Text(spendStatus.reason ?? "本月数据不完整，不计算剩余 / 预估，也不触发预算阈值告警。")
                        .font(.caption2)
                        .foregroundStyle(spendStatus.isActual ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                selectedRangeSection(
                    account: account,
                    budget: budget,
                    analysisRange: analysisRange,
                    month: month
                )
            } else {
                Text("未设置预算。设置后可查看使用率与 80% / 100% 告警；预算仅为本机设置。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }


    private func selectedRangeSection(
        account: Account,
        budget: Budget,
        analysisRange: DayRange,
        month: (monthKey: String, range: DayRange)
    ) -> some View {
        let selectedRecords = model.usageRecords.filter {
            $0.accountId == account.id
                && analysisRange.contains($0.day)
                && $0.currency == budget.currency
        }
        let selectedCosts = selectedRecords.compactMap(\.cost)
        let selectedStatus: DataStatus
        if account.credentialInvalid {
            selectedStatus = .failed("凭据失效：\(account.lastError ?? "需要重新输入 API Key")")
        } else if let error = account.lastError, !error.isEmpty {
            selectedStatus = .partial("同步失败：\(error)")
        } else if selectedRecords.isEmpty {
            selectedStatus = .missing("所选分析范围没有该账户的用量记录")
        } else if selectedCosts.isEmpty {
            selectedStatus = .missing("所选记录未提供费用字段")
        } else {
            selectedStatus = .actual
        }
        let selectedCostText = selectedCosts.isEmpty
            ? "无数据"
            : Money.formatCost(selectedCosts.reduce(Decimal(0), +), currency: budget.currency)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Label("所选分析范围", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                Text(analysisRange.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Text("该账户费用：")
                        .font(.caption.weight(.semibold))
                    DataValueLabel(
                        text: selectedCostText,
                        status: selectedStatus.prefixed("所选范围费用"),
                        font: .caption.weight(.semibold)
                    )
                }
            }
            Text("仅统计上述时间段内已同步的厂商 UTC 日桶，不参与本地月度预算和告警。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("本地预算周期：本机自然月 \(month.range.startDay) 至 \(month.range.endDay)；发生跨月时不会把所选范围当作预算周期。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

}

enum BudgetEditorKind {
    case budget
    case threshold
}

struct BudgetEditorView: View {
    @ObservedObject var model: AppModel
    let account: Account
    let kind: BudgetEditorKind
    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var currency: String
    @State private var errorMessage: String?

    init(model: AppModel, account: Account, kind: BudgetEditorKind) {
        self.model = model
        self.account = account
        self.kind = kind
        switch kind {
        case .budget:
            _amountText = State(initialValue: account.budget.map {
                NSDecimalNumber(decimal: $0.amount).stringValue
            } ?? "")
            _currency = State(initialValue: account.budget?.currency ?? "USD")
        case .threshold:
            _amountText = State(initialValue: account.balanceThreshold.map {
                NSDecimalNumber(decimal: $0.amount).stringValue
            } ?? "")
            let balances = model.latestBalances(for: account).map(\.currency)
            _currency = State(
                initialValue: account.balanceThreshold?.currency
                    ?? balances.first
                    ?? account.provider.defaultCurrency
            )
        }
    }

    private var title: String {
        kind == .budget ? "本地月度预算" : "余额低水位阈值"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                if model.isDemo { DemoTag() }
            }
            .padding(20)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text("\(account.displayName) · \(model.currencyLabel(for: account))").font(.headline)
                if kind == .budget {
                    Text("月度预算按本机自然月统计用量费用，仅用于本机告警，与厂商官方额度分开；使用率达到 80% / 100% 时各触发一次告警。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("当官方余额低于该值时触发本地告警；余额回升到阈值以上后自动重新布防。余额没有官方上限，因此不显示百分比额度。阈值只作用于当前账户，币种由该账户余额接口确定，不同账户 / 币种分开统计。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    TextField("金额", text: $amountText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    Picker("币种", selection: $currency) {
                        ForEach(currencyOptions, id: \.self) { code in Text(code).tag(code) }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                if let errorMessage {
                    InlineErrorView(message: errorMessage)
                }
                if model.isDemo {
                    Text("演示模式下的预算与阈值不可修改。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(20)
            Divider()
            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isDemo)
            }
            .padding(16)
        }
        .frame(width: 520)
    }

    private var currencyOptions: [String] {
        switch kind {
        case .budget:
            return ["USD"]
        case .threshold:
            var options = Set(model.latestBalances(for: account).map(\.currency))
            if let existing = account.balanceThreshold?.currency {
                options.insert(existing)
            }
            if options.isEmpty {
                options.insert(account.provider.defaultCurrency)
            }
            return options.sorted()
        }
    }

    private func save() {
        errorMessage = nil
        do {
            switch kind {
            case .budget:
                try model.saveBudget(account: account, amountText: amountText, currency: currency)
            case .threshold:
                try model.saveThreshold(account: account, amountText: amountText, currency: currency)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
