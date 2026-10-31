import SwiftUI
import OverplayCore

/// Keeps the last summary while the panel is hidden. The content view stays
/// mounted so the scroll position survives hide/show; skipping the builder
/// keeps the hidden panel from recomputing on every model tick.
@MainActor
final class FloatingSummaryCache {
    private var cached: FloatingSummary?
    private var cachedRevision: UUID?
    private(set) var buildCount = 0

    func summary(for model: AppModel, isVisible: Bool) -> FloatingSummary {
        let revision = model.localizationRevision
        if !isVisible, let cached, cachedRevision == revision { return cached }
        buildCount += 1
        let summary = FloatingSummaryBuilder.make(
            accounts: model.accounts,
            usageRecords: model.usageRecords,
            balances: model.balances,
            quotas: model.quotas,
            alerts: model.alerts,
            now: model.now
        )
        cached = summary
        cachedRevision = revision
        return summary
    }
}

struct FloatingPanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var visibility: FloatingPanelVisibility
    let density: FloatingDensity
    let summaryCache: FloatingSummaryCache
    let onClose: () -> Void
    let onToggleDensity: () -> Void
    let onCollapse: () -> Void
    let onOpenMain: () -> Void
    let onOpenMessages: () -> Void

    private var summary: FloatingSummary {
        summaryCache.summary(for: model, isVisible: visibility.isVisible)
    }

    var body: some View {
        panelContent
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preferredColorScheme(nil)
            .environment(\.locale, model.effectiveLocale)
    }

    private var panelContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    globalSummary
                    accountsSection
                    footer
                }
                .padding(14)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.headline)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("Overplay").font(.headline.weight(.bold))
                    if model.isDemo { DemoTag() }
                }
                Text(headerSubtitle)
                    .font(.caption2)
                    .foregroundStyle(headerIsStale ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .help(headerSubtitle)
            }
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                panelButton(
                    symbol: "xmark",
                    help: L10n.t("statusBar.d94cefe4dc"),
                    action: onClose
                )
                panelButton(
                    symbol: density == .expanded ? "chevron.up" : "chevron.down",
                    help: density == .expanded ? L10n.t("floating.4c2abdc86a") : L10n.t("floating.e17ce1d5bf"),
                    action: onToggleDensity
                )
                panelButton(
                    symbol: "minus.circle",
                    help: L10n.t("floating.322c66c022"),
                    action: onCollapse
                )
                panelButton(
                    symbol: "arrow.up.right.square",
                    help: L10n.t("floating.3f73472136"),
                    action: onOpenMain
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var headerSubtitle: String {
        var parts: [String] = []
        if model.accounts.isEmpty {
            parts.append(L10n.t("floating.d125522fc6"))
        } else {
            parts.append(L10n.f("floating.aacf67bc4e", summary.activeAccountCount))
            if summary.disabledAccountCount > 0 {
                parts.append(L10n.f("floating.ee0e49457f", summary.disabledAccountCount))
            }
        }
        if let lastSync = summary.lastSyncAt {
            parts.append(L10n.f("floating.0147d5a3b6", DateFormatters.shortTime.string(from: lastSync)))
        } else {
            parts.append(L10n.t("health.neverSynced"))
        }
        return parts.joined(separator: " · ")
    }

    private var headerIsStale: Bool {
        guard let lastSync = summary.lastSyncAt else { return false }
        return model.now.timeIntervalSince(lastSync) > model.settings.refreshInterval * 2
    }

    private func panelButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var globalSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Text(L10n.t("floating.b11b32b438"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        if !summary.todayStatus.isActual, let icon = summary.todayStatus.iconName {
                            Image(systemName: icon)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(summary.todayStatus.tint)
                                .help(summary.todayStatus.reason ?? "")
                        }
                    }
                    if summary.todayStatus.isActual, !summary.todayCosts.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            ForEach(summary.todayCosts.keys.sorted(), id: \.self) { currency in
                                Text(Money.formatCost(summary.todayCosts[currency] ?? 0, currency: currency))
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                            }
                        }
                    } else {
                        HStack(spacing: 5) {
                            Text(summary.todayStatus.isMissing ? L10n.t("floating.92ed395e3f") : summary.todayStatus.emptyLabel)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Image(systemName: summary.todayStatus.iconName ?? "tray")
                                .font(.caption)
                                .foregroundStyle(summary.todayStatus.tint)
                        }
                        .help(summary.todayStatus.reason ?? summary.todayStatus.emptyLabel)
                    }
                }
                Spacer(minLength: 0)
                alertSummary
            }
            Divider().opacity(0.45)
            HStack(alignment: .top, spacing: 0) {
                snapshotColumn(
                    title: L10n.t("core.floatingSummary.f5f1ad2311"),
                    symbol: "creditcard",
                    status: summary.balancesStatus,
                    rows: balanceRows
                )
                Divider().frame(height: 52).padding(.horizontal, 10)
                snapshotColumn(
                    title: L10n.t("core.floatingSummary.f625451199"),
                    symbol: "gauge.with.dots.needle.50percent",
                    status: summary.creditsStatus,
                    rows: creditRows
                )
                Divider().frame(height: 52).padding(.horizontal, 10)
                tokenColumn
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private var alertSummary: some View {
        Group {
            if summary.unacknowledgedAlertCount > 0 {
                Button(action: onOpenMessages) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Label(
                            "\(summary.unacknowledgedAlertCount)",
                            systemImage: summary.criticalAlertCount > 0
                                ? "exclamationmark.triangle.fill"
                                : "bell.badge"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(summary.criticalAlertCount > 0 ? Color.red : Color.orange)
                        Text(summary.criticalAlertCount > 0 ? L10n.t("floating.d85ef4e514") : L10n.t("core.messages.0642fa2988"))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(L10n.t("dashboard.4d7ebd8d8f"))
                .accessibilityLabel(L10n.f("floating.75baa8f30e", summary.unacknowledgedAlertCount))
            } else {
                Label(L10n.t("floating.61e269413e"), systemImage: "checkmark.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func snapshotColumn(
        title: String,
        symbol: String,
        status: DataStatus,
        rows: [(String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                if !status.isActual, let icon = status.iconName {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(status.tint)
                }
            }
            if status.isActual, !rows.isEmpty {
                ForEach(Array(rows.prefix(2).enumerated()), id: \.offset) { _, row in
                    Text(row.1)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .help(row.0)
                }
            } else {
                Text(status.isActual ? L10n.t("dataStatus.6ffa7e6d35") : status.emptyLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(status.reason ?? "")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tokenColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: "number")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(L10n.t("floating.1bac85732d"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                if !summary.tokenStatus.isActual, let icon = summary.tokenStatus.iconName {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(summary.tokenStatus.tint)
                }
            }
            if summary.tokenStatus.isActual {
                Text("\(Money.formatCompactInteger(summary.tokenTotal)) tokens")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(L10n.f("floating.bd9ae6258a", summary.tokenAccounts, summary.totalAccounts))
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                Text(summary.requestsAvailable
                     ? L10n.f("floating.9c7b978970", Money.formatCompactInteger(summary.requestCount))
                     : L10n.t("floating.317d982d2d"))
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            } else {
                Text(summary.tokenStatus.emptyLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .help(summary.tokenStatus.reason ?? "")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var balanceRows: [(String, String)] {
        summary.balances.keys.sorted().map { currency in
            (currency, Money.formatBalance(summary.balances[currency] ?? 0, currency: currency))
        }
    }

    private var creditRows: [(String, String)] {
        summary.creditsRemaining.keys.sorted().map { currency in
            (currency, Money.formatBalance(summary.creditsRemaining[currency] ?? 0, currency: currency))
        }
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(L10n.t("core.csv.c3d92b20c8")).font(.subheadline.weight(.semibold))
                Text("\(model.accounts.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.refreshAll()
                } label: {
                    Label(L10n.t("providerDetail.38108eaa1d"), systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .disabled(model.isDemo || model.accounts.isEmpty)
                .help(model.isDemo ? L10n.t("floating.280880b4de") : L10n.t("floating.d67c7bf730"))
            }
            if model.accounts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("floating.a65f750ed3")).font(.callout.weight(.semibold))
                    Text(L10n.t("floating.7b0ed52c26"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(L10n.t("floating.549cf8c0c8"), action: onOpenMain)
                        .buttonStyle(.link)
                        .font(.caption)
                }
                .padding(.vertical, 12)
            } else {
                if summary.activeAccountCount == 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                        Text(L10n.t("floating.bbde6bf66a"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.t("floating.549cf8c0c8"), action: onOpenMain)
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.orange.opacity(0.08))
                    )
                }
                LazyVStack(spacing: 6) {
                    ForEach(summary.rows) { row in
                        accountRow(row)
                    }
                }
            }
        }
    }

    private func accountRow(_ row: FloatingAccountRow) -> some View {
        VStack(alignment: .leading, spacing: density == .expanded ? 5 : 3) {
            HStack(spacing: 7) {
                ProviderMark(provider: row.provider, iconName: row.iconName)
                    .scaleEffect(0.72)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(row.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    if let officialName = row.officialName {
                        Text(officialName)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 5) {
                        primaryStatusLabel(row.primaryStatus)
                        if row.unacknowledgedAlerts > 0 {
                            Label("\(row.unacknowledgedAlerts)", systemImage: row.criticalAlerts > 0 ? "exclamationmark.triangle.fill" : "bell")
                                .foregroundStyle(row.criticalAlerts > 0 ? Color.red : Color.orange)
                        }
                        if !row.enabled {
                            Text(L10n.t("health.disabled")).foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 9))
                }
                Spacer(minLength: 2)
                Button {
                    if let account = model.accounts.first(where: { $0.id == row.id }) {
                        model.refresh(account: account)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(model.isDemo || !row.enabled)
                .help(model.isDemo ? L10n.t("floating.280880b4de") : L10n.f("floating.c8fdfe3f3c", row.name))
                .accessibilityLabel(L10n.f("floating.c8fdfe3f3c", row.name))
            }

            if row.primaryStatus.isActual, !row.primaryLines.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    ForEach(Array(row.primaryLines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            if row.primaryLines.count > 1 {
                                Text(line.currency)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            Text(Money.formatBalance(line.value, currency: line.currency))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
            } else {
                DataValueLabel(
                    text: row.primaryStatus.emptyLabel,
                    status: row.primaryStatus,
                    font: .caption.weight(.medium)
                )
                .help(row.primaryStatus.reason ?? "")
            }

            if density == .expanded {
                if row.secondaryStatus != nil, !row.secondaryLines.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(row.secondaryLines.enumerated()), id: \.offset) { _, line in
                            Text("\(line.label) \(Money.formatBalance(line.value, currency: line.currency))")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        if let ratio = row.budgetRatio {
                            ProgressView(value: min(max(NSDecimalNumber(decimal: ratio).doubleValue / 100, 0), 1))
                                .frame(width: 48)
                                .tint(ratio >= 100 ? .red : ratio >= 80 ? .orange : .green)
                        }
                    }
                }
                if let error = row.errorSummary {
                    Text(L10n.t(error))
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                if let last = row.lastSuccessAt {
                    Text(L10n.f("floating.0147d5a3b6", DateFormatters.shortTime.string(from: last)))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, density == .expanded ? 7 : 5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func primaryStatusLabel(_ status: DataStatus) -> some View {
        HStack(spacing: 2) {
            Image(systemName: status.isActual ? "checkmark.circle.fill" : (status.iconName ?? "tray"))
                .foregroundStyle(status.isActual ? Color.green : status.tint)
            Text(status.isActual ? L10n.t("health.normal") : status.emptyLabel)
                .foregroundStyle(status.isActual ? Color.secondary : status.tint)
        }
        .help(status.reason ?? "")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(L10n.t("floating.549cf8c0c8"), action: onOpenMain)
                .buttonStyle(.link)
                .font(.caption)
            Spacer()
            Text(L10n.f("floating.94bfadcf4a", model.settings.refreshIntervalMinutes))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

}
