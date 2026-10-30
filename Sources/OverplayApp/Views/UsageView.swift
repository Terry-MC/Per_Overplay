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
            summaryCards
            if records.isEmpty {
                emptyRecordsState
                missingDataNotes
            } else {
                chartsAndTables
                missingDataNotes
            }

            Text(L10n.t("usage.af56043f83"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyRecordsState: some View {
        SectionCard(isDemo: model.isDemo) {
            EmptyStateView(
                symbol: "chart.bar.doc.horizontal",
                title: L10n.t("usage.91913c9ff5"),
                message: model.hasUsageFilters
                    ? L10n.t("usage.924ec1757a")
                    : (model.isDemo
                        ? L10n.t("usage.bbf85385bc")
                        : L10n.t("usage.faf5511fd2"))
            ) {
                if model.hasUsageFilters {
                    Button(L10n.t("messages.4bbc4e5fd9")) { model.resetUsageFilters() }
                }
            }
        }
    }

    private var chartsAndTables: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionCard(
                title: L10n.t("usage.dc3207941a"),
                subtitle: currency.map { L10n.f("usage.132f486445", $0) } ?? L10n.t("usage.e8dbc48a7f"),
                isDemo: model.isDemo
            ) {
                if costSeries.isEmpty {
                    emptyChart(L10n.t("usage.b8ba932d66"))
                } else {
                    let allDays = CalendarDay.days(from: model.currentRange)
                    Chart(costSeries) { point in
                        BarMark(
                            x: .value(L10n.t("usage.b6fed9af83"), point.day),
                            y: .value(L10n.t("metric.cost"), point.cost)
                        )
                        .foregroundStyle(by: .value(L10n.t("core.csv.0c131e3964"), point.provider))
                    }
                    .chartXScale(domain: allDays)
                    .chartXAxis {
                        AxisMarks(values: axisDayValues(allDays)) { value in
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
                    Text(
                        model.isDemo
                            ? L10n.t("usage.81d55bd84f")
                            : L10n.t("usage.fce91b5a6e")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if !costSeries.contains(where: { $0.day == model.currentRange.endDay }) {
                        Text(L10n.f("usage.1456c7de21", model.currentRange.endDay))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            SectionCard(
                title: L10n.t("usage.0abd48a0b6"),
                subtitle: L10n.t("usage.d7ef99f7c6"),
                isDemo: model.isDemo
            ) {
                if tokenSeries.isEmpty {
                    emptyChart(L10n.t("usage.5f1da33cec"))
                } else {
                    let allDays = CalendarDay.days(from: model.currentRange)
                    Chart {
                        ForEach(tokenSeries) { point in
                            if point.promptAvailable {
                                LineMark(
                                    x: .value(L10n.t("usage.b6fed9af83"), point.day),
                                    y: .value("tokens", point.prompt)
                                )
                                .foregroundStyle(by: .value(L10n.t("messages.e4e46c7235"), "Prompt"))
                                .interpolationMethod(.monotone)
                            }
                            if point.completionAvailable {
                                LineMark(
                                    x: .value(L10n.t("usage.b6fed9af83"), point.day),
                                    y: .value("tokens", point.completion)
                                )
                                .foregroundStyle(by: .value(L10n.t("messages.e4e46c7235"), "Completion"))
                                .interpolationMethod(.monotone)
                            }
                        }
                    }
                    .chartXScale(domain: allDays)
                    .chartXAxis {
                        AxisMarks(values: axisDayValues(allDays)) { value in
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
                    Text(
                        model.isDemo
                            ? L10n.t("usage.3242a28c04")
                            : L10n.t("usage.214281b2c6")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if !tokenSeries.contains(where: { $0.day == model.currentRange.endDay }) {
                        Text(L10n.f("usage.1456c7de21", model.currentRange.endDay))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if modelUsages.isEmpty {
                SectionCard(title: L10n.t("usage.0d114aeb20"), subtitle: L10n.t("dataStatus.6ffa7e6d35"), isDemo: model.isDemo) {
                    Text(L10n.t("usage.e833bdae74"))
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
            SectionCard(title: L10n.t("usage.9d224cc286"), isDemo: model.isDemo) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(gaps) { account in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName)
                                    .font(.caption.weight(.semibold))
                                if !account.capabilities.usage {
                                    Text(L10n.t("usage.cbc43acf36"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(model.isDemo ? L10n.t("usage.78e27f2359") : L10n.t("usage.445431ea37"))
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
        VStack(alignment: .leading, spacing: 10) {
            AnalysisRangeControls(model: model, compact: true)
            HStack(spacing: 14) {
                if model.availableCurrencies.count > 1 {
                    let binding = Binding<String>(
                        get: { model.effectiveCurrency ?? "" },
                        set: { model.selectedCurrency = $0 }
                    )
                    Picker(L10n.t("core.csv.a81ab5e100"), selection: binding) {
                        ForEach(model.availableCurrencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 110)
                } else if let currency {
                    Text(L10n.f("usage.51c47086e2", currency))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker(L10n.t("core.csv.c3d92b20c8"), selection: $model.usageAccountFilter) {
                    Text(L10n.t("messages.c5e5d57837")).tag(String?.none)
                    ForEach(model.filterAccounts, id: \.id) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 145)

                Picker(L10n.t("core.csv.98fd0cbd9c"), selection: $model.usageModelFilter) {
                    Text(L10n.t("usage.688facc5f5")).tag(String?.none)
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
                    .help(L10n.t("usage.cced1eef57"))
                }

                Spacer()

                Button {
                    exportCSV()
                } label: {
                    Label(L10n.t("usage.7e9cc8635e"), systemImage: "square.and.arrow.up")
                }
                .disabled(records.isEmpty)
            }

            if rangeExceedsThirtyDays {
                Text(model.isDemo
                    ? L10n.t("usage.852dbbb9b3")
                    : L10n.t("usage.ef8e4c883f"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rangeExceedsThirtyDays: Bool {
        CalendarDay.days(from: model.currentRange).count > 30
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
            ? [] : [(Money.formatInteger(requestCounts.reduce(0, +)), L10n.t("usage.5e5b8169ee"))]
        let baseStatus = model.usageDataStatus()
        let costStatus: DataStatus = (costLines.isEmpty
            ? (records.isEmpty ? baseStatus : .missing(L10n.t("usage.4b3624093d")))
            : baseStatus).prefixed(L10n.t("usage.5ae7f19c41"))
        let tokenStatus: DataStatus = (tokenLines.isEmpty
            ? (records.isEmpty ? baseStatus : .missing(L10n.t("usage.16a9dbdd83")))
            : baseStatus).prefixed("tokens")
        let requestStatus: DataStatus = (requestLines.isEmpty
            ? (records.isEmpty ? baseStatus : .missing(L10n.t("usage.3f20509e5f")))
            : baseStatus).prefixed(L10n.t("core.analysisRange.b28376ff80"))

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 210), spacing: 14)],
            alignment: .leading,
            spacing: 14
        ) {
            MetricCard(
                title: L10n.t("usage.5ae7f19c41"),
                valueLines: costLines,
                footnote: costStatus.isActual ? L10n.t("usage.5e8b16e6c8") : (costStatus.reason ?? L10n.t("dataStatus.6ffa7e6d35")),
                symbol: "dollarsign.circle",
                isDemo: model.isDemo,
                status: costStatus
            )
            MetricCard(
                title: "tokens",
                valueLines: tokenLines,
                footnote: tokenStatus.isActual ? L10n.t("usage.9b067de74b") : (tokenStatus.reason ?? L10n.t("dataStatus.6ffa7e6d35")),
                symbol: "number",
                isDemo: model.isDemo,
                status: tokenStatus
            )
            MetricCard(
                title: L10n.t("core.analysisRange.b28376ff80"),
                valueLines: requestLines,
                footnote: requestStatus.isActual ? L10n.t("usage.ea6b3baed6") : (requestStatus.reason ?? L10n.t("dataStatus.6ffa7e6d35")),
                symbol: "arrow.left.arrow.right",
                isDemo: model.isDemo,
                status: requestStatus
            )
            MetricCard(
                title: L10n.t("usage.85634fa9ef"),
                valueLines: [(String(records.count), L10n.t("usage.bce2ef6151"))],
                footnote: L10n.t("usage.3efa5d2552"),
                symbol: "list.bullet.rectangle",
                isDemo: model.isDemo,
                status: baseStatus.prefixed(L10n.t("usage.85634fa9ef"))
            )
        }
    }

    private var modelBreakdown: some View {
        SectionCard(
            title: L10n.t("usage.0d114aeb20"),
            subtitle: currency ?? (model.isDemo ? L10n.t("usage.c6dbb0bba9") : "OpenRouter activity"),
            isDemo: model.isDemo
        ) {
            let totalsByCurrency = model.costs(records)
            VStack(spacing: 0) {
                modelGridRow(
                    [L10n.t("core.csv.98fd0cbd9c"), L10n.t("core.csv.c3d92b20c8"), "Prompt", "Completion", "Reasoning", "Cached", L10n.t("core.analysisRange.b28376ff80"), L10n.t("usage.590d36deba"), L10n.t("usage.380a2fed3f")],
                    header: true
                )
                ForEach(modelUsages) { usage in
                    Divider()
                    let total = usage.currency.flatMap { totalsByCurrency[$0] } ?? 0
                    let share = usage.costAvailable && total > 0 ? usage.cost / total * 100 : nil
                    modelGridRow([
                        usage.model,
                        usage.accountName,
                        usage.promptAvailable ? Money.formatInteger(usage.promptTokens) : L10n.t("core.csv.071fb244ea"),
                        usage.completionAvailable ? Money.formatInteger(usage.completionTokens) : L10n.t("core.csv.071fb244ea"),
                        usage.reasoningAvailable ? Money.formatInteger(usage.reasoningTokens) : L10n.t("core.csv.071fb244ea"),
                        usage.cachedAvailable ? Money.formatInteger(usage.cachedTokens) : L10n.t("core.csv.071fb244ea"),
                        usage.requestsAvailable ? Money.formatInteger(usage.requests) : L10n.t("core.csv.071fb244ea"),
                        usage.costAvailable
                            ? Money.formatCost(usage.cost, currency: usage.currency ?? currency ?? "USD")
                            : L10n.t("core.csv.071fb244ea"),
                        share.map { Money.percent($0) } ?? "—"
                    ], header: false)
                    if usage.byokAvailable && usage.byokCost > 0 {
                        HStack {
                            Text(L10n.t("usage.c764cbec53"))
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
                    Text(L10n.f("usage.4a763ed3ae", usage.source, UIFormat.compactDate(usage.lastUpdated)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
        }
    }

    private let modelWidths: [CGFloat?] = [nil, 100, 70, 82, 78, 64, 56, 88, 52]

    private func modelGridRow(_ values: [String], header: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(header ? .caption2.weight(.semibold) : .caption2)
                    .foregroundStyle(header ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: modelWidths[index], alignment: index >= 2 ? .trailing : .leading)
                    .frame(maxWidth: index == 0 ? .infinity : nil, alignment: .leading)
                    .help(value)
            }
        }
        .padding(.vertical, header ? 3 : 5)
    }

    private var detailTable: some View {
        SectionCard(
            title: L10n.t("usage.6bc335e3bc"),
            subtitle: L10n.f("usage.241b6402ee", records.count, model.currentRange.label),
            isDemo: model.isDemo
        ) {
            if records.isEmpty {
                emptyChart(L10n.t("usage.17f4ec224b"))
            } else {
                let totals = model.costs(records)
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        detailGridRow(
                            [L10n.t("usage.b6fed9af83"), L10n.t("core.csv.c3d92b20c8"), L10n.t("core.csv.98fd0cbd9c"), "Prompt", "Completion", "Reasoning", "Cached", L10n.t("core.analysisRange.b28376ff80"), L10n.t("usage.590d36deba"), "BYOK", L10n.t("usage.380a2fed3f"), L10n.t("core.csv.c63f79e636"), L10n.t("usage.138c939e33")],
                            header: true
                        )
                        ForEach(Array(records.sorted(by: { $0.day > $1.day }).prefix(200))) { record in
                            Divider()
                            let total = record.currency.flatMap { totals[$0] } ?? 0
                            let share: String = {
                                guard let cost = record.cost, total > 0 else { return "—" }
                                return Money.percent(cost / total * 100)
                            }()
                            detailGridRow([
                                record.day,
                                record.accountName,
                                record.model,
                                record.promptTokens.map(Money.formatInteger) ?? L10n.t("core.csv.071fb244ea"),
                                record.completionTokens.map(Money.formatInteger) ?? L10n.t("core.csv.071fb244ea"),
                                record.reasoningTokens.map(Money.formatInteger) ?? L10n.t("core.csv.071fb244ea"),
                                record.cachedTokens.map(Money.formatInteger) ?? L10n.t("core.csv.071fb244ea"),
                                record.requests.map(Money.formatInteger) ?? L10n.t("core.csv.071fb244ea"),
                                record.cost.map { Money.formatCost($0, currency: record.currency ?? "") } ?? L10n.t("core.csv.071fb244ea"),
                                record.byokCost.map { Money.formatCost($0, currency: record.currency ?? "USD") } ?? L10n.t("core.csv.071fb244ea"),
                                share,
                                record.source,
                                DateFormatters.mediumDateTime.string(from: record.updatedAt)
                            ], header: false)
                        }
                    }
                    .frame(width: 1120, alignment: .leading)
                }
                if records.count > 200 {
                    Text(L10n.t("usage.9542467a2d"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(L10n.t("usage.eb28e26b74"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private let detailWidths: [CGFloat?] = [78, 96, nil, 58, 66, 66, 56, 50, 80, 70, 45, 112, 96]

    private func detailGridRow(_ values: [String], header: Bool) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(header ? .caption2.weight(.semibold) : .caption2)
                    .foregroundStyle(header ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(
                        width: detailWidths[index],
                        alignment: numericColumn(index) ? .trailing : .leading
                    )
                    .frame(maxWidth: index == 2 ? .infinity : nil, alignment: .leading)
                    .help(value)
            }
        }
        .padding(.vertical, header ? 3 : 4)
    }

    private func numericColumn(_ index: Int) -> Bool {
        (3...10).contains(index) || index == 12
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
                    model.showBanner(L10n.f("usage.e69a391adc", export.filename), style: .success)
                case .failure(let error):
                    model.showBanner(L10n.f("usage.af55c3ac40", L10n.t(error.localizedDescription)), style: .error)
                }
            }
        }
    }
}
