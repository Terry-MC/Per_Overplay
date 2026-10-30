import SwiftUI
import OverplayCore

struct MenuBarPanelView: View {
    @ObservedObject var model: AppModel
    var openMain: (DashboardTab) -> Void
    var quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if model.isDemo {
                Text(DemoMode.shortBadge)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.1))
            }
            Divider()

            ScrollView {
                if model.accounts.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(L10n.t("menuBar.1f78ac5a72"))
                            .font(.headline)
                        Text(L10n.t("menuBar.0036c5c9d5"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button(L10n.t("menuBar.1519cc3e90")) { openMain(.overview) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.accounts) { account in
                            accountRow(account)
                            if account.id != model.accounts.last?.id {
                                Divider().padding(.leading, 46)
                            }
                        }
                    }
                }
                if !model.alerts.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.t("menuBar.5078424f7e")).font(.caption.weight(.semibold))
                            if model.isDemo { DemoTag() }
                            Spacer()
                            Text(L10n.f("menuBar.dd296b0bc0", model.unacknowledgedAlerts.count))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.unacknowledgedAlerts.prefix(2)) { alert in
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(L10n.f("common.accountAlertLabel", alert.accountName, alert.kind.title))
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .frame(maxHeight: 380)

            Divider()
            HStack(spacing: 8) {
                Button {
                    openMain(.overview)
                } label: {
                    Label(L10n.t("menuBar.eb943fa97b"), systemImage: "macwindow")
                }
                Button {
                    model.refreshAll()
                } label: {
                    Label(L10n.t("providerDetail.38108eaa1d"), systemImage: "arrow.clockwise")
                }
                .disabled(model.isDemo || model.accounts.isEmpty)
                Button {
                    openMain(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                Spacer()
                Button(role: .destructive) {
                    quit()
                } label: {
                    Image(systemName: "power")
                }
                .help(L10n.t("statusBar.d94cefe4dc"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(12)
        }
        .frame(width: 366)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, model.effectiveLocale)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Overplay").font(.headline)
                    if model.isDemo { DemoTag() }
                }
                Text(model.isDemo ? L10n.t("settings.fbd46976e0") : L10n.f("menuBar.94d9bdb6d9", model.accounts.count, model.settings.refreshIntervalMinutes))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.hasCriticalAlert {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help(L10n.t("menuBar.a03082271f"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: 10) {
            ProviderMark(provider: account.provider, iconName: account.iconName)
                .scaleEffect(0.84)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(account.displayName).font(.subheadline.weight(.medium))
                    if model.isDemo || account.isDemo { DemoTag() }
                }
                Text(primaryMetric(account))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            HealthBadge(health: model.health(for: account))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func primaryMetric(_ account: Account) -> String {
        if account.capabilities.credits {
            guard let quota = model.latestQuota(for: account) else { return L10n.t("health.neverSynced") }
            let label = account.provider == .openrouter ? "credits" : L10n.t("menuBar.3fa9a9d38e")
            return L10n.f("menuBar.d7981395e7", label, Money.formatBalance(quota.remaining, currency: quota.currency), Money.formatBalance(quota.totalUsage, currency: quota.currency))
        }
        let balances = model.latestBalances(for: account)
        if !balances.isEmpty {
            return balances.map {
                Money.formatBalance($0.total, currency: $0.currency)
            }.joined(separator: " · ")
        }
        if account.capabilities.usage {
            return L10n.t("menuBar.2e969b0a68")
        }
        return L10n.t("health.neverSynced")
    }
}
