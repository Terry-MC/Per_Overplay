import SwiftUI
import UniformTypeIdentifiers
import OverplayCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var onAddAccount: () -> Void
    var onEditAccount: (Account) -> Void
    var onDeleteAccount: (Account) -> Void
    @State private var showLanguageImporter = false
    @State private var languageError: String?

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
            languageSection
            generalSection
            accountsSection
            demoSection
            privacySection
            aboutSection
            exitSection
        }
    }

    private var languageSection: some View {
        SectionCard(title: L10n.t("settings.language.title"), isDemo: model.isDemo) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("settings.language.picker")).font(.subheadline.weight(.semibold))
                        Text(L10n.t("settings.language.description"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker(L10n.t("settings.language.picker"), selection: Binding(
                        get: { model.selectedLanguageIdentifier },
                        set: { model.setLanguage(identifier: $0) }
                    )) {
                        ForEach(model.languageOptions) { language in
                            Text(language.displayName).tag(language.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                HStack(spacing: 10) {
                    Button {
                        languageError = nil
                        showLanguageImporter = true
                    } label: {
                        Label(L10n.t("settings.language.import"), systemImage: "square.and.arrow.down")
                    }
                    .disabled(model.isDemo)
                    if let pack = model.selectedImportedLanguagePack {
                        Text(L10n.f("settings.language.current", pack.displayName, pack.locale))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(L10n.t("settings.language.remove"), role: .destructive) {
                            do {
                                try model.removeLanguagePack(locale: pack.locale)
                                languageError = nil
                            } catch {
                                languageError = error.localizedDescription
                            }
                        }
                        .disabled(model.isDemo)
                    }
                    Spacer()
                }
                if model.isDemo {
                    Text(L10n.t("settings.language.demo"))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if let languageError {
                    InlineErrorView(message: languageError)
                }
                Text(L10n.t("settings.language.format"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fileImporter(
            isPresented: $showLanguageImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                do {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= LocalizedLanguagePack.maxFileSize else {
                        throw LanguagePackError.fileTooLarge
                    }
                    let data = try Data(contentsOf: url)
                    _ = try model.importLanguagePack(
                        data: data,
                        sourceFileName: url.lastPathComponent
                    )
                    languageError = nil
                } catch {
                    languageError = error.localizedDescription
                }
            case .failure(let error):
                languageError = error.localizedDescription
            }
        }
    }

    private var generalSection: some View {
        SectionCard(title: L10n.t("settings.a69e4d32ff"), isDemo: model.isDemo) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("settings.c652467e5f")).font(.subheadline.weight(.semibold))
                        Text(L10n.t("settings.fc9d1e60c1"))
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
                        Text(L10n.f("settings.eb7fa47f34", model.settings.refreshIntervalMinutes))
                            .monospacedDigit()
                            .frame(width: 160, alignment: .trailing)
                    }
                    .disabled(model.isDemo)
                }
                if model.isDemo {
                    Text(L10n.t("settings.22623bd653"))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Divider()
                Toggle(isOn: Binding(
                    get: { model.settings.notificationsEnabled },
                    set: { model.setNotificationsEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("settings.3800bcfe61")).font(.subheadline.weight(.semibold))
                        Text(L10n.t("settings.e65c46c8c6"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(model.isDemo)
                HStack(spacing: 10) {
                    if model.isDemo {
                        Text(L10n.t("settings.2a71fdbf4b"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text(L10n.f("settings.7230d66187", model.notificationStatusText))
                            .font(.caption)
                            .foregroundStyle(model.notificationStatus == .denied ? .orange : .secondary)
                        if model.notificationStatus == .denied {
                            Button(L10n.t("settings.cbda26274d")) {
                                model.openNotificationSettings()
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                            Text(L10n.t("settings.41836e4926"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(L10n.t("settings.76ef862577")) {
                        model.sendTestNotification()
                    }
                    .disabled(model.isDemo || !model.settings.notificationsEnabled)
                }
            }
        }
    }

    private var accountsSection: some View {
        SectionCard(
            title: L10n.t("settings.accounts.title"),
            subtitle: L10n.f("settings.3c12d9513d", model.accounts.count),
            isDemo: model.isDemo
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if model.accounts.isEmpty {
                    Text(L10n.t("settings.4a6f4b687d"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.accounts) { account in
                        HStack(spacing: 10) {
                            ProviderMark(provider: account.provider, iconName: account.iconName)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(account.displayName).font(.subheadline.weight(.semibold))
                                    if model.isDemo || account.isDemo { DemoTag() }
                                }
                                Text(
                                    [
                                        account.provider.displayName,
                                        account.officialName.map { L10n.f("common.officialName", $0) },
                                        model.currencyLabel(for: account),
                                        model.capabilitySummary(for: account)
                                    ].compactMap { $0 }.joined(separator: " · ")
                                )
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
                            .help(account.enabled ? L10n.t("settings.9d06f77a8f") : L10n.t("settings.ae0ba48faa"))
                            Button(L10n.t("common.edit")) { onEditAccount(account) }
                                .disabled(model.isDemo)
                            Button(L10n.t("common.delete")) { onDeleteAccount(account) }
                                .disabled(model.isDemo)
                        }
                        if account.id != model.accounts.last?.id { Divider() }
                    }
                }
                if model.isDemo {
                    Text(L10n.t("settings.accounts.demoNote"))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button {
                        onAddAccount()
                    } label: {
                        Label(L10n.t("dashboard.c771c7d8e2"), systemImage: "plus")
                    }
                    .disabled(model.isDemo)
                    if model.isDemo {
                        Text(L10n.t("settings.55bfbfc2da"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                }
            }
        }
    }

    private var demoSection: some View {
        SectionCard(title: L10n.t("settings.fbd46976e0")) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "flask")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("settings.1e1a23e5ea"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(DemoMode.shortBadge)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if model.isDemo {
                    Button(L10n.t("settings.c7e8e58589")) { model.exitDemoMode() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(L10n.t("app.fb7f73f291")) { model.requestEnterDemoMode() }
                }
                Button(L10n.t("settings.ac7cf69b18")) { model.showDemoDisclaimer() }
            }
        }
    }

    private var privacySection: some View {
        SectionCard(title: L10n.t("settings.e8afd31bb8")) {
            VStack(alignment: .leading, spacing: 10) {
                row(L10n.t("settings.fc01c2ef5e"), model.dataFileDisplayPath, monospaced: true)
                row(L10n.t("settings.336f3130b2"), L10n.t("settings.32c1dc9cb5"))
                row(L10n.t("settings.9ad74ff12b"), L10n.t("settings.4430bf294f"))
                row(L10n.t("settings.157f2a9f1a"), L10n.t("settings.eeacf547b5"))
                row(L10n.t("settings.fb83bdc4d1"), L10n.t("settings.a856374dbd"))
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("component.4d045824c0")).font(.subheadline.weight(.semibold))
                        Text(L10n.t("settings.privacy.csvDescription"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        exportCSV()
                    } label: {
                        Label(L10n.t("usage.7e9cc8635e"), systemImage: "square.and.arrow.up")
                    }
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("settings.1fd211da86")).font(.subheadline.weight(.semibold))
                        Text(L10n.t("settings.c038e23212"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        model.confirmClearAllData()
                    } label: {
                        Text(L10n.t("app.04c3cd821d"))
                    }
                    .disabled(model.isDemo)
                }
                if model.isDemo {
                    Text(L10n.t("settings.fc0f6e5243"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var aboutSection: some View {
        SectionCard(title: L10n.t("settings.bed172efc9")) {
            VStack(alignment: .leading, spacing: 8) {
                row(L10n.t("settings.989d1affa0"), appVersion)
                Text(L10n.t("settings.07c1b20c2d"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Link(L10n.t("settings.5cef613ce4"), destination: URL(string: "https://github.com/Terry-MC/Per_Overplay")!)
                    Link(
                        L10n.t("settings.f37d8a7d9e"),
                        destination: URL(string: "https://openrouter.ai/docs/api-reference/credits/get-credits")!
                    )
                    Link(
                        L10n.t("settings.7a85386fbe"),
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
                    Text(L10n.t("settings.c7df833091")).font(.subheadline.weight(.semibold))
                    Text(L10n.t("settings.a001860143"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.t("statusBar.d94cefe4dc")) {
                    AppPanels.confirmQuit(model: model)
                }
            }
        }
    }

    private func exportCSV() {
        guard let export = model.csvExportData() else { return }
        AppPanels.saveCSV(filename: export.filename, data: export.data, isDemo: model.isDemo) { result in
            switch result {
            case .success:
                model.showBanner(L10n.f("usage.e69a391adc", export.filename), style: .success)
            case .failure(let error):
                model.showBanner(L10n.f("usage.af55c3ac40", L10n.t(error.localizedDescription)), style: .error)
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
