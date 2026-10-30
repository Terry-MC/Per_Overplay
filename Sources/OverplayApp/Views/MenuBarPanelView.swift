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
                        Text("尚未添加账户")
                            .font(.headline)
                        Text("添加 DeepSeek 或 OpenRouter 账户，或使用演示模式体验。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("打开主界面") { openMain(.overview) }
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
                            Text("告警").font(.caption.weight(.semibold))
                            if model.isDemo { DemoTag() }
                            Spacer()
                            Text("\(model.unacknowledgedAlerts.count) 条未确认")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.unacknowledgedAlerts.prefix(2)) { alert in
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("\(alert.accountName)：\(alert.kind.title)")
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
                    Label("主界面", systemImage: "macwindow")
                }
                Button {
                    model.refreshAll()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
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
                .help("退出 Overplay")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(12)
        }
        .frame(width: 366)
        .background(Color(nsColor: .windowBackgroundColor))
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
                Text(model.isDemo ? "演示模式" : "\(model.accounts.count) 个账户 · \(model.settings.refreshIntervalMinutes) 分钟刷新")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.hasCriticalAlert {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help("存在未确认告警")
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
            guard let quota = model.latestQuota(for: account) else { return "尚未同步" }
            let label = account.provider == .openrouter ? "credits" : "额度"
            return "\(label) \(Money.formatBalance(quota.remaining, currency: quota.currency)) · 已用 \(Money.formatBalance(quota.totalUsage, currency: quota.currency))"
        }
        let balances = model.latestBalances(for: account)
        if !balances.isEmpty {
            return balances.map {
                Money.formatBalance($0.total, currency: $0.currency)
            }.joined(separator: " · ")
        }
        if account.capabilities.usage {
            return "已连接 · 用量可用"
        }
        return "尚未同步"
    }
}
