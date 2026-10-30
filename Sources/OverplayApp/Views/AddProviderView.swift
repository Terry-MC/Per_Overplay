import SwiftUI
import OverplayCore

struct AddProviderView: View {
    @ObservedObject var model: AppModel
    var onEdit: (Account) -> Void
    var onDelete: (Account) -> Void

    @State private var provider: ProviderKind = .deepseek
    @State private var displayName = ""
    @State private var officialName = ""
    @State private var iconName = ""
    @State private var apiKey = ""
    @State private var baseURL = ""
    @State private var endpointPath = "/"
    @State private var authMode: GenericAuthMode = .bearer
    @State private var headerName = "X-API-Key"
    @State private var mapping = GenericFieldMapping()
    @State private var warningRule = AlertLineRule.off
    @State private var criticalRule = AlertLineRule.off
    @State private var warningValue = ""
    @State private var criticalValue = ""
    @State private var warningCurrency = "USD"
    @State private var criticalCurrency = "USD"
    @State private var warningPercent = ""
    @State private var criticalPercent = ""
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var testResult: ConnectionTestResult?
    @State private var formError: String?
    @State private var alertAccount: Account?
    @State private var editingAlertConfig = AccountAlertConfig.off
    @State private var editingAccount: Account?
    @State private var lastSignature = ""
    @State private var lastPublicSignature = ""
    @State private var lastConnectionSignature = ""

