import Charts
import SwiftUI
import OverplayCore

struct ProviderDetailView: View {
    @ObservedObject var model: AppModel
    let account: Account
    @Environment(\.dismiss) private var dismiss
    @State private var metric: UsageMetric = .tokens

    private var granularities: [AnalysisGranularity] {
        model.analysisGranularities(for: account)
    }

    private var effectiveGranularity: AnalysisGranularity {
        let selected = model.selectedGranularity
        if granularities.contains(selected) { return selected }
        return .automatic
    }

    private var totals: ProviderUsageTotals {
        model.providerTotals(for: account)
    }

    private var records: [UsageRecord] {
        model.analysisRecords(for: account)
    }

    private var usageCurrency: String? {
        records.compactMap(\.currency).first
    }

    private var byokTotal: Decimal {
        records.compactMap(\.byokCost).reduce(Decimal(0), +)
    }

    private var organizationTag: Bool {
        [.openai, .anthropic].contains(account.provider)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AnalysisRangeControls(
                        model: model,
                        showsGranularity: true,
                        granularities: granularities
                    )
                    if let issue = model.dataIssue(for: account) {
                        AnomalyNotice(message: issue)
                    }
                    summary
                    chartSection
                    notes
                }
                .padding(20)
            }
        }
        .frame(minWidth: 820, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.providerDetailVisible = true }
        .onDisappear { model.providerDetailVisible = false }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ProviderMark(provider: account.provider, iconName: account.iconName)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.displayName)
                        .font(.title3.weight(.semibold))
                    if model.isDemo || account.isDemo { DemoTag() }
                    if organizationTag { DetailTag(text: L10n.t("providerDetail.9e4000b2b7"), color: .blue) }
                    if !account.enabled { DetailTag(text: L10n.t("health.disabled"), color: .secondary) }
                }
                Text(
                    [
                        account.provider.displayName,
                        account.officialName.map { L10n.f("settings.cf2ff9d62a", $0) },
                        model.capabilitySummary(for: account)
                    ].compactMap { $0 }.joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(account.credentialInvalid ? .red : .secondary)
                Text(L10n.f("providerDetail.2fa6817f01", sourceDescription, lastSuccessText))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HealthBadge(health: model.health(for: account))
            Button {
                model.refresh(account: account)
            } label: {
                if model.isSyncing(account) {
                    ProgressView().controlSize(.small)
                } else {
                    Label(L10n.t("providerDetail.38108eaa1d"), systemImage: "arrow.clockwise")
                }
            }
            .disabled(
                model.isDemo || !account.enabled || model.isSyncing(account)
                    || model.isRefreshCoolingDown(account)
            )
            .help(model.refreshBlockedReason(for: account).map(L10n.t) ?? L10n.t("providerDetail.03e03ba84f"))
            Button(L10n.t("common.close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .background(.regularMaterial)
    }

    private var sourceDescription: String {
        if account.provider == .deepseek { return L10n.t("providerDetail.1b392ce08e") }
        if account.provider == .openrouter { return L10n.t("providerDetail.0a3540c180") }
        if account.provider == .genericHTTP {
            return L10n.f("core.genericHTTP.9ab64c049d", account.genericConfig?.endpointPath ?? "/")
        }
        if account.isDemo || model.isDemo { return L10n.t("providerDetail.8f24f04bfc") }
        return L10n.f("providerDetail.de16fb12da", account.provider.displayName)
    }

    private var lastSuccessText: String {
        account.lastSuccessAt.map { UIFormat.compactDate($0) } ?? L10n.t("app.52e38de1f4")
    }

    @ViewBuilder
    private var summary: some View {
        if account.capabilities.balance && !account.capabilities.usage {
            balanceSummary
        } else {
            usageSummary
        }
    }

    private var usageSummary: some View {
        let costStatus: DataStatus = totals.costAvailable ? .actual : .missing(L10n.t("providerDetail.dc841f4746"))
        let tokenStatus: DataStatus = totals.tokensAvailable ? .actual : .missing(L10n.t("providerDetail.914fce6f29"))
        let requestStatus: DataStatus = totals.requestsAvailable ? .actual : .missing(L10n.t("providerDetail.a8e8d095a4"))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                DetailMetric(title: "Token", value: totals.tokensAvailable
                    ? "\(Money.formatCompactInteger(totals.totalTokens))"
                    : L10n.t("providerDetail.567cdafa2a"), status: tokenStatus)
                DetailMetric(title: L10n.t("metric.cost"), value: totals.costAvailable
                    ? UIFormat.costLines(totals.costs).map(\.0).joined(separator: " · ")
                    : L10n.t("providerDetail.567cdafa2a"), status: costStatus)
                DetailMetric(title: L10n.t("core.analysisRange.b28376ff80"), value: totals.requestsAvailable
                    ? Money.formatCompactInteger(totals.requests)
                    : L10n.t("providerDetail.567cdafa2a"), status: requestStatus)
                Spacer()
            }
            HStack(spacing: 14) {
                Text("Prompt \(totals.tokensAvailable ? Money.formatCompactInteger(totals.promptTokens) : L10n.t("core.csv.071fb244ea"))")
                Text("Completion \(totals.tokensAvailable ? Money.formatCompactInteger(totals.completionTokens) : L10n.t("core.csv.071fb244ea"))")
                Text("Reasoning \(totals.tokensAvailable ? Money.formatCompactInteger(totals.reasoningTokens) : L10n.t("core.csv.071fb244ea"))")
                Text("Cached \(totals.tokensAvailable ? Money.formatCompactInteger(totals.cachedTokens) : L10n.t("core.csv.071fb244ea"))")
                if byokTotal > 0 {
                    Text("BYOK \(Money.formatCost(byokTotal, currency: usageCurrency ?? account.provider.defaultCurrency))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if let quota = model.latestQuota(for: account) {
                let status = model.creditDataStatus(for: account)
                HStack(spacing: 8) {
                    Text(L10n.t("providerDetail.281dbbb3e2"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    DataValueLabel(
                        text: Money.formatBalance(quota.remaining, currency: quota.currency),
                        status: status,
                        font: .caption.weight(.semibold)
                    )
                    if status.isActual, let percent = quota.usagePercent {
                        Text(L10n.f("providerDetail.30f846184a", Money.percent(percent)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let history = usageHistory {
                Text(L10n.f("providerDetail.5d423def9b", metric.label, formatMetric(history.first), formatMetric(history.last), formatMetric(history.peak)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(L10n.t("providerDetail.b7705779fd"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var usageHistory: (first: Double, last: Double, peak: Double)? {
        let values = AnalysisChartMath.dailyValues(
            records: records,
            metric: metric,
            currency: usageCurrency
        )
        let days = values.keys.sorted()
        guard let firstDay = days.first,
              let lastDay = days.last,
              let first = values[firstDay],
              let last = values[lastDay] else { return nil }
        return (first, last, values.values.max() ?? last)
    }

    private func formatMetric(_ value: Double) -> String {
        switch metric {
        case .tokens, .requests:
            return Money.formatCompactInteger(Int(value.rounded()))
        case .cost:
            return Money.formatCost(
                Decimal(value),
                currency: usageCurrency ?? account.provider.defaultCurrency
            )
        }
    }

    private var balanceSummary: some View {
        let balances = model.latestBalances(for: account)
        let status = model.balanceDataStatus(for: account)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 24) {
                if balances.isEmpty {
                    DetailMetric(title: L10n.t("providerDetail.f11215f8f6"), value: L10n.t("dataStatus.6ffa7e6d35"), status: status)
                }
                ForEach(balances) { balance in
                    let series = model.balanceChartPoints(for: account, granularity: effectiveGranularity)
                        .filter { $0.currency == balance.currency }
                    DetailMetric(
                        title: L10n.f("providerDetail.59a789d878", balance.currency),
                        value: Money.formatBalance(balance.total, currency: balance.currency),
                        status: status
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("providerDetail.2accb8e1c8")).font(.caption2).foregroundStyle(.secondary)
                        if let first = series.first, let last = series.last, series.count >= 2 {
                            let delta = last.value - first.value
                            Text("\(delta >= 0 ? "+" : "")\(String(format: "%.2f", delta))")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(delta < 0 ? .orange : .green)
                            Text(L10n.f("providerDetail.9ba37104d3", String(format: "%.2f", first.value), String(format: "%.2f", last.value)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(L10n.t("providerDetail.ac6b204e44"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }
            if let threshold = account.balanceThreshold {
                Text(L10n.f("providerDetail.61708d4a30", Money.formatBalance(threshold.amount, currency: threshold.currency)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(L10n.t("providerDetail.5e1d8e9560"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        if account.capabilities.balance && !account.capabilities.usage {
            balanceChart
        } else if account.capabilities.usage {
            usageChart
        } else {
            SectionCard(title: L10n.t("providerDetail.591110d871"), isDemo: model.isDemo) {
                EmptyStateView(
                    symbol: "eye.slash",
                    title: L10n.t("providerDetail.bea950ed5b"),
                    message: L10n.t("providerDetail.26a776e85f")
                )
            }
        }
    }

    private var balanceChart: some View {
        let points = model.balanceChartPoints(for: account, granularity: effectiveGranularity)
        return SectionCard(
            title: L10n.t("providerDetail.e8d3eb94c4"),
            subtitle: L10n.f("providerDetail.8634513206", effectiveGranularity.label),
            isDemo: model.isDemo
        ) {
            if points.isEmpty {
                chartEmpty(L10n.t("providerDetail.ed97af3c13"))
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value(L10n.t("messages.89b4aa6364"), point.date),
                        y: .value(L10n.t("metric.balance"), point.value)
                    )
                    .foregroundStyle(by: .value(L10n.t("core.csv.a81ab5e100"), point.currency))
                    PointMark(
                        x: .value(L10n.t("messages.89b4aa6364"), point.date),
                        y: .value(L10n.t("metric.balance"), point.value)
                    )
                    .foregroundStyle(by: .value(L10n.t("core.csv.a81ab5e100"), point.currency))
                    .symbolSize(18)
                }
                .frame(height: 250)
                .chartLegend(position: .bottom)
                Text(L10n.t("providerDetail.62dfde54ec"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var usageChart: some View {
        let segments = model.usageSegments(
            for: account,
            metric: metric,
            granularity: effectiveGranularity
        )
        let metricAvailable: Bool = {
            switch metric {
            case .tokens: return totals.tokensAvailable
            case .cost: return totals.costAvailable
            case .requests: return totals.requestsAvailable
            }
        }()
        let subtitle: String = {
            if metric == .cost {
                return L10n.f("providerDetail.3a4150af97", effectiveGranularity.label, usageCurrency ?? L10n.t("common.noCostCurrency"))
            }
            return L10n.f("providerDetail.3a4150af97", effectiveGranularity.label, metric.label)
        }()
        return SectionCard(
            title: L10n.t("providerDetail.fffa79c0de"),
            subtitle: subtitle,
            isDemo: model.isDemo
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Picker(L10n.t("providerDetail.1dfc810a7b"), selection: $metric) {
                    ForEach(UsageMetric.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                if !metricAvailable {
                    chartEmpty(L10n.f("providerDetail.aa709830af", metric.label))
                } else if segments.isEmpty {
                    chartEmpty(L10n.f("providerDetail.8c803e652f", metric.label))
                } else {
                    Chart {
                        ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                            ForEach(segment) { point in
                                LineMark(
                                    x: .value(L10n.t("messages.89b4aa6364"), chartDate(point.key)),
                                    y: .value(metric.label, point.value)
                                )
                                .foregroundStyle(by: .value(L10n.t("providerDetail.21ce5adddf"), "\(index)"))
                                PointMark(
                                    x: .value(L10n.t("messages.89b4aa6364"), chartDate(point.key)),
                                    y: .value(metric.label, point.value)
                                )
                                .foregroundStyle(by: .value(L10n.t("providerDetail.21ce5adddf"), "\(index)"))
                                .symbolSize(10)
                            }
                        }
                    }
                    .chartLegend(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 7)) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: axisDateFormat)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let number = value.as(Double.self) {
                                    Text(axisLabel(number))
                                }
                            }
                        }
                    }
                    .frame(height: 260)
                    Text(chartFootnote(segments: segments))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if account.provider == .openrouter && daysInRange > 30 {
                    Label(L10n.t("providerDetail.4df99aa7e5"), systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var daysInRange: Int {
        CalendarDay.days(from: model.currentRange).count
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = CalendarDay.utc
        return calendar
    }

    private func chartDate(_ key: String) -> Date {
        let text: String
        switch effectiveGranularity {
        case .month:
            text = "\(key)-01"
        case .year:
            text = "\(key)-01-01"
        default:
            text = key
        }
        return CalendarDay.date(from: text, timeZone: CalendarDay.utc, calendar: utcCalendar)
            ?? Date.distantPast
    }

    private var axisDateFormat: Date.FormatStyle {
        switch effectiveGranularity {
        case .month:
            return .dateTime.year(.twoDigits).month(.twoDigits)
        case .year:
            return .dateTime.year()
        default:
            return .dateTime.month(.twoDigits).day(.twoDigits)
        }
    }

    private func chartFootnote(segments: [[UsageChartPoint]]) -> String {
        var parts = [
            L10n.f("providerDetail.9c7669354e", sourceDescription),
            L10n.t("providerDetail.eb4432e51a")
        ]
        if segments.count > 1 {
            parts.append(L10n.f("providerDetail.435d9ce718", segments.count))
        }
        if effectiveGranularity == .month || effectiveGranularity == .year {
            parts.append(L10n.t("providerDetail.1bfc90969d"))
        }
        if effectiveGranularity == .automatic {
            parts.append(L10n.t("providerDetail.41ed155ea7"))
        }
        if !granularities.contains(.minute) && !granularities.contains(.hour) {
            parts.append(L10n.t("providerDetail.3828196d0c"))
        }
        return parts.joined(separator: " · ")
    }

    private func chartEmpty(_ message: String) -> some View {
        HStack {
            Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
    }

    private func axisLabel(_ value: Double) -> String {
        switch metric {
        case .tokens, .requests:
            return Money.formatCompactInteger(Int(value.rounded()))
        case .cost:
            return String(format: "%.2f", value)
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let note = capabilityNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if model.isStale(account) {
                Text(L10n.t("providerDetail.90492437a5"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text(L10n.t("providerDetail.5430d3d8b6"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var capabilityNote: String? {
        if account.provider == .deepseek {
            return L10n.t("providerDetail.9103c919e3")
        }
        if account.provider == .openrouter {
            return L10n.t("providerDetail.9e1102f0a0")
        }
        if account.provider == .genericHTTP {
            return L10n.t("providerDetail.44c4a8ebd3")
        }
        if account.provider == .gemini {
            return L10n.t("providerDetail.83319110e4")
        }
        if account.isDemo || model.isDemo {
            return L10n.t("providerDetail.b57d32e387")
        }
        return L10n.t("providerDetail.a510611baa")
    }
}

private struct DetailMetric: View {
    var title: String
    var value: String
    var status: DataStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            DataValueLabel(
                text: value,
                status: status,
                font: .system(size: 22, weight: .semibold, design: .rounded)
            )
        }
    }
}

private struct DetailTag: View {
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
