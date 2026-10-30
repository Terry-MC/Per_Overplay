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
                    title: L10n.t("floating.d125522fc6"),
                    message: L10n.t("quota.7bf947867e")
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
            account.officialName.map { L10n.f("settings.cf2ff9d62a", $0) },
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
        let status = model.balanceDataStatus(for: account).prefixed(L10n.t("core.floatingSummary.f5f1ad2311"))
        Divider()
        if balances.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.f("quota.e0544e29c7", model.currencyLabel(for: account)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DataValueLabel(
                            text: L10n.t("dataStatus.6ffa7e6d35"),
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
                        Text(L10n.f("quota.e0544e29c7", balance.currency))
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
                            Text(L10n.f("quota.6e36924888", Money.formatBalance(granted, currency: balance.currency)))
                        }
                        if let toppedUp = balance.toppedUp {
                            Text(L10n.f("quota.b930474be4", Money.formatBalance(toppedUp, currency: balance.currency)))
                        }
                        Text(L10n.f("quota.d2b9869a69", UIFormat.compactDate(balance.asOf)))
                        Text(L10n.f("providerDetail.9c7669354e", balance.source))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    if let isAvailable = balance.isAvailable {
                        Label(
                            isAvailable ? L10n.t("quota.4115ef85ea") : L10n.t("quota.9d3bed6bbf"),
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
                Text(L10n.t("providerDetail.e8d3eb94c4"))
                    .font(.subheadline.weight(.semibold))
                if series.count < 2 {
                    Text(L10n.t("quota.256fb6c637"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if series.count >= 2 {
                Chart(series) { snapshot in
                    LineMark(
                        x: .value(L10n.t("messages.89b4aa6364"), snapshot.asOf),
                        y: .value(L10n.t("metric.balance"), NSDecimalNumber(decimal: snapshot.total).doubleValue)
                    )
                    PointMark(
                        x: .value(L10n.t("messages.89b4aa6364"), snapshot.asOf),
                        y: .value(L10n.t("metric.balance"), NSDecimalNumber(decimal: snapshot.total).doubleValue)
                    )
                    .symbolSize(12)
                }
                .frame(height: 150)
                Text(L10n.t("quota.2234781b0f"))
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
                Text(L10n.t("quota.66d3cf61d5")).font(.subheadline.weight(.semibold))
                if let threshold {
                    Text(L10n.f("quota.dcd688e398", Money.formatBalance(threshold.amount, currency: threshold.currency)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if status.isActual, let relevant {
                        Text(
                            relevant.total < threshold.amount
                                ? L10n.f("quota.56327695e5", Money.formatBalance(relevant.total, currency: relevant.currency))
                                : L10n.f("quota.c5532e2ff5", Money.formatBalance(relevant.total, currency: relevant.currency))
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(relevant.total < threshold.amount ? .orange : .green)
                    } else if !status.isActual {
                        Text(L10n.f("quota.a3da00bf3a", status.reason ?? status.emptyLabel))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !balances.isEmpty {
                        Text(L10n.f("quota.995f4d16f1", model.currencyLabel(for: account)))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text(L10n.t("quota.d41cd7e642"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(threshold == nil ? L10n.t("quota.21d4e2e365") : L10n.t("quota.e200ee3482")) {
                thresholdAccount = account
            }
            .disabled(model.isDemo)
            if threshold != nil {
                Button(L10n.t("quota.7b15e5e8e7")) {
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
        let quotaName = account.provider == .openrouter ? "credits" : L10n.t("menuBar.3fa9a9d38e")
        let status = model.creditDataStatus(for: account).prefixed(L10n.f("settings.cf2ff9d62a", quotaName))
        if let quota {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.f("quota.2c976d79ba", quotaName)).font(.caption).foregroundStyle(.secondary)
                        DataValueLabel(
                            text: Money.formatBalance(quota.remaining, currency: quota.currency),
                            status: status,
                            font: .system(size: 30, weight: .semibold, design: .rounded)
                        )
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.f("quota.7358a6b955", Money.formatBalance(quota.totalCredits, currency: quota.currency)))
                        Text(L10n.f("quota.fd5c51f3c0", Money.formatBalance(quota.totalUsage, currency: quota.currency)))
                        Text(L10n.f("quota.d2b9869a69", UIFormat.compactDate(quota.asOf)))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    if status.isActual, let percent = quota.usagePercent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(L10n.t("quota.9bfba85a1b")).font(.caption).foregroundStyle(.secondary)
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
                    Text(L10n.t("quota.1074f6570d"))
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
                        Text(L10n.f("quota.2c976d79ba", quotaName)).font(.caption).foregroundStyle(.secondary)
                        DataValueLabel(
                            text: L10n.t("dataStatus.6ffa7e6d35"),
                            status: status,
                            font: .system(size: 30, weight: .semibold, design: .rounded)
                        )
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(L10n.t("quota.9bfba85a1b")).font(.caption).foregroundStyle(.secondary)
                        DataValueLabel(
                            text: L10n.t("dataStatus.6ffa7e6d35"),
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
        let spendStatus = model.budgetSpendDataStatus(for: account).prefixed(L10n.t("quota.166b33d15f"))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.t("quota.4cbf7880a6"), systemImage: "target")
                    .font(.subheadline.weight(.semibold))
                Text(L10n.t("quota.96370f99b4"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(budget == nil ? L10n.t("quota.acc3fd7eee") : L10n.t("quota.d20c8474fe")) {
                    budgetAccount = account
                }
                .disabled(model.isDemo)
                if budget != nil {
                    Button(L10n.t("quota.7b15e5e8e7")) {
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
                            Text(L10n.t("quota.166b33d15f")).font(.caption).foregroundStyle(.secondary)
                            Text(Money.formatCost(spend, currency: budget.currency))
                                .font(.title3.weight(.semibold))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("metric.budget")).font(.caption).foregroundStyle(.secondary)
                            Text(Money.formatBalance(budget.amount, currency: budget.currency))
                                .font(.title3.weight(.semibold))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text((remaining ?? 0) < 0 ? L10n.t("quota.816627f615") : L10n.t("quota.f37c034a97"))
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
                                Text(L10n.t("quota.8ca02f90d1")).font(.caption).foregroundStyle(.secondary)
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
                        Text(L10n.t("quota.4afc9a9265"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let forecast {
                            Text(L10n.f("quota.9f82c4753e", Money.formatBalance(forecast, currency: budget.currency)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(L10n.f("quota.9b8210b7a5", month.range.startDay, month.range.endDay))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("quota.166b33d15f")).font(.caption).foregroundStyle(.secondary)
                            DataValueLabel(
                                text: L10n.t("dataStatus.6ffa7e6d35"),
                                status: spendStatus,
                                font: .title3.weight(.semibold)
                            )
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("metric.budget")).font(.caption).foregroundStyle(.secondary)
                            Text(Money.formatBalance(budget.amount, currency: budget.currency))
                                .font(.title3.weight(.semibold))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("quota.f37c034a97")).font(.caption).foregroundStyle(.secondary)
                            DataValueLabel(
                                text: "—",
                                status: spendStatus,
                                font: .title3.weight(.semibold)
                            )
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(L10n.t("quota.8ca02f90d1")).font(.caption).foregroundStyle(.secondary)
                            DataValueLabel(
                                text: L10n.t("dataStatus.6ffa7e6d35"),
                                status: spendStatus,
                                font: .title3.weight(.semibold)
                            )
                        }
                    }
                    Text(spendStatus.reason ?? L10n.t("quota.a2cdc74805"))
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
                Text(L10n.t("quota.82ca86054e"))
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
            selectedStatus = .failed(L10n.f("app.29dd8b4768", L10n.t(account.lastError ?? L10n.t("credential.fallback.apiKey"))))
        } else if let error = account.lastError, !error.isEmpty {
            selectedStatus = .partial(L10n.f("app.b3c04fc986", L10n.t(error)))
        } else if selectedRecords.isEmpty {
            selectedStatus = .missing(L10n.t("quota.12a24af6db"))
        } else if selectedCosts.isEmpty {
            selectedStatus = .missing(L10n.t("quota.d8dc076c65"))
        } else {
            selectedStatus = .actual
        }
        let selectedCostText = selectedCosts.isEmpty
            ? L10n.t("dataStatus.6ffa7e6d35")
            : Money.formatCost(selectedCosts.reduce(Decimal(0), +), currency: budget.currency)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Label(L10n.t("quota.b98dcfe557"), systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                Text(analysisRange.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Text(L10n.t("quota.94ab47117b"))
                        .font(.caption.weight(.semibold))
                    DataValueLabel(
                        text: selectedCostText,
                        status: selectedStatus.prefixed(L10n.t("core.floatingSummary.7a286de355")),
                        font: .caption.weight(.semibold)
                    )
                }
            }
            Text(L10n.t("quota.00e05f6d46"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(L10n.f("quota.5ed2de8c3c", month.range.startDay, month.range.endDay))
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
        kind == .budget ? L10n.t("quota.651d436ef1") : L10n.t("quota.66d3cf61d5")
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
                    Text(L10n.t("quota.a0d01785c8"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L10n.t("quota.9df43387c3"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    TextField(L10n.t("quota.34943c40c9"), text: $amountText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    Picker(L10n.t("core.csv.a81ab5e100"), selection: $currency) {
                        ForEach(currencyOptions, id: \.self) { code in Text(code).tag(code) }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                if let errorMessage {
                    InlineErrorView(message: errorMessage)
                }
                if model.isDemo {
                    Text(L10n.t("quota.0d99a40ae4"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(20)
            Divider()
            HStack {
                Button(L10n.t("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.t("common.save")) { save() }
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
