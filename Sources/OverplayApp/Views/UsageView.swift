import Charts
import SwiftUI
import OverplayCore

struct UsageView: View {
    @ObservedObject var model: AppModel

    private var records: [UsageRecord] { model.currentRecords }
    private var currency: String? { model.effectiveCurrency }
    private var costSeries: [DailyCostPoint] {
        guard let currency else { return [] }
        return model.dailyCostSeries(records: records, currency: currency)
    }
    private var tokenSeries: [DailyTokenPoint] { model.dailyTokenSeries(records: records) }
    private var modelUsages: [ModelUsage] { model.modelUsage(records: records, currency: currency) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            controls
            if records.isEmpty {
                emptyRecordsState
                missingDataNotes
            } else {
                summaryCards
                chartsAndTables
                missingDataNotes
            }

            Text("费用和 tokens 仅来自各厂商官方只读接口；不调用推理接口。CSV 导出仅包含当前筛选，且不包含任何凭证。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyRecordsState: some View {
        SectionCard(isDemo: model.isDemo) {
            EmptyStateView(
                symbol: "chart.bar.doc.horizontal",
                title: "所选范围没有用量数据",
                message: model.hasUsageFilters
                    ? "当前账户 / 模型筛选没有匹配记录。可清除筛选或切换时间范围。"
                    : "OpenRouter 仅提供最近约 30 个 UTC 日；DeepSeek 官方不提供历史 token / 费用接口。缺失数据不会以 0 补齐。"
            ) {
                if model.hasUsageFilters {
                    Button("清除筛选") { model.resetUsageFilters() }
                }
            }
        }
    }

    private var chartsAndTables: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionCard(
                title: "费用趋势",
                subtitle: currency.map { "按厂商堆叠 · \($0) · 厂商 UTC 日" } ?? "无费用数据",
                isDemo: model.isDemo
            ) {
                if costSeries.isEmpty {
                    emptyChart("没有可绘制的费用数据。缺失数据不会以 0 补齐。")
                } else {
                    Chart(costSeries) { point in
                        BarMark(
                            x: .value("日期", point.day),
                            y: .value("费用", point.cost)
                        )
                        .foregroundStyle(by: .value("厂商", point.provider))
                    }
                    .chartXAxis {
                        AxisMarks(values: axisDayValues(costSeries.map(\.day))) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let day = value.as(String.self) {
                                    Text(shortDay(day))
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let number = value.as(Double.self) {
                                    Text(String(format: "%.2f", number))
                                }
                            }
                        }
                    }
                    .frame(height: 230)
                    Text("来源：OpenRouter 官方 activity（其余厂商未提供费用）。仅绘制有数据的日期。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SectionCard(
                title: "Token 趋势",
                subtitle: "仅包含提供实际 token 数据的厂商",
                isDemo: model.isDemo
            ) {
                if tokenSeries.isEmpty {
                    emptyChart("厂商未提供 token 历史。DeepSeek 无历史用量接口；缺失数据不显示为 0。")
                } else {
                    Chart {
                        ForEach(tokenSeries) { point in
                            if point.promptAvailable {
                                LineMark(
                                    x: .value("日期", point.day),
                                    y: .value("tokens", point.prompt)
                                )
                                .foregroundStyle(by: .value("类型", "Prompt"))
                                .interpolationMethod(.monotone)
                            }
                            if point.completionAvailable {
                                LineMark(
                                    x: .value("日期", point.day),
                                    y: .value("tokens", point.completion)
                                )
                                .foregroundStyle(by: .value("类型", "Completion"))
                                .interpolationMethod(.monotone)
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: axisDayValues(tokenSeries.map(\.day))) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let day = value.as(String.self) {
                                    Text(shortDay(day))
                                }
                            }
                        }
                    }
                    .frame(height: 210)
                    Text("Reasoning tokens 已由厂商单列，不重复计入 totals；OpenRouter 用量窗口约 30 个 UTC 日。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if modelUsages.isEmpty {
                SectionCard(title: "模型拆分", subtitle: "无数据", isDemo: model.isDemo) {
                    Text("所选范围没有可用的模型级数据。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                modelBreakdown
            }

            detailTable
        }
    }

    @ViewBuilder
    private var missingDataNotes: some View {
        let availableAccounts = Set(model.unfilteredRecords.map(\.accountId))
        let gaps = model.accounts.filter {
            !$0.capabilities.usage || !availableAccounts.contains($0.id)
        }
        if !gaps.isEmpty {
            SectionCard(title: "数据缺口", isDemo: model.isDemo) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(gaps) { account in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName)
                                    .font(.caption.weight(.semibold))
                                if !account.capabilities.usage {
                                    Text("厂商未提供历史 token / 费用数据。DeepSeek 官方仅提供余额快照，界面不会以 0 或伪造曲线替代。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("所选范围无 activity 记录。OpenRouter 仅覆盖最近约 30 个 UTC 日；请检查同步状态或时间范围。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Picker("范围", selection: $model.selectedPreset) {
                ForEach(AnalysisPreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 230)
            .labelsHidden()

            if model.availableCurrencies.count > 1 {
                let binding = Binding<String>(
                    get: { model.effectiveCurrency ?? "" },
                    set: { model.selectedCurrency = $0 }
                )
                Picker("币种", selection: binding) {
                    ForEach(model.availableCurrencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)
            } else if let currency {
                Text("币种 \(currency)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(model.currentRange.label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("账户", selection: $model.usageAccountFilter) {
                Text("全部账户").tag(String?.none)
                ForEach(model.filterAccounts, id: \.id) { account in
                    Text(account.name).tag(Optional(account.id))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 145)

            Picker("模型", selection: $model.usageModelFilter) {
                Text("全部模型").tag(String?.none)
                ForEach(model.filterModels, id: \.self) { model in
                    Text(model).tag(Optional(model))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)

            if model.hasUsageFilters {
                Button {
                    model.resetUsageFilters()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .help("清除账户 / 模型筛选")
            }

            Spacer()

            Button {
                exportCSV()
            } label: {
                Label("导出 CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(records.isEmpty)
        }
        .overlay(alignment: .bottomLeading) {
            if model.selectedPreset == .ninety {
                Text("OpenRouter 仅提供最近约 30 个 UTC 日，超出窗口的日期不会显示，也不会补 0。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .offset(y: 16)
            }
        }
        .padding(.bottom, model.selectedPreset == .ninety ? 14 : 0)
    }

    private var summaryCards: some View {
        let costs = currency.map { code in
            model.costs(records.filter { $0.currency == code })
        } ?? [:]
        let tokenCounts = records.compactMap { record -> Int? in
            guard record.promptTokens != nil || record.completionTokens != nil else { return nil }
            return (record.promptTokens ?? 0) + (record.completionTokens ?? 0)
        }
        let requestCounts = records.compactMap(\.requests)
        let costLines = costs.isEmpty ? [] : UIFormat.costLines(costs)
        let tokenLines: [(String, String?)] = tokenCounts.isEmpty
            ? [] : [(Money.formatInteger(tokenCounts.reduce(0, +)), "tokens")]
        let requestLines: [(String, String?)] = requestCounts.isEmpty
            ? [] : [(Money.formatInteger(requestCounts.reduce(0, +)), "次")]

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 210), spacing: 14)],
            alignment: .leading,
            spacing: 14
        ) {
            MetricCard(
                title: "筛选范围内费用",
                valueLines: costLines,
                footnote: "按当前币种筛选；分币种展示，不合并。",
                symbol: "dollarsign.circle",
                isDemo: model.isDemo
            )
            MetricCard(
                title: "tokens",
                valueLines: tokenLines,
                footnote: "仅统计提供实际字段的记录；缺失不补 0。",
                symbol: "number",
                isDemo: model.isDemo
            )
            MetricCard(
                title: "请求数",
                valueLines: requestLines,
                footnote: "厂商提供时展示，否则标记未提供。",
                symbol: "arrow.left.arrow.right",
                isDemo: model.isDemo
            )
            MetricCard(
                title: "数据记录",
                valueLines: [(String(records.count), "条")],
                footnote: "按账户 / 日期 / 模型 / 供应商去重后存储。",
                symbol: "list.bullet.rectangle",
                isDemo: model.isDemo
            )
        }
    }

    private var modelBreakdown: some View {
        SectionCard(
            title: "模型拆分",
            subtitle: currency ?? "OpenRouter activity",
            isDemo: model.isDemo
        ) {
            let totalsByCurrency = model.costs(records)
            VStack(spacing: 0) {
                gridRow(
                    ["模型", "账户", "Prompt", "Completion", "费用", "占比"],
                    header: true
                )
                ForEach(modelUsages) { usage in
                    Divider()
                    let total = usage.currency.flatMap { totalsByCurrency[$0] } ?? 0
                    let share = usage.costAvailable && total > 0 ? usage.cost / total * 100 : nil
                    gridRow([
                        usage.model,
                        usage.accountName,
                        usage.promptAvailable ? Money.formatInteger(usage.promptTokens) : "未提供",
                        usage.completionAvailable ? Money.formatInteger(usage.completionTokens) : "未提供",
                        usage.costAvailable
                            ? Money.formatCost(usage.cost, currency: usage.currency ?? currency ?? "USD")
                            : "未提供",
                        share.map { Money.percent($0) } ?? "—"
                    ], header: false)
                    if usage.byokAvailable && usage.byokCost > 0 {
                        HStack {
                            Text("BYOK 费用（与 credits 消耗分开）")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Money.formatCost(usage.byokCost, currency: usage.currency ?? "USD"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 2)
                        .padding(.top, 3)
                    }
                    Text("来源：\(usage.source) · 最近更新 \(UIFormat.compactDate(usage.lastUpdated))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func gridRow(_ values: [String], header: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(header ? .caption.weight(.semibold) : .caption)
                    .foregroundStyle(header ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(
                        maxWidth: index == 0 ? .infinity : (index == 1 ? 100 : nil),
                        alignment: index >= 4 ? .trailing : .leading
                    )
                    .frame(minWidth: index == 0 ? 150 : nil, alignment: index >= 4 ? .trailing : .leading)
            }
        }
        .padding(.vertical, header ? 4 : 6)
    }

    private var detailTable: some View {
        SectionCard(
            title: "用量明细",
            subtitle: "\(records.count) 条 · \(model.currentRange.label)",
            isDemo: model.isDemo
        ) {
            if records.isEmpty {
                emptyChart("所选范围内没有明细数据。")
            } else {
                let totals = model.costs(records)
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        detailCell("日期", weight: .semibold, width: 88)
                        detailCell("账户", weight: .semibold, width: 108)
                        detailCell("模型", weight: .semibold)
                        detailCell("tokens", weight: .semibold, width: 84, alignment: .trailing)
                        detailCell("费用", weight: .semibold, width: 84, alignment: .trailing)
                        detailCell("占比", weight: .semibold, width: 54, alignment: .trailing)
                        detailCell("来源", weight: .semibold, width: 150)
                        detailCell("最后更新", weight: .semibold, width: 116, alignment: .trailing)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                    ForEach(Array(records.sorted(by: { $0.day > $1.day }).prefix(200))) { record in
                        Divider()
                        let total = record.currency.flatMap { totals[$0] } ?? 0
                        let share: String = {
                            guard let cost = record.cost, total > 0 else { return "—" }
                            return Money.percent(cost / total * 100)
                        }()
                        HStack(spacing: 8) {
                            detailCell(record.day, width: 88)
                            detailCell(record.accountName, width: 108)
                            detailCell(record.model)
                            detailCell(
                                record.totalTokens.map(Money.formatInteger) ?? "未提供",
                                width: 84, alignment: .trailing
                            )
                            detailCell(
                                record.cost.map { Money.formatCost($0, currency: record.currency ?? "") } ?? "未提供",
                                width: 84, alignment: .trailing
                            )
                            detailCell(share, width: 54, alignment: .trailing)
                            detailCell(record.source, width: 150)
                            detailCell(
                                DateFormatters.mediumDateTime.string(from: record.updatedAt),
                                width: 116, alignment: .trailing
                            )
                        }
                        .padding(.vertical, 4)
                    }
                }
                if records.count > 200 {
                    Text("仅显示前 200 条；导出 CSV 包含当前筛选的全部记录。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("来源与时间范围会写入导出文件；缺失字段显示“未提供”。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func detailCell(
        _ text: String,
        weight: Font.Weight = .regular,
        width: CGFloat? = nil,
        alignment: Alignment = .leading
    ) -> some View {
        Text(text)
            .font(.caption.weight(weight))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .help(text)
    }

    private func emptyChart(_ message: String) -> some View {
        HStack {
            Image(systemName: "chart.bar.xaxis").foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
    }

    private func axisDayValues(_ days: [String]) -> [String] {
        let unique = Array(Set(days)).sorted()
        guard unique.count > 7 else { return unique }
        let step = Int(ceil(Double(unique.count) / 7.0))
        return unique.enumerated()
            .filter { $0.offset % step == 0 || $0.offset == unique.count - 1 }
            .map(\.element)
    }

    private func shortDay(_ day: String) -> String {
        day.count >= 10 ? String(day.suffix(5)) : day
    }

    private func exportCSV() {
        guard let export = model.csvExportData() else { return }
        AppPanels.saveCSV(filename: export.filename, data: export.data, isDemo: model.isDemo) { result in
            Task { @MainActor in
                switch result {
                case .success:
                    model.showBanner("CSV 已导出：\(export.filename)", style: .success)
                case .failure(let error):
                    model.showBanner("CSV 导出失败：\(error.localizedDescription)", style: .error)
                }
            }
        }
    }
}
