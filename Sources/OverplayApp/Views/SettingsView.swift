import SwiftUI
import OverplayCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var onAddAccount: () -> Void
    var onEditAccount: (Account) -> Void
    var onDeleteAccount: (Account) -> Void

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let warning = model.initializationWarning {
                InlineErrorView(message: warning)
            }
            generalSection
            accountsSection
            demoSection
            privacySection
            aboutSection
            exitSection
        }
    }

    private var generalSection: some View {
        SectionCard(title: "刷新与通知", isDemo: model.isDemo) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自动刷新间隔").font(.subheadline.weight(.semibold))
                        Text("默认 15 分钟，可在 5–60 分钟之间配置。收起 / 隐藏窗口不暂停；退出应用才停止。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Stepper(
                        value: Binding(
                            get: { model.settings.refreshIntervalMinutes },
                            set: { model.setRefreshInterval($0) }
                        ),
                        in: 5...60,
                        step: 5
                    ) {
                        Text("每 \(model.settings.refreshIntervalMinutes) 分钟")
                            .monospacedDigit()
                            .frame(width: 96, alignment: .trailing)
                    }
                    .disabled(model.isDemo)
                }
                if model.isDemo {
                    Text("演示模式仅修改当前内存演示设置，不影响真实配置。")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Divider()
                Toggle(isOn: Binding(
                    get: { model.settings.notificationsEnabled },
                    set: { model.setNotificationsEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("启用本地通知").font(.subheadline.weight(.semibold))
                        Text("阈值告警、连续同步失败、凭据失效与数据过期提醒。通知内容不包含 API Key。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(model.isDemo)
                HStack(spacing: 10) {
                    if model.isDemo {
                        Text("演示模式不请求系统通知权限，也不发送系统通知；告警仅显示在应用内。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("通知权限：\(model.notificationStatusText)")
                            .font(.caption)
                            .foregroundStyle(model.notificationStatus == .denied ? .orange : .secondary)
                        if model.notificationStatus == .denied {
                            Button("打开系统通知设置") {
                                model.openNotificationSettings()
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                            Text("应用内告警与托盘状态仍可用。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("测试通知") {
                        model.sendTestNotification()
                    }
                    .disabled(model.isDemo)
                }
            }
        }
    }

    private var accountsSection: some View {
        SectionCard(
            title: "账户",
            subtitle: "\(model.accounts.count) 个",
            isDemo: model.isDemo
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if model.accounts.isEmpty {
                    Text("尚未添加账户。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.accounts) { account in
                        HStack(spacing: 10) {
                            ProviderMark(provider: account.provider)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(account.displayName).font(.subheadline.weight(.semibold))
                                    if model.isDemo || account.isDemo { DemoTag() }
                                }
                                Text(account.provider.displayName + " · " + model.currencyLabel(for: account) + " · " + model.capabilitySummary(for: account))
                                    .font(.caption)
                                    .foregroundStyle(account.credentialInvalid ? .red : .secondary)
                                Text(model.lastSyncText(for: account))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HealthBadge(health: model.health(for: account))
                            Toggle("", isOn: Binding(
                                get: { account.enabled },
                                set: { model.setAccountEnabled(account, enabled: $0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .disabled(model.isDemo)
                            .help(account.enabled ? "禁用后停止同步与告警" : "启用账户")
                            Button("编辑") { onEditAccount(account) }
                                .disabled(model.isDemo)
                            Button("删除") { onDeleteAccount(account) }
                                .disabled(model.isDemo)
                        }
                        if account.id != model.accounts.last?.id { Divider() }
                    }
                }
                HStack {
                    Button {
                        onAddAccount()
                    } label: {
                        Label("添加账户", systemImage: "plus")
                    }
                    .disabled(model.isDemo)
                    if model.isDemo {
                        Text("演示模式下不可添加真实账户。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                }
            }
        }
    }

    private var demoSection: some View {
        SectionCard(title: "演示模式") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "flask")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("演示模式使用本地模拟数据覆盖主要页面与告警路径，不发起任何外部网络请求，也不读写 Keychain 或真实数据库。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(DemoMode.shortBadge)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if model.isDemo {
                    Button("退出演示模式") { model.exitDemoMode() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("进入演示模式") { model.requestEnterDemoMode() }
                }
                Button("查看免责声明") { model.showDemoDisclaimer() }
            }
        }
    }

    private var privacySection: some View {
        SectionCard(title: "数据与隐私") {
            VStack(alignment: .leading, spacing: 10) {
                row("本地数据位置", model.dataFileDisplayPath, monospaced: true)
                row("凭证存储", "macOS Keychain（仅本机，不随 iCloud 同步）")
                row("网络访问", "仅 DeepSeek / OpenRouter 官方 HTTPS 域名；无遥测、无第三方统计")
                row("DeepSeek 限制", "仅余额；无历史 token / 费用接口，界面显示“厂商未提供”")
                row("OpenRouter 限制", "需要 Management Key；activity 约 30 个 UTC 日窗口")
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("清除全部本地数据").font(.subheadline.weight(.semibold))
                        Text("删除账户、Keychain 凭证、历史用量、快照、告警与设置；需要两次确认。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        model.confirmClearAllData()
                    } label: {
                        Text("清除全部数据")
                    }
                    .disabled(model.isDemo)
                }
                if model.isDemo {
                    Text("演示模式下不会触碰真实数据或 Keychain。请先退出演示模式再清除真实数据。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var aboutSection: some View {
        SectionCard(title: "关于") {
            VStack(alignment: .leading, spacing: 8) {
                row("版本", appVersion)
                Text("Overplay 仅读取官方余额 / credits / 用量接口，不代理 LLM 请求，不进行逐请求 token 统计。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Link("项目仓库", destination: URL(string: "https://github.com/Terry-MC/Per_Overplay")!)
                    Link(
                        "OpenRouter Management Key 文档",
                        destination: URL(string: "https://openrouter.ai/docs/api-reference/credits/get-credits")!
                    )
                    Link(
                        "DeepSeek 余额文档",
                        destination: URL(string: "https://api-docs.deepseek.com/zh-cn/api/get-user-balance/")!
                    )
                }
                .font(.caption)
            }
        }
    }

    private var exitSection: some View {
        SectionCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("退出程序").font(.subheadline.weight(.semibold))
                    Text("停止全部定时刷新、取消进行中的请求并退出。与托盘 / 悬浮窗关闭行为一致。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("退出 Overplay") {
                    AppPanels.confirmQuit(model: model)
                }
            }
        }
    }

    private func row(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}
