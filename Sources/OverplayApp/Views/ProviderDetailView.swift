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
            ProviderMark(provider: account.provider)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.displayName)
                        .font(.title3.weight(.semibold))
                    if model.isDemo || account.isDemo { DemoTag() }
                    if organizationTag { DetailTag(text: "组织级", color: .blue) }
                    if !account.enabled { DetailTag(text: "已禁用", color: .secondary) }
                }
                Text("\(account.provider.displayName) · \(model.capabilitySummary(for: account))")
                    .font(.caption)
                    .foregroundStyle(account.credentialInvalid ? .red : .secondary)
                Text("数据来源：\(sourceDescription) · 最近成功 \(lastSuccessText)")
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
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            .disabled(
                model.isDemo || !account.enabled || model.isSyncing(account)
                    || model.isRefreshCoolingDown(account)
            )
            .help(model.refreshBlockedReason(for: account) ?? "立即刷新该账户")
            Button("关闭") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .background(.regularMaterial)
    }

    private var sourceDescription: String {
        if account.provider == .deepseek { return "DeepSeek 官方余额快照（非逐请求 token）" }
        if account.provider == .openrouter { return "OpenRouter activity（约 30 天 UTC 日桶）" }
        if account.provider == .genericHTTP {
            return "通用 HTTP · GET \(account.genericConfig?.endpointPath ?? "/")"
        }
        if account.isDemo || model.isDemo { return "演示数据（不联网）" }
        return "\(account.provider.displayName) 官方只读接口"
    }

    private var lastSuccessText: String {
        account.lastSuccessAt.map { UIFormat.compactDate($0) } ?? "尚未成功同步"
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
        let costStatus: DataStatus = totals.costAvailable ? .actual : .missing("厂商未提供费用字段")
        let tokenStatus: DataStatus = totals.tokensAvailable ? .actual : .missing("厂商未提供 token 字段")
        let requestStatus: DataStatus = totals.requestsAvailable ? .actual : .missing("厂商未提供请求数字段")
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                DetailMetric(title: "Token", value: totals.tokensAvailable
                    ? "\(Money.formatCompactInteger(totals.totalTokens))"
                    : "厂商未提供", status: tokenStatus)
                DetailMetric(title: "费用", value: totals.costAvailable
                    ? UIFormat.costLines(totals.costs).map(\.0).joined(separator: " · ")
                    : "厂商未提供", status: costStatus)
                DetailMetric(title: "请求数", value: totals.requestsAvailable
                    ? Money.formatCompactInteger(totals.requests)
                    : "厂商未提供", status: requestStatus)
                Spacer()
            }
            HStack(spacing: 14) {
                Text("Prompt \(totals.tokensAvailable ? Money.formatCompactInteger(totals.promptTokens) : "未提供")")
                Text("Completion \(totals.tokensAvailable ? Money.formatCompactInteger(totals.completionTokens) : "未提供")")
                Text("Reasoning \(totals.tokensAvailable ? Money.formatCompactInteger(totals.reasoningTokens) : "未提供")")
                Text("Cached \(totals.tokensAvailable ? Money.formatCompactInteger(totals.cachedTokens) : "未提供")")
                if byokTotal > 0 {
                    Text("BYOK \(Money.formatCost(byokTotal, currency: usageCurrency ?? account.provider.defaultCurrency))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if let quota = model.latestQuota(for: account) {
                let status = model.creditDataStatus(for: account)
                HStack(spacing: 8) {
                    Text("官方 credits 剩余")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    DataValueLabel(
                        text: Money.formatBalance(quota.remaining, currency: quota.currency),
                        status: status,
                        font: .caption.weight(.semibold)
                    )
                    if status.isActual, let percent = quota.usagePercent {
                        Text("官方额度使用率 \(Money.percent(percent))（BYOK 与 credits 分开）")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let history = usageHistory {
                Text("\(metric.label) 首日 \(formatMetric(history.first)) → 末日 \(formatMetric(history.last)) · 峰值 \(formatMetric(history.peak))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("阶段统计来自当前记录；Reasoning 为 completion 子集、Cached 为 prompt 子集，不重复计入 token 总量。")
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
                    DetailMetric(title: "当前余额", value: "无数据", status: status)
                }
                ForEach(balances) { balance in
                    let series = model.balanceChartPoints(for: account, granularity: effectiveGranularity)
                        .filter { $0.currency == balance.currency }
                    DetailMetric(
                        title: "当前余额 · \(balance.currency)",
                        value: Money.formatBalance(balance.total, currency: balance.currency),
                        status: status
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("所选范围变化").font(.caption2).foregroundStyle(.secondary)
                        if let first = series.first, let last = series.last, series.count >= 2 {
                            let delta = last.value - first.value
                            Text("\(delta >= 0 ? "+" : "")\(String(format: "%.2f", delta))")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(delta < 0 ? .orange : .green)
                            Text("首点 \(String(format: "%.2f", first.value)) → 末点 \(String(format: "%.2f", last.value))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("至少两次成功同步后显示")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }
            if let threshold = account.balanceThreshold {
                Text("本地低水位阈值 \(Money.formatBalance(threshold.amount, currency: threshold.currency))；仅用于告警，不是官方上限。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("余额型厂商不提供逐请求 token / 费用历史；本页只绘制真实余额快照，不伪造 token 折线。")
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
            SectionCard(title: "厂商详情", isDemo: model.isDemo) {
                EmptyStateView(
                    symbol: "eye.slash",
                    title: "该厂商暂无可用图表",
                    message: "当前数据源没有提供用量、费用或余额能力；界面不会推断或伪造指标。"
                )
            }
        }
    }

    private var balanceChart: some View {
        let points = model.balanceChartPoints(for: account, granularity: effectiveGranularity)
        return SectionCard(
            title: "余额快照曲线",
            subtitle: "\(effectiveGranularity.label)粒度 · 非逐请求 token 统计",
            isDemo: model.isDemo
        ) {
            if points.isEmpty {
                chartEmpty("所选范围没有余额快照。余额曲线只使用真实同步点，不补 0、不连线伪造。")
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("余额", point.value)
                    )
                    .foregroundStyle(by: .value("币种", point.currency))
                    PointMark(
                        x: .value("时间", point.date),
                        y: .value("余额", point.value)
                    )
                    .foregroundStyle(by: .value("币种", point.currency))
                    .symbolSize(18)
                }
                .frame(height: 250)
                .chartLegend(position: .bottom)
                Text("每个点来自一次成功同步；切换粒度时每个时间桶保留最后一个快照，不做上采样。")
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
                return "\(effectiveGranularity.label)粒度 · \(usageCurrency ?? "无费用币种")"
            }
            return "\(effectiveGranularity.label)粒度 · \(metric.label)"
        }()
        return SectionCard(
            title: "按时间趋势",
            subtitle: subtitle,
            isDemo: model.isDemo
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("指标", selection: $metric) {
                    ForEach(UsageMetric.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                if !metricAvailable {
                    chartEmpty("厂商未提供\(metric.label)字段。缺失数据不显示为 0，也不伪造曲线。")
                } else if segments.isEmpty {
                    chartEmpty("所选范围没有可绘制的\(metric.label)数据；缺失日期保持空白。")
                } else {
                    Chart {
                        ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                            ForEach(segment) { point in
                                LineMark(
                                    x: .value("时间", chartDate(point.key)),
                                    y: .value(metric.label, point.value)
                                )
                                .foregroundStyle(by: .value("分段", "\(index)"))
                                PointMark(
                                    x: .value("时间", chartDate(point.key)),
                                    y: .value(metric.label, point.value)
                                )
                                .foregroundStyle(by: .value("分段", "\(index)"))
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
                    Label("OpenRouter 仅提供约 30 个 UTC 日窗口；超出部分留空，不补 0。", systemImage: "clock.badge.exclamationmark")
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
            "来源：\(sourceDescription)",
            "数据点按厂商实际记录绘制"
        ]
        if segments.count > 1 {
            parts.append("缺失日期已断开折线（\(segments.count) 段），未补 0")
        }
        if effectiveGranularity == .month || effectiveGranularity == .year {
            parts.append("由日级记录聚合")
        }
        if effectiveGranularity == .automatic {
            parts.append("自动使用日级数据")
        }
        if !granularities.contains(.minute) && !granularities.contains(.hour) {
            parts.append("厂商未提供分钟 / 小时粒度")
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
                Text("当前数据已过期，图表保留最近一次有效同步；不会把旧值当作实时数据。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("时间范围与筛选在主窗口各分析页共享；打开详情、切换范围或指标不会发起网络请求。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var capabilityNote: String? {
        if account.provider == .deepseek {
            return "DeepSeek：官方仅提供余额，不提供历史 token / 费用；余额快照粒度可切换。"
        }
        if account.provider == .openrouter {
            return "OpenRouter：用量窗口约 30 天（UTC 日桶）；BYOK 与 credits 分开统计；官方无余额。"
        }
        if account.provider == .genericHTTP {
            return "通用 HTTP：仅展示已映射并在响应中命中的字段；未配置指标不推断。"
        }
        if account.provider == .gemini {
            return "Gemini：真实 AI Studio 接口不提供逐 Key 用量 / 费用；本页演示平台数据仅用于功能展示。未配置指标不推断。"
        }
        if account.isDemo || model.isDemo {
            return "演示平台：数据为本地模拟，不联网、不读写 Keychain；不代表真实厂商能力。"
        }
        return "仅展示厂商实际提供并已同步的指标；未提供字段不会显示 0。"
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