    private let iconOptions = AccountIconCatalog.options

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            publicAlertSection
            formSection
            accountsSection
        }
        .onAppear {
            warningPercent = NSDecimalNumber(decimal: model.settings.publicAlertConfig.warningPercent).stringValue
            criticalPercent = NSDecimalNumber(decimal: model.settings.publicAlertConfig.criticalPercent).stringValue
            lastSignature = formSignature
            lastPublicSignature = publicSignature
            lastConnectionSignature = connectionSignature
            openDebugAlertSheetIfNeeded()
            openDebugEditIfNeeded()
        }
        .onChange(of: model.debugAlertLineAccountId) { _, _ in
            openDebugAlertSheetIfNeeded()
        }
        .onChange(of: model.debugEditAccountId) { _, _ in
            openDebugEditIfNeeded()
        }
        .onChange(of: formSignature) { _, _ in
            refreshUnsavedFlag()
        }
        .onChange(of: publicSignature) { _, _ in
            refreshUnsavedFlag()
        }
        .onChange(of: connectionSignature) { _, newValue in
            guard newValue != lastConnectionSignature else { return }
            lastConnectionSignature = newValue
            testResult = nil
        }
        .onChange(of: model.providerFormResetToken) { _, _ in
            resetForm()
        }
        .sheet(item: $alertAccount) { account in
            AlertLineEditorSheet(
                model: model,
                account: account,
                initialConfig: editingAlertConfig
            )
        }
    }

    private var publicAlertSection: some View {
        SectionCard(title: L10n.t("addProvider.256a49ee94"), isDemo: model.isDemo) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("addProvider.0463694499"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    labeledField(L10n.t("addProvider.915b1d4671"), text: $warningPercent, width: 130, required: true)
                    labeledField(L10n.t("addProvider.4775c9323b"), text: $criticalPercent, width: 130, required: true)
                    Spacer()
                    Button(L10n.t("addProvider.f3b0b7aef7")) { savePublicConfig() }
                        .disabled(model.isDemo || publicConfigError != nil)
                }
                if let publicConfigError {
                    Label(publicConfigError, systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if model.isDemo {
                    Text(L10n.t("addProvider.2f44438a0e"))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var formSection: some View {
        SectionCard(
            title: editingAccount == nil ? L10n.t("dashboard.addProvider") : L10n.t("addProvider.f501f28f26"),
            subtitle: L10n.t("addProvider.a34c8ea0c9"),
            isDemo: model.isDemo
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker(L10n.t("core.csv.0c131e3964"), selection: $provider) {
                    Text("DeepSeek").tag(ProviderKind.deepseek)
                    Text("OpenRouter").tag(ProviderKind.openrouter)
                    Text(L10n.t("provider.genericHTTP.name")).tag(ProviderKind.genericHTTP)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(editingAccount != nil)

                Text(L10n.t("addProvider.c640421fd7"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    labeledField(L10n.t("addProvider.8e759b9280"), text: $displayName, width: 220)
                    labeledField(L10n.t("addProvider.b0fb41120b"), text: $officialName, width: 200)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("addProvider.55e34a70b1")).font(.caption).foregroundStyle(.secondary)
                        Picker(L10n.t("addProvider.1f24c1e5aa"), selection: $iconName) {
                            Text(L10n.t("addProvider.74812bf1e2")).tag("")
                            ForEach(iconOptions, id: \.self) { name in
                                Label(name, systemImage: name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(L10n.t("addProvider.fe7e771d82"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(L10n.t("addProvider.32945d3e36"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    HStack(spacing: 12) {
                        SecureField("API Key / Management Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 420)
                        Button {
                            Task { await runTest() }
                        } label: {
                            if isTesting {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(L10n.t("addProvider.10b7d8eccc"), systemImage: "bolt.horizontal.circle")
                            }
                        }
                        .disabled(
                            isTesting || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                    if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(L10n.t("addProvider.1be0f4f3e9"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if model.isDemo {
                    Text(L10n.t("addProvider.1801f70f4e"))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if provider == .genericHTTP {
                    genericHTTPFields
                }

                alertLineFields

                if let testResult {
                    testResultView(testResult)
                }
                if let formError {
                    InlineErrorView(message: formError)
                }

                Text(L10n.t("addProvider.937391fd7d"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let reason = saveDisabledReason, !isSaving {
                    Label(reason, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(model.isDemo ? .orange : .red)
                }
                if !missingRequirements.isEmpty, !isSaving {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("addProvider.f949a784d6"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(missingRequirements, id: \.self) { item in
                            Text("• \(item)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Text(L10n.t("addProvider.5af73c60a1"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if editingAccount != nil {
                        Button(L10n.t("addProvider.c698df948d")) { resetForm() }
                    }
                    Button(L10n.t("addProvider.84fcd70d42")) { resetForm() }
                    Button {
                        save()
                    } label: {
                        if isSaving { ProgressView().controlSize(.small) }
                        Text(editingAccount == nil ? L10n.t("addProvider.2e1d532a2e") : L10n.t("addProvider.60b4ae9082"))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saveDisabledReason != nil || isSaving)
                }
            }
        }
    }

    private var genericHTTPFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(L10n.t("addProvider.e41e08ff76")).font(.headline)
            HStack(spacing: 12) {
                labeledField("Base URL", text: $baseURL, width: 300, required: true)
                labeledField(L10n.t("addProvider.e3a2fc0649"), text: $endpointPath, width: 160, required: true)
                Picker(L10n.t("addProvider.32c808cbe5"), selection: $authMode) {
                    ForEach(GenericAuthMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .frame(width: 190)
                if authMode == .header {
                    labeledField(L10n.t("addProvider.0003b78466"), text: $headerName, width: 150, required: true)
                }
            }
            DisclosureGroup {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                    mappingField(L10n.t("addProvider.826ac2fd3e"), text: $mapping.balanceTotal)
                    mappingField(L10n.t("addProvider.69c3705939"), text: $mapping.balanceCurrency)
                    mappingField(L10n.t("addProvider.c4d715ed2e"), text: $mapping.balanceGranted)
                    mappingField(L10n.t("addProvider.b237b1d2b8"), text: $mapping.balanceToppedUp)
                    mappingField(L10n.t("addProvider.4954023e67"), text: $mapping.creditsTotal)
                    mappingField(L10n.t("addProvider.a76f5f2fb2"), text: $mapping.creditsUsed)
                    mappingField(L10n.t("addProvider.cf7635f4ac"), text: $mapping.creditsCurrency)
                    mappingField(L10n.t("addProvider.6087c62b9d"), text: $mapping.usageDay)
                    mappingField("Prompt tokens", text: $mapping.promptTokens)
                    mappingField("Completion tokens", text: $mapping.completionTokens)
                    mappingField(L10n.t("core.analysisRange.b28376ff80"), text: $mapping.requests)
                    mappingField(L10n.t("metric.cost"), text: $mapping.cost)
                    mappingField(L10n.t("addProvider.f6fac936dd"), text: $mapping.usageCurrency)
                }
                .padding(.top, 6)
                Text(L10n.t("addProvider.9879e9c1ac"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } label: {
                HStack(spacing: 6) {
                    Text(L10n.t("addProvider.6dfa49e0ca"))
                    Text(L10n.t("addProvider.3f0e0eea30"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
            .font(.callout)
        }
    }

    private var alertLineFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 6) {
                Text(L10n.t("addProvider.e6733b3e08")).font(.headline)
                Text(L10n.t("addProvider.4b7a9ed7f8")).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 20) {
                AlertLineRuleEditor(
                    title: L10n.t("addProvider.35f0803018"),
                    rule: $warningRule,
                    valueText: $warningValue,
                    currency: $warningCurrency
                )
                AlertLineRuleEditor(
                    title: L10n.t("addProvider.8d56556021"),
                    rule: $criticalRule,
                    valueText: $criticalValue,
                    currency: $criticalCurrency
                )
            }
            if let error = alertConfigError() {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func mappingField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField(L10n.t("addProvider.c94c8d5a6c"), text: text)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
    }

    private func labeledField(
        _ title: String,
        text: Binding<String>,
        width: CGFloat,
        required: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                if required {
                    Text(L10n.t("addProvider.32945d3e36")).font(.caption2.weight(.semibold)).foregroundStyle(.red)
                }
            }
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }

    private var accountsSection: some View {
        SectionCard(title: L10n.t("addProvider.f1f1d49a12"), subtitle: L10n.f("settings.3c12d9513d", model.accounts.count), isDemo: model.isDemo) {
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
                                    if account.alertConfig != nil {
                                        Text(L10n.t("addProvider.8dee2d6c0e")).font(.caption2).foregroundStyle(.blue)
                                    }
                                }
                                Text(
                                    [
                                        account.provider.displayName,
                                        account.officialName.map { L10n.f("settings.cf2ff9d62a", $0) },
                                        account.capabilities.summary
                                    ].compactMap { $0 }.joined(separator: " · ")
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(L10n.t("metric.alertLine")) {
                                editingAlertConfig = account.alertConfig ?? legacyAlertConfig(for: account)
                                alertAccount = account
                            }
                            .disabled(model.isDemo)
                            Button(L10n.t("common.edit")) {
                                if account.provider == .genericHTTP {
                                    startEditing(account)
                                } else {
                                    onEdit(account)
                                }
                            }
                            .disabled(model.isDemo)
                            Button(L10n.t("common.delete")) { onDelete(account) }
                                .disabled(model.isDemo)
                        }
                        if account.id != model.accounts.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func testResultView(_ result: ConnectionTestResult) -> some View {
        let color: Color
        let symbol: String
        switch result.category {
        case .success:
            color = .green; symbol = "checkmark.seal.fill"
        case .invalidCredential, .permission:
            color = .red; symbol = "key.slash.fill"
        case .rateLimited, .timeout, .network, .address:
            color = .orange; symbol = "exclamationmark.triangle.fill"
        case .malformed, .unknown:
            color = .orange; symbol = "questionmark.circle.fill"
        }
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(result.message).font(.callout).textSelection(.enabled)
                if let capabilities = result.capabilities {
                    Text(L10n.f("addProvider.b288ee97ca", capabilities.summary))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let retryAfter = result.retryAfter {
                    Text(L10n.f("addProvider.316e324035", Int(retryAfter.rounded())))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var genericConfig: GenericHTTPConfig? {
        guard provider == .genericHTTP else { return nil }
        return GenericHTTPConfig(
            baseURL: baseURL,
            endpointPath: endpointPath,
            authMode: authMode,
            headerName: headerName,
            mapping: mapping
        )
    }

    private func runTest() async {
        formError = nil
        testResult = nil
        if model.isDemo {
            isTesting = true
            try? await Task.sleep(nanoseconds: 250_000_000)
            testResult = ConnectionTestResult(
                category: .success,
                message: L10n.t("addProvider.bcb630201d"),
                capabilities: provider == .genericHTTP ? genericConfig?.capabilities : provider.capabilities
            )
            isTesting = false
            model.hasUnsavedChanges = true
            return
        }
        isTesting = true
        defer { isTesting = false }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await model.testConnection(
            provider: provider,
            apiKey: key,
            genericConfig: genericConfig
        )
        testResult = result
        if result.category == .success {
            model.hasUnsavedChanges = true
        }
    }

    private func save() {
        formError = nil
        if let error = alertConfigError() {
            formError = error
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            if let editingAccount {
                try model.updateAccount(
                    editingAccount,
                    name: displayName,
                    newAPIKey: apiKey.isEmpty ? nil : apiKey,
                    officialName: officialName,
                    iconName: iconName,
                    genericConfig: genericConfig,
                    alertConfig: makeAlertConfig()
                )
            } else {
                _ = try model.saveNewAccount(
                    provider: provider,
                    name: displayName,
                    apiKey: apiKey,
                    officialName: officialName,
                    iconName: iconName,
                    genericConfig: genericConfig,
                    alertConfig: makeAlertConfig()
                )
            }
            model.hasUnsavedChanges = false
            resetForm()
        } catch {
            formError = error.localizedDescription
        }
    }

    private func legacyAlertConfig(for account: Account) -> AccountAlertConfig {
        if let budget = account.budget {
            _ = budget
            return AccountAlertConfig(
                warning: AlertLineRule(mode: .custom, metric: .budgetPercent, value: 80),
                critical: AlertLineRule(mode: .custom, metric: .budgetPercent, value: 100)
            )
        }
        if let threshold = account.balanceThreshold {
            return AccountAlertConfig(
                warning: AlertLineRule(
                    mode: .custom,
                    metric: .balanceAbsolute,
                    value: threshold.amount,
                    currency: threshold.currency
                ),
                critical: .off
            )
        }
        return .off
    }

    private func openDebugAlertSheetIfNeeded() {
        guard let accountId = model.debugAlertLineAccountId,
              let account = model.accounts.first(where: { $0.id == accountId }) else { return }
        editingAlertConfig = account.alertConfig ?? legacyAlertConfig(for: account)
        alertAccount = account
        model.debugAlertLineAccountId = nil
    }

    private func openDebugEditIfNeeded() {
        guard let accountId = model.debugEditAccountId,
              let account = model.accounts.first(where: { $0.id == accountId }) else { return }
        if editingAccount?.id != accountId {
            startEditing(account)
        }
        model.debugEditAccountId = nil
    }

    private func startEditing(_ account: Account) {
        editingAccount = account
        provider = account.provider
        displayName = account.displayName
        officialName = account.officialName ?? ""
        iconName = account.iconName ?? ""
        apiKey = ""
        if let config = account.genericConfig {
            baseURL = config.baseURL
            endpointPath = config.endpointPath
            authMode = config.authMode
            headerName = config.headerName
            mapping = config.mapping
        }
        let alertConfig = account.alertConfig ?? .off
        warningRule = alertConfig.warning
        criticalRule = alertConfig.critical
        warningValue = alertConfig.warning.value.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        criticalValue = alertConfig.critical.value.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        warningCurrency = alertConfig.warning.currency ?? "USD"
        criticalCurrency = alertConfig.critical.currency ?? "USD"
        testResult = nil
        formError = nil
        model.hasUnsavedChanges = false
        lastSignature = formSignature
        lastPublicSignature = publicSignature
        lastConnectionSignature = connectionSignature
    }

    private func makeAlertConfig() -> AccountAlertConfig {
        var warning = warningRule
        warning.value = parseDecimal(warningValue)
        warning.currency = warning.metric == .balanceAbsolute ? warningCurrency : nil
        var critical = criticalRule
        critical.value = parseDecimal(criticalValue)
        critical.currency = critical.metric == .balanceAbsolute ? criticalCurrency : nil
        return AccountAlertConfig(warning: warning, critical: critical)
    }

    private func parseDecimal(_ text: String) -> Decimal? {
        parseAlertDecimal(text)
    }

    private func savePublicConfig() {
        guard let warning = parseDecimal(warningPercent),
              let critical = parseDecimal(criticalPercent),
              warning >= 0, critical >= 0 else {
            formError = L10n.t("addProvider.0bd6bc968a")
            return
        }
        guard warning <= critical else {
            formError = L10n.t("addProvider.c6da5c774d")
            return
        }
        formError = nil
        model.savePublicAlertConfig(PublicAlertConfig(
            warningPercent: warning,
            criticalPercent: critical
        ))
        lastPublicSignature = publicSignature
        refreshUnsavedFlag()
    }

    private var publicConfigError: String? {
        guard let warning = parseDecimal(warningPercent),
              let critical = parseDecimal(criticalPercent) else {
            return L10n.t("addProvider.44185ab68e")
        }
        guard warning >= 0, critical >= 0 else { return L10n.t("addProvider.74bc48018d") }
        guard warning <= critical else { return L10n.t("addProvider.c6da5c774d") }
        return nil
    }

    private func alertConfigError() -> String? {
        alertLineValidationError(
            warning: warningRule,
            warningValue: warningValue,
            warningCurrency: warningCurrency,
            critical: criticalRule,
            criticalValue: criticalValue,
            criticalCurrency: criticalCurrency
        )
    }

    private var missingRequirements: [String] {
        var items: [String] = []
        if let error = alertConfigError() { items.append(error) }
        if let editingAccount {
            let keyChanged = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let configurationChanged = provider == .genericHTTP
                && genericConfig != editingAccount.genericConfig
            if (keyChanged || configurationChanged), testResult?.category != .success {
                items.append(L10n.t("addProvider.f1270c8edc"))
            }
            return items
        }
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append("API Key / Management Key")
        }
        if testResult?.category != .success {
            items.append(L10n.t("addProvider.bfbf35fbdc"))
        }
        if provider == .genericHTTP {
            if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append("Base URL")
            }
            if !(mapping.hasBalanceMapping || mapping.hasCreditsMapping || mapping.hasUsageMapping) {
                items.append(L10n.t("addProvider.80d49eefdd"))
            }
        }
        return items
    }

    private var saveDisabledReason: String? {
        if model.isDemo { return L10n.t("addProvider.b7eb28ffaf") }
        if let error = alertConfigError() { return error }
        if let editingAccount {
            let keyChanged = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let configurationChanged = provider == .genericHTTP
                && genericConfig != editingAccount.genericConfig
            if (keyChanged || configurationChanged), testResult?.category != .success {
                return L10n.t("addProvider.2293d9db95")
            }
            return nil
        }
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.t("addProvider.06a25be6f7")
        }
        if testResult?.category != .success {
            return L10n.t("addProvider.014f743be8")
        }
        if provider == .genericHTTP {
            if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return L10n.t("addProvider.2a80065f19")
            }
            if !(mapping.hasBalanceMapping || mapping.hasCreditsMapping || mapping.hasUsageMapping) {
                return L10n.t("addProvider.551f3f0768")
            }
        }
        return nil
    }

    private func resetForm() {
        editingAccount = nil
        displayName = ""
        officialName = ""
        iconName = ""
        apiKey = ""
        baseURL = ""
        endpointPath = "/"
        authMode = .bearer
        headerName = "X-API-Key"
        mapping = GenericFieldMapping()
        warningRule = .off
        criticalRule = .off
        warningValue = ""
        criticalValue = ""
        warningCurrency = "USD"
        criticalCurrency = "USD"
        testResult = nil
        formError = nil
        warningPercent = NSDecimalNumber(decimal: model.settings.publicAlertConfig.warningPercent).stringValue
        criticalPercent = NSDecimalNumber(decimal: model.settings.publicAlertConfig.criticalPercent).stringValue
        model.hasUnsavedChanges = false
        lastSignature = formSignature
        lastPublicSignature = publicSignature
        lastConnectionSignature = connectionSignature
    }

    private var publicSignature: String {
        [warningPercent, criticalPercent].joined(separator: "|")
    }

    private func refreshUnsavedFlag() {
        model.hasUnsavedChanges = formSignature != lastSignature
            || publicSignature != lastPublicSignature
    }

    private var connectionSignature: String {
        [
            provider.rawValue, apiKey, baseURL, endpointPath, authMode.rawValue,
            headerName, mapping.balanceTotal, mapping.balanceCurrency,
            mapping.balanceGranted, mapping.balanceToppedUp, mapping.creditsTotal,
            mapping.creditsUsed, mapping.creditsCurrency, mapping.usageDay,
            mapping.promptTokens, mapping.completionTokens, mapping.requests,
            mapping.cost, mapping.usageCurrency
        ].joined(separator: "|")
    }

    private var formSignature: String {
        [
            provider.rawValue, displayName, officialName, iconName, apiKey,
            baseURL, endpointPath, authMode.rawValue, headerName,
            mapping.balanceTotal, mapping.balanceCurrency, mapping.balanceGranted,
            mapping.balanceToppedUp, mapping.creditsTotal, mapping.creditsUsed,
            mapping.creditsCurrency, mapping.usageDay, mapping.promptTokens,
            mapping.completionTokens, mapping.requests, mapping.cost,
            mapping.usageCurrency,
            warningRule.mode.rawValue, warningRule.metric.rawValue, warningValue,
            warningCurrency,
            criticalRule.mode.rawValue, criticalRule.metric.rawValue, criticalValue,
            criticalCurrency
        ].joined(separator: "|")
    }
}

private func parseAlertDecimal(_ text: String) -> Decimal? {
    Decimal(
        string: text.trimmingCharacters(in: .whitespacesAndNewlines),
        locale: Locale(identifier: "en_US_POSIX")
    )
}

private func alertLineValidationError(
    warning: AlertLineRule,
    warningValue: String,
    warningCurrency: String,
    critical: AlertLineRule,
    criticalValue: String,
    criticalCurrency: String
) -> String? {
    let entries: [(String, AlertLineRule, String, String)] = [
        (L10n.t("addProvider.35f0803018"), warning, warningValue, warningCurrency),
        (L10n.t("addProvider.8d56556021"), critical, criticalValue, criticalCurrency)
    ]
    for (title, rule, valueText, currencyText) in entries {
        if rule.mode == .custom {
            guard let value = parseAlertDecimal(valueText), value >= 0 else {
                return L10n.f("addProvider.ea5b48a14e", title)
            }
            if rule.metric == .balanceAbsolute,
               currencyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return L10n.f("addProvider.06fcc8e0e8", title)
            }
        }
        if rule.mode == .followPublic, !rule.metric.usesPercent {
            return L10n.f("addProvider.14195f9d08", title)
        }
    }
    return nil
}

struct AlertLineRuleEditor: View {
    var title: String
    @Binding var rule: AlertLineRule
    @Binding var valueText: String
    @Binding var currency: String
    var currencyOptions: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Picker(L10n.t("addProvider.ed0eea8f20"), selection: $rule.mode) {
                ForEach(AlertLineMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .frame(width: 140)
            if rule.mode != .off {
                Picker(L10n.t("providerDetail.1dfc810a7b"), selection: $rule.metric) {
                    ForEach(AlertMetricKind.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .frame(width: 160)
                if rule.mode == .custom {
                    HStack(spacing: 6) {
                        TextField(L10n.t("addProvider.6adebf0e91"), text: $valueText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                        if rule.metric == .balanceAbsolute {
                            if currencyOptions.isEmpty {
                                TextField(L10n.t("addProvider.4420803f5c"), text: $currency)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 110)
                            } else {
                                Picker(L10n.t("core.csv.a81ab5e100"), selection: $currency) {
                                    ForEach(currencyOptions, id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                    if !currency.isEmpty, !currencyOptions.contains(currency) {
                                        Text(currency).tag(currency)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 110)
                            }
                        }
                    }
                    Text(L10n.t("addProvider.97242298d6"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(sourceHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceHint: String {
        switch rule.mode {
        case .off: return L10n.t("addProvider.5efd4d47ea")
        case .followPublic:
            return rule.metric.usesPercent ? L10n.t("addProvider.424dcac639") : L10n.t("addProvider.b8b447db67")
        case .custom:
            return L10n.t("addProvider.c335424524")
        }
    }
}

private struct AlertLineEditorSheet: View {
    @ObservedObject var model: AppModel
    let account: Account
    @Environment(\.dismiss) private var dismiss
    @State private var warning: AlertLineRule
    @State private var critical: AlertLineRule
    @State private var warningValue: String
    @State private var criticalValue: String
    @State private var warningCurrency: String
    @State private var criticalCurrency: String

    init(model: AppModel, account: Account, initialConfig: AccountAlertConfig) {
        self.model = model
        self.account = account
        _warning = State(initialValue: initialConfig.warning)
        _critical = State(initialValue: initialConfig.critical)
        _warningValue = State(initialValue: initialConfig.warning.value.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        _criticalValue = State(initialValue: initialConfig.critical.value.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        _warningCurrency = State(initialValue: initialConfig.warning.currency ?? "USD")
        _criticalCurrency = State(initialValue: initialConfig.critical.currency ?? "USD")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.f("addProvider.784c71fc2d", account.displayName)).font(.title3.weight(.semibold))
                Spacer()
                if model.isDemo { DemoTag() }
            }
            .padding(20)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                AlertLineRuleEditor(
                    title: L10n.t("addProvider.35f0803018"),
                    rule: $warning,
                    valueText: $warningValue,
                    currency: $warningCurrency,
                    currencyOptions: currencyOptions
                )
                AlertLineRuleEditor(
                    title: L10n.t("addProvider.8d56556021"),
                    rule: $critical,
                    valueText: $criticalValue,
                    currency: $criticalCurrency,
                    currencyOptions: currencyOptions
                )
                Text(L10n.f("addProvider.00c962f137", Money.percent(model.settings.publicAlertConfig.warningPercent), Money.percent(model.settings.publicAlertConfig.criticalPercent)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if account.alertConfig == nil, let legacySummary {
                    Text(legacySummary)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if let validationMessage {
                    InlineErrorView(message: validationMessage)
                }
            }
            .padding(20)
            Divider()
            HStack(spacing: 12) {
                Button(L10n.t("common.cancel")) { dismiss() }
                Spacer()
                if model.isDemo {
                    Text(L10n.t("addProvider.fec9108615"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if validationMessage != nil {
                    Text(L10n.t("addProvider.6707877e5e"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button(L10n.t("common.save")) { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isDemo || validationMessage != nil)
            }
            .padding(16)
        }
        .frame(width: 620)
    }

    private var validationMessage: String? {
        alertLineValidationError(
            warning: warning,
            warningValue: warningValue,
            warningCurrency: warningCurrency,
            critical: critical,
            criticalValue: criticalValue,
            criticalCurrency: criticalCurrency
        )
    }

    private var currencyOptions: [String] {
        var options = Set(model.latestBalances(for: account).map(\.currency))
        if let currency = account.budget?.currency { options.insert(currency) }
        if !warningCurrency.isEmpty { options.insert(warningCurrency) }
        if !criticalCurrency.isEmpty { options.insert(criticalCurrency) }
        return options.sorted()
    }

    private var legacySummary: String? {
        var parts: [String] = []
        if let budget = account.budget {
            parts.append(L10n.f("addProvider.e3ab847cbd", budget.amount, budget.currency))
        }
        if let threshold = account.balanceThreshold {
            parts.append(L10n.f("addProvider.ba0d578b41", threshold.amount, threshold.currency))
        }
        guard !parts.isEmpty else { return nil }
        return L10n.t("addProvider.419ec83f6c") + parts.joined(separator: L10n.t("common.listSeparator"))
            + L10n.t("addProvider.e51771b635")
    }

    private func save() {
        guard validationMessage == nil else { return }
        var warningRule = warning
        warningRule.value = parseAlertDecimal(warningValue)
        warningRule.currency = warning.metric == .balanceAbsolute ? warningCurrency : nil
        var criticalRule = critical
        criticalRule.value = parseAlertDecimal(criticalValue)
        criticalRule.currency = critical.metric == .balanceAbsolute ? criticalCurrency : nil
        model.saveAccountAlertConfig(account, config: AccountAlertConfig(
            warning: warningRule,
            critical: criticalRule
        ))
        dismiss()
    }
}
