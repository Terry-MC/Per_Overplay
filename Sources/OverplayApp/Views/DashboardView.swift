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
        .environment(\.locale, model.effectiveLocale)
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
        .onChange(of: model.debugDeleteAccountId) { _, accountId in
            guard let accountId,
                  let account = model.accounts.first(where: { $0.id == accountId }) else { return }
            deleteAccount = account
            model.debugDeleteAccountId = nil
        }
    }

    private func requestEditAccount(_ account: Account) {
        if account.provider == .genericHTTP {
            model.selectedTab = .addProvider
            model.debugEditAccountId = account.id
        } else {
            editAccount = account
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
                    guard !model.hasUnsavedChanges
                        || AppPanels.confirmDiscardUnsaved(model: model, action: L10n.t("appDelegate.f9f838cb05")) else {
                        return
                    }
                    onSwitchToFloating()
                } label: {
                    Label(L10n.t("dashboard.616ab19888"), systemImage: "rectangle.on.rectangle")
                }
                .help(L10n.t("dashboard.b71d572be1"))
                Button {
                    model.showMessageCenter = true
                } label: {
                    HStack(spacing: 5) {
                        Image(
                            systemName: model.unacknowledgedAlertCount > 0
                                ? "bell.badge.fill"
                                : "bell"
                        )
                        Text(L10n.t("dashboard.dc6de3fa86"))
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
                .help(L10n.t("dashboard.4d7ebd8d8f"))
                Button {
                    model.refreshAll()
                } label: {
                    Label(L10n.t("common.refreshAll"), systemImage: "arrow.clockwise")
                }
                .disabled(model.isDemo || model.accounts.isEmpty)
                if !model.isDemo {
                    Button {
                        model.selectedTab = .addProvider
                    } label: {
                        Label(L10n.t("dashboard.c771c7d8e2"), systemImage: "plus")
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
            base = L10n.t("dashboard.d5a8c28716")
        } else if model.accounts.isEmpty {
            base = L10n.t("dashboard.3d56cbaef0")
        } else {
            base = L10n.f("dashboard.f2edf0faaa", model.accounts.count, model.settings.refreshIntervalMinutes)
        }
        if let last = model.lastRefreshAllAt {
            return base + L10n.t("dashboard.bdd1d3aedf") + DateFormatters.shortTime.string(from: last)
        }
        return base
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(DashboardTab.allCases) { tab in
                Button {
                    if model.selectedTab == .addProvider,
                       model.hasUnsavedChanges,
                       tab != .addProvider,
                       !AppPanels.confirmDiscardUnsaved(model: model, action: L10n.t("dashboard.e219258855")) {
                        return
                    }
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
            BaseInfoView(
                model: model,
                onEdit: { requestEditAccount($0) },
                onDelete: { deleteAccount = $0 }
            )
        case .usage:
            UsageView(model: model)
        case .quota:
            QuotaView(model: model)
        case .addProvider:
            AddProviderView(
                model: model,
                onEdit: { editAccount = $0 },
                onDelete: { deleteAccount = $0 }
            )
        case .settings:
            SettingsView(
                model: model,
                onAddAccount: { model.selectedTab = .addProvider },
                onEditAccount: { requestEditAccount($0) },
                onDeleteAccount: { deleteAccount = $0 }
            )
        }
    }

}
