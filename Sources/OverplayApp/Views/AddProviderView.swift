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
        }
        .onChange(of: model.debugAlertLineAccountId) { _, _ in
            openDebugAlertSheetIfNeeded()
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
        SectionCard(title: "公共告知线 / 警戒线", isDemo: model.isDemo) {
            VStack(alignment: .leading, spacing: 10) {
                Text("公共阈值只影响“跟随公共”的百分比告警线；绝对指标只能自定义。新账户默认关闭告警线。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    labeledField("告知线 %", text: $warningPercent, width: 130, required: true)
                    labeledField("警戒线 %", text: $criticalPercent, width: 130, required: true)
                    Spacer()
                    Button("保存公共阈值") { savePublicConfig() }
                        .disabled(model.isDemo || publicConfigError != nil)
                }
                if let publicConfigError {
                    Label(publicConfigError, systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if model.isDemo {
                    Text("演示模式不修改真实公共阈值。")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var formSection: some View {
        SectionCard(
            title: editingAccount == nil ? "新增厂商" : "编辑厂商",
            subtitle: "真实模式仅保存 DeepSeek / OpenRouter / 通用 HTTP",
            isDemo: model.isDemo
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("厂商", selection: $provider) {
                    Text("DeepSeek").tag(ProviderKind.deepseek)
                    Text("OpenRouter").tag(ProviderKind.openrouter)
                    Text("通用 HTTP").tag(ProviderKind.genericHTTP)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(editingAccount != nil)

                Text("OpenAI / Anthropic / Azure / Google Vertex / 内部网关等真实组织级连接器仍标记为“暂不支持”，本 Issue 不创建可监控账户。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    labeledField("显示名称（可选）", text: $displayName, width: 220)
                    labeledField("官方名称（可选）", text: $officialName, width: 200)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("图标（可选）").font(.caption).foregroundStyle(.secondary)
                        Picker("图标", selection: $iconName) {
                            Text("默认（厂商图标）").tag("")
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
                        Text("API Key / Management Key（仅写入 Keychain）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("必填")
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
                                Label("测试连接", systemImage: "bolt.horizontal.circle")
                            }
                        }
                        .disabled(
                            isTesting || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                    if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("请输入 Key 后点击“测试连接”；测试成功后才能保存新账户。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if model.isDemo {
                    Text("演示模式只模拟连接测试，不发起网络请求、不写 Keychain、不保存账户。")
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

                Text("必填：API Key / Management Key；通用 HTTP 另需 Base URL 与至少一个映射字段。可选：显示名称、官方名称、图标、告警线。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let reason = saveDisabledReason, !isSaving {
                    Label(reason, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(model.isDemo ? .orange : .red)
                }
                if !missingRequirements.isEmpty, !isSaving {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("保存前还需完成：")
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
                    Text("新增账户须连接测试成功后才能保存；编辑名称 / 图标可直接保存，修改通用 HTTP 端点或认证须重新测试。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if editingAccount != nil {
                        Button("取消编辑") { resetForm() }
                    }
                    Button("清空") { resetForm() }
                    Button {
                        save()
                    } label: {
                        if isSaving { ProgressView().controlSize(.small) }
                        Text(editingAccount == nil ? "保存并开始监控" : "保存修改")
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
            Text("通用 HTTP（单一 HTTPS 只读 GET 端点）").font(.headline)
            HStack(spacing: 12) {
                labeledField("Base URL", text: $baseURL, width: 300, required: true)
                labeledField("端点路径", text: $endpointPath, width: 160, required: true)
                Picker("认证", selection: $authMode) {
                    ForEach(GenericAuthMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .frame(width: 190)
                if authMode == .header {
                    labeledField("Header 名称", text: $headerName, width: 150, required: true)
                }
            }
            DisclosureGroup {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                    mappingField("余额 total", text: $mapping.balanceTotal)
                    mappingField("余额币种", text: $mapping.balanceCurrency)
                    mappingField("赠送余额", text: $mapping.balanceGranted)
                    mappingField("充值余额", text: $mapping.balanceToppedUp)
                    mappingField("额度 total", text: $mapping.creditsTotal)
                    mappingField("额度 used", text: $mapping.creditsUsed)
                    mappingField("额度币种", text: $mapping.creditsCurrency)
                    mappingField("用量日期", text: $mapping.usageDay)
                    mappingField("Prompt tokens", text: $mapping.promptTokens)
                    mappingField("Completion tokens", text: $mapping.completionTokens)
                    mappingField("请求数", text: $mapping.requests)
                    mappingField("费用", text: $mapping.cost)
                    mappingField("用量币种", text: $mapping.usageCurrency)
                }
                .padding(.top, 6)
                Text("未映射的指标显示“未配置”，不推断；不支持 OAuth、多端点或数组逐项映射。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } label: {
                HStack(spacing: 6) {
                    Text("JSON 字段映射（点号路径）")
                    Text("必填：至少一个")
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
                Text("新账户告警线").font(.headline)
                Text("可选，默认关闭").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 20) {
                AlertLineRuleEditor(
                    title: "告知线",
                    rule: $warningRule,
                    valueText: $warningValue,
                    currency: $warningCurrency
                )
                AlertLineRuleEditor(
                    title: "警戒线",
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
            TextField("例如 data.balance", text: text)
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
                    Text("必填").font(.caption2.weight(.semibold)).foregroundStyle(.red)
                }
            }
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }

    private var accountsSection: some View {
        SectionCard(title: "已接入厂商", subtitle: "\(model.accounts.count) 个", isDemo: model.isDemo) {
            VStack(alignment: .leading, spacing: 10) {
                if model.accounts.isEmpty {
                    Text("尚未添加账户。")
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
                                        Text("告警线已配置").font(.caption2).foregroundStyle(.blue)
                                    }
                                }
                                Text(
                                    [
                                        account.provider.displayName,
                                        account.officialName.map { "官方 \($0)" },
                                        account.capabilities.summary
                                    ].compactMap { $0 }.joined(separator: " · ")
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("告警线") {
                                editingAlertConfig = account.alertConfig ?? legacyAlertConfig(for: account)
                                alertAccount = account
                            }
                            .disabled(model.isDemo)
                            Button("编辑") {
                                if account.provider == .genericHTTP {
                                    startEditing(account)
                                } else {
                                    onEdit(account)
                                }
                            }
                            .disabled(model.isDemo)
                            Button("删除") { onDelete(account) }
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
                    Text("能力：\(capabilities.summary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let retryAfter = result.retryAfter {
                    Text("建议 \(Int(retryAfter.rounded())) 秒后重试")
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
                message: "演示模式：模拟连接成功；未联网、未写 Keychain、未保存账户",
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
            formError = "公共阈值必须是大于等于 0 的数字（币种、百分号请勿填入）"
            return
        }
        guard warning <= critical else {
            formError = "公共告知线不能高于警戒线"
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
            return "公共阈值必须是数字"
        }
        guard warning >= 0, critical >= 0 else { return "公共阈值不能为负数" }
        guard warning <= critical else { return "公共告知线不能高于警戒线" }
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
                items.append("修改 API Key 或通用 HTTP 配置后重新测试连接")
            }
            return items
        }
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append("API Key / Management Key")
        }
        if testResult?.category != .success {
            items.append("连接测试成功")
        }
        if provider == .genericHTTP {
            if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append("Base URL")
            }
            if !(mapping.hasBalanceMapping || mapping.hasCreditsMapping || mapping.hasUsageMapping) {
                items.append("至少一个余额 / 额度 / 用量映射字段")
            }
        }
        return items
    }

    private var saveDisabledReason: String? {
        if model.isDemo { return "演示模式不保存账户；请在真实模式中保存并开始监控。" }
        if let error = alertConfigError() { return error }
        if let editingAccount {
            let keyChanged = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let configurationChanged = provider == .genericHTTP
                && genericConfig != editingAccount.genericConfig
            if (keyChanged || configurationChanged), testResult?.category != .success {
                return "修改 API Key 或通用 HTTP 配置后，请先重新测试连接成功。"
            }
            return nil
        }
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写 API Key / Management Key（必填）。"
        }
        if testResult?.category != .success {
            return "请先测试连接，成功后才能保存并开始监控。"
        }
        if provider == .genericHTTP {
            if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "请填写 Base URL（必填）。"
            }
            if !(mapping.hasBalanceMapping || mapping.hasCreditsMapping || mapping.hasUsageMapping) {
                return "请至少填写一个余额 / 额度 / 用量映射字段。"
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
        ("告知线", warning, warningValue, warningCurrency),
        ("警戒线", critical, criticalValue, criticalCurrency)
    ]
    for (title, rule, valueText, currencyText) in entries {
        if rule.mode == .custom {
            guard let value = parseAlertDecimal(valueText), value >= 0 else {
                return "\(title)必须是大于等于 0 的数字；币种请填在单独的币种框，不要填入 “100 USD” 这类组合文本。"
            }
            if rule.metric == .balanceAbsolute,
               currencyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(title)的余额币种不能为空。"
            }
        }
        if rule.mode == .followPublic, !rule.metric.usesPercent {
            return "\(title)的绝对指标不能跟随公共，请选择自定义。"
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
            Picker("模式", selection: $rule.mode) {
                ForEach(AlertLineMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .frame(width: 140)
            if rule.mode != .off {
                Picker("指标", selection: $rule.metric) {
                    ForEach(AlertMetricKind.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .frame(width: 160)
                if rule.mode == .custom {
                    HStack(spacing: 6) {
                        TextField("纯数字，如 80", text: $valueText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                        if rule.metric == .balanceAbsolute {
                            if currencyOptions.isEmpty {
                                TextField("币种，如 USD", text: $currency)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 110)
                            } else {
                                Picker("币种", selection: $currency) {
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
                    Text("阈值只填数字；币种请使用独立币种框，不要输入 “100 USD”。")
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
        case .off: return "关闭：不评估该线"
        case .followPublic:
            return rule.metric.usesPercent ? "使用公共百分比阈值" : "绝对指标不能跟随公共，请选择自定义"
        case .custom:
            return "使用自定义阈值"
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
                Text("告警线 · \(account.displayName)").font(.title3.weight(.semibold))
                Spacer()
                if model.isDemo { DemoTag() }
            }
            .padding(20)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                AlertLineRuleEditor(
                    title: "告知线",
                    rule: $warning,
                    valueText: $warningValue,
                    currency: $warningCurrency,
                    currencyOptions: currencyOptions
                )
                AlertLineRuleEditor(
                    title: "警戒线",
                    rule: $critical,
                    valueText: $criticalValue,
                    currency: $criticalCurrency,
                    currencyOptions: currencyOptions
                )
                Text("公共阈值：告知 \(Money.percent(model.settings.publicAlertConfig.warningPercent)) / 警戒 \(Money.percent(model.settings.publicAlertConfig.criticalPercent))。绝对指标只能自定义。")
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
                Button("取消") { dismiss() }
                Spacer()
                if model.isDemo {
                    Text("演示模式不可保存告警线。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if validationMessage != nil {
                    Text("请先修正上方校验错误。")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("保存") { save() }
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
            parts.append("预算 \(budget.amount) \(budget.currency)")
        }
        if let threshold = account.balanceThreshold {
            parts.append("余额低水位 \(threshold.amount) \(threshold.currency)")
        }
        guard !parts.isEmpty else { return nil }
        return "旧固定阈值：" + parts.joined(separator: "；")
            + "。保存新告警线后旧预算 / 余额阈值不再单独触发；每条线只能选一个指标，请确认当前预填规则已覆盖你最关心的旧阈值。"
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
