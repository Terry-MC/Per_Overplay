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
            lastConnectionSignature = connectionSignature
        }
        .onChange(of: formSignature) { _, newValue in
            guard newValue != lastSignature else { return }
            lastSignature = newValue
            model.hasUnsavedChanges = true
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
                    labeledField("告知线 %", text: $warningPercent, width: 130)
                    labeledField("警戒线 %", text: $criticalPercent, width: 130)
                    Spacer()
                    Button("保存公共阈值") { savePublicConfig() }
                        .disabled(model.isDemo)
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
                    labeledField("显示名称", text: $displayName, width: 220)
                    labeledField("官方名称（可选）", text: $officialName, width: 200)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("图标").font(.caption).foregroundStyle(.secondary)
                        Picker("图标", selection: $iconName) {
                            Text("默认图标").tag("")
                            ForEach(iconOptions, id: \.self) { name in
                                Label(name, systemImage: name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                    Spacer()
                }

                HStack(spacing: 12) {
                    SecureField("API Key / Management Key（仅写入 Keychain）", text: $apiKey)
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
                    .disabled(!canSave || isSaving || model.isDemo)
                }
            }
        }
    }

    private var genericHTTPFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("通用 HTTP（单一 HTTPS 只读 GET 端点）").font(.headline)
            HStack(spacing: 12) {
                labeledField("Base URL", text: $baseURL, width: 300)
                labeledField("端点路径", text: $endpointPath, width: 160)
                Picker("认证", selection: $authMode) {
                    ForEach(GenericAuthMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .frame(width: 190)
                if authMode == .header {
                    labeledField("Header 名称", text: $headerName, width: 150)
                }
            }
            DisclosureGroup("JSON 字段映射（点号路径）") {
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
            }
            .font(.callout)
        }
    }

    private var alertLineFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("新账户告警线（默认关闭）").font(.headline)
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

    private func labeledField(_ title: String, text: Binding<String>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
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

    private var canSave: Bool {
        if let editingAccount {
            let keyChanged = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let configurationChanged = provider == .genericHTTP
                && genericConfig != editingAccount.genericConfig
            if keyChanged || configurationChanged {
                return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && testResult?.category == .success
            }
            return true
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              testResult?.category == .success else { return false }
        if provider == .genericHTTP {
            return !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (mapping.hasBalanceMapping || mapping.hasCreditsMapping || mapping.hasUsageMapping)
        }
        return true
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
        Decimal(string: text.trimmingCharacters(in: .whitespacesAndNewlines), locale: Locale(identifier: "en_US_POSIX"))
    }

    private func savePublicConfig() {
        guard let warning = parseDecimal(warningPercent),
              let critical = parseDecimal(criticalPercent),
              warning >= 0, critical >= 0 else {
            formError = "公共阈值必须是大于等于 0 的数字"
            return
        }
        guard warning <= critical else {
            formError = "公共告知线不能高于警戒线"
            return
        }
        model.savePublicAlertConfig(PublicAlertConfig(
            warningPercent: warning,
            criticalPercent: critical
        ))
    }

    private func alertConfigError() -> String? {
        let pairs: [(String, AlertLineRule, String)] = [
            ("告知线", warningRule, warningValue),
            ("警戒线", criticalRule, criticalValue)
        ]
        for (title, rule, valueText) in pairs {
            if rule.mode == .custom {
                guard let value = parseDecimal(valueText), value >= 0 else {
                    return "\(title)必须是大于等于 0 的数字"
                }
            }
            if rule.mode == .followPublic, !rule.metric.usesPercent {
                return "\(title)的绝对指标不能跟随公共，请选择自定义"
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
        lastConnectionSignature = connectionSignature
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
            criticalCurrency,
            warningPercent, criticalPercent
        ].joined(separator: "|")
    }
}

struct AlertLineRuleEditor: View {
    var title: String
    @Binding var rule: AlertLineRule
    @Binding var valueText: String
    @Binding var currency: String

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
                        TextField("阈值", text: $valueText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                        if rule.metric == .balanceAbsolute {
                            TextField("币种", text: $currency)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }
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
    @State private var errorMessage: String?

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
                AlertLineRuleEditor(title: "告知线", rule: $warning, valueText: $warningValue, currency: $warningCurrency)
                AlertLineRuleEditor(title: "警戒线", rule: $critical, valueText: $criticalValue, currency: $criticalCurrency)
                Text("公共阈值：告知 \(Money.percent(model.settings.publicAlertConfig.warningPercent)) / 警戒 \(Money.percent(model.settings.publicAlertConfig.criticalPercent))。绝对指标只能自定义。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if account.alertConfig == nil, account.budget != nil || account.balanceThreshold != nil {
                    Text("该账户存在 issue-001 的旧固定阈值。保存新告警线后，旧预算 / 余额阈值不再单独触发；请确认映射后的规则。")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if let errorMessage { InlineErrorView(message: errorMessage) }
            }
            .padding(20)
            Divider()
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isDemo)
            }
            .padding(16)
        }
        .frame(width: 620)
    }

    private func save() {
        for (title, rule, valueText, currencyText) in [
            ("告知线", warning, warningValue, warningCurrency),
            ("警戒线", critical, criticalValue, criticalCurrency)
        ] {
            if rule.mode == .custom {
                guard let value = valueText.decimalValue, value >= 0 else {
                    errorMessage = "\(title)必须是大于等于 0 的数字"
                    return
                }
                if rule.metric == .balanceAbsolute,
                   currencyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errorMessage = "\(title)的余额币种不能为空"
                    return
                }
            }
            if rule.mode == .followPublic, !rule.metric.usesPercent {
                errorMessage = "\(title)的绝对指标不能跟随公共，请选择自定义"
                return
            }
        }
        var warningRule = warning
        warningRule.value = warningValue.decimalValue
        warningRule.currency = warning.metric == .balanceAbsolute ? warningCurrency : nil
        var criticalRule = critical
        criticalRule.value = criticalValue.decimalValue
        criticalRule.currency = critical.metric == .balanceAbsolute ? criticalCurrency : nil
        model.saveAccountAlertConfig(account, config: AccountAlertConfig(
            warning: warningRule,
            critical: criticalRule
        ))
        dismiss()
    }
}

private extension String {
    var decimalValue: Decimal? {
        Decimal(string: trimmingCharacters(in: .whitespacesAndNewlines), locale: Locale(identifier: "en_US_POSIX"))
    }
}
