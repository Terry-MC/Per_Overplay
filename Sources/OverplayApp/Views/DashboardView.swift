import SwiftUI
import OverplayCore

struct DashboardView: View {
    @ObservedObject var model: AppModel
    var onSwitchToFloating: () -> Void = {}

    @State private var showAddAccount = false
    @State private var editAccount: Account?
    @State private var deleteAccount: Account?

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.isDemo { DemoBanner() }
            if let warning = model.initializationWarning {
                InlineErrorView(message: warning)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }

            if model.showOnboarding && !model.isDemo {
                OnboardingView(model: model) {
                    showAddAccount = true
                }
            } else {
                tabBar
                Divider()
                ScrollView {
                    content
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .frame(maxWidth: 1360, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .frame(minWidth: 1080, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .topTrailing) {
            ToastStackView(model: model)
                .padding(.top, model.isDemo ? 150 : 112)
                .padding(.trailing, 20)
                .zIndex(10)
        }
        .sheet(isPresented: $showAddAccount) {
            AccountEditorView(model: model, mode: .add)
        }
        .sheet(item: $editAccount) { account in
            AccountEditorView(model: model, mode: .edit(account))
        }
        .sheet(item: $deleteAccount) { account in
            DeleteAccountSheet(model: model, account: account)
        }
        .sheet(isPresented: $model.showMessageCenter) {
            MessageCenterView(model: model)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text("Overplay").font(.title2.weight(.bold))
                        if model.isDemo { DemoTag() }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !model.showOnboarding || model.isDemo {
                Button {
                    onSwitchToFloating()
                } label: {
                    Label("简略版", systemImage: "rectangle.on.rectangle")
                }
                .help("切换到简略版悬浮窗")
                Button {
                    model.showMessageCenter = true
                } label: {
                    HStack(spacing: 5) {
                        Image(
                            systemName: model.unacknowledgedAlertCount > 0
                                ? "bell.badge.fill"
                                : "bell"
                        )
                        Text("消息")
                        if model.unacknowledgedAlertCount > 0 {
                            Text(
                                model.unacknowledgedAlertCount > 99
                                    ? "99+"
                                    : "\(model.unacknowledgedAlertCount)"
                            )
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red.opacity(0.16)))
                            .foregroundStyle(.red)
                        }
                    }
                }
                .help("打开消息中心")
                Button {
                    model.refreshAll()
                } label: {
                    Label("刷新全部", systemImage: "arrow.clockwise")
                }
                .disabled(model.isDemo || model.accounts.isEmpty)
                if !model.isDemo {
                    Button {
                        showAddAccount = true
                    } label: {
                        Label("添加账户", systemImage: "plus")
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }

    private var subtitle: String {
        let base: String
        if model.isDemo {
            base = "演示模式 · 固定本地模拟数据 · 不发起网络请求"
        } else if model.accounts.isEmpty {
            base = "数据仅保存在本机 · 密钥仅存 Keychain"
        } else {
            base = "\(model.accounts.count) 个账户 · 自动刷新每 \(model.settings.refreshIntervalMinutes) 分钟"
        }
        if let last = model.lastRefreshAllAt {
            return base + " · 最近操作 " + DateFormatters.shortTime.string(from: last)
        }
        return base
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(DashboardTab.allCases) { tab in
                Button {
                    model.selectedTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                        Text(tab.title)
                    }
                    .font(.subheadline.weight(model.selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(model.selectedTab == tab ? Color.accentColor : .secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(model.selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.selectedTab == tab ? .isSelected : [])
            }
            Spacer()
            if model.isDemo {
                Text(DemoMode.shortBadge)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        switch model.selectedTab {
        case .overview:
            OverviewView(
                model: model,
                onEdit: { editAccount = $0 },
                onDelete: { deleteAccount = $0 }
            )
        case .usage:
            UsageView(model: model)
        case .quota:
            QuotaView(model: model)
        case .settings:
            SettingsView(
                model: model,
                onAddAccount: { showAddAccount = true },
                onEditAccount: { editAccount = $0 },
                onDeleteAccount: { deleteAccount = $0 }
            )
        }
    }

}
