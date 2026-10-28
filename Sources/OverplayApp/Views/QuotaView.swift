import Charts
import SwiftUI
import OverplayCore

struct QuotaView: View {
    @ObservedObject var model: AppModel
    @State private var budgetAccount: Account?
    @State private var thresholdAccount: Account?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.accounts.isEmpty {
                EmptyStateView(
                    symbol: "gauge.with.dots.needle.50percent",
                    title: "暂无账户",
                    message: "添加 DeepSeek 或 OpenRouter 账户后，可在此查看官方余额、credits 与本地预算。"
                )
            } else {
                ForEach(model.accounts) { account in
                    accountSection(account)
                }
            }
            alertHistory
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
                    ProviderMark(provider: account.provider)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(account.displayName).font(.headline)
                            if model.isDemo || account.isDemo { DemoTag() }
                        }
                        Text(account.provider.displayName + " · " + model.capabilitySummary(for: account))
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

                if account.provider == .deepseek {
                    deepSeekSection(account)
                } else {
                    openRouterSection(account)
                }
            }
        }
    }

    @ViewBuilder
    private func deepSeekSection(_ account: Account) -> some View {
        let balances = model.latestBalances(for: account)
        Divider()
        if balances.isEmpty {
            Text(model.health(for: account) == .neverSynced ? "尚未同步余额。" : "厂商未提供余额数据。")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ForEach(balances) { balance in
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("官方余额 · \(balance.currency)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Money.formatBalance(balance.total, currency: balance.currency))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
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
                            isAvailable ? "官方标记可用" : "官方标记不可用",
                            systemImage: isAvailable ? "checkmark.circle" : "xmark.circle"
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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("余额低水位阈值").font(.subheadline.weight(.semibold))
                if let threshold {
                    Text("阈值 \(Money.formatBalance(threshold.amount, currency: threshold.currency)) · 仅用于本地告警，不是官方限额")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let relevant {
                        Text(
                            relevant.total < threshold.amount
                                ? "当前已低于阈值：\(Money.formatBalance(relevant.total, currency: relevant.currency))"
                                : "当前高于阈值：\(Money.formatBalance(relevant.total, currency: relevant.currency))"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(relevant.total < threshold.amount ? .orange : .green)
                    }
                } else {
                    Text("未设置。低于阈值时产生本地告警；回升到阈值以上后才重新布防。")
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
        if let quota {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("官方 credits 剩余").font(.caption).foregroundStyle(.secondary)
                        Text(Money.formatBalance(quota.remaining, currency: quota.currency))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("总充值 \(Money.formatBalance(quota.totalCredits, currency: quota.currency))")
                        Text("总使用 \(Money.formatBalance(quota.totalUsage, currency: quota.currency))")
                        Text("同步于 \(UIFormat.compactDate(quota.asOf))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    if let percent = quota.usagePercent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("官方额度使用率").font(.caption).foregroundStyle(.secondary)
                            Text(Money.percent(percent))
                                .font(.headline)
                                .foregroundStyle(percent >= Decimal(90) ? .orange : .primary)
                        }
                    }
                }
                if let percent = quota.usagePercent {
                    ProgressView(
                        value: min(max(NSDecimalNumber(decimal: percent).doubleValue / 100.0, 0), 1)
                    )
                    .tint(percent >= 90 ? .orange : .blue)
                    Text("官方额度（total_credits − total_usage），不是本地预算。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("尚未获取 credits。需要 OpenRouter Management Key。")
                .font(.callout)
                .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("本地预算", systemImage: "target")
                    .font(.subheadline.weight(.semibold))
                Text("按自然月 · 本地预算，不冒充官方额度")
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
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("本月已用").font(.caption).foregroundStyle(.secondary)
                        Text(
                            spend.map { Money.formatCost($0, currency: budget.currency) } ?? "暂无数据"
                        )
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
                BudgetProgressBar(ratio: ratio, isDemo: model.isDemo)
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
                Text("本月已用按 OpenRouter UTC 日桶统计，可能不含今天，且仅覆盖接口约 30 天窗口；数据不完整时不触发预算告警。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("未设置预算。设置后可查看使用率与 80% / 100% 告警；预算仅为本机设置。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var alertHistory: some View {
        SectionCard(
            title: "告警记录",
            subtitle: "\(model.alerts.count) 条",
            isDemo: model.isDemo
        ) {
            if model.alerts.isEmpty {
                HStack {
                    Image(systemName: "bell.slash").foregroundStyle(.secondary)
                    Text("暂无告警记录。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(model.alerts.prefix(50))) { alert in
                    AlertRowView(
                        alert: alert,
                        isDemo: model.isDemo,
                        onAcknowledge: { model.acknowledge(alert) }
                    )
                    if alert.id != model.alerts.prefix(50).last?.id {
                        Divider()
                    }
                }
                if model.alerts.count > 50 {
                    Text("仅显示最近 50 条；完整记录保存在本地数据库。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
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
            _currency = State(initialValue: account.balanceThreshold?.currency ?? balances.first ?? "CNY")
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
                Text(account.displayName).font(.headline)
                if kind == .budget {
                    Text("OpenRouter 月度预算仅用于本机告警，与官方 credits 额度分开；使用率达到 80% / 100% 时各触发一次告警。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("当官方余额低于该值时触发本地告警；余额回升到阈值以上后自动重新布防。余额没有官方上限，因此不显示百分比额度。")
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
            let balances = model.latestBalances(for: account).map(\.currency)
            return Array(Set(balances + ["CNY", "USD"])).sorted()
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
