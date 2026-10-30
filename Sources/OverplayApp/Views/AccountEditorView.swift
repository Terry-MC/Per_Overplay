import SwiftUI
import OverplayCore

enum AccountEditorMode: Identifiable {
    case add
    case edit(Account)

    var id: String {
        switch self {
        case .add: return "add-\(UUID().uuidString)"
        case .edit(let account): return "edit-\(account.id)"
        }
    }
}

struct AccountEditorView: View {
    @ObservedObject var model: AppModel
    let mode: AccountEditorMode
    @Environment(\.dismiss) private var dismiss

    @State private var provider: ProviderKind
    @State private var name: String
    @State private var officialName: String
    @State private var iconName: String
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var testResult: ConnectionTestResult?
    @State private var formError: String?
    @State private var isSaving = false

    init(model: AppModel, mode: AccountEditorMode) {
        self.model = model
        self.mode = mode
        switch mode {
        case .add:
            _provider = State(initialValue: .deepseek)
            _name = State(initialValue: "")
            _officialName = State(initialValue: "")
            _iconName = State(initialValue: "")
        case .edit(let account):
            _provider = State(initialValue: account.provider)
            _name = State(initialValue: account.name)
            _officialName = State(initialValue: account.officialName ?? "")
            _iconName = State(initialValue: account.iconName ?? "")
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingAccount: Account? {
        if case .edit(let account) = mode { return account }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isEditing ? "编辑账户" : "添加账户")
                    .font(.title2.weight(.semibold))
                Spacer()
                if isEditing { DemoTagIfNeeded(isDemo: model.isDemo) }
            }
            .padding(22)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !isEditing {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("厂商").font(.headline)
                            Picker("厂商", selection: $provider) {
                                ForEach(ProviderKind.realAccountProviders) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    } else if let editingAccount {
                        Label("\(editingAccount.provider.displayName) · 账户 \(editingAccount.displayName)", systemImage: "person.crop.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("显示名称").font(.headline)
                        TextField("例如：主账户", text: $name)
                            .textFieldStyle(.roundedBorder)
                        Text("留空时使用厂商名称。多个账户可使用不同名称区分。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("官方名称（可选）").font(.headline)
                            TextField("例如：OpenRouter 生产组织", text: $officialName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 300)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("图标").font(.headline)
                            Picker("图标", selection: $iconName) {
                                Text("默认（厂商图标）").tag("")
                                ForEach(AccountIconCatalog.options, id: \.self) { icon in
                                    Label(icon, systemImage: icon).tag(icon)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(isEditing ? "替换 API Key（可选）" : "API Key")
                            .font(.headline)
                        SecureField(
                            isEditing ? "留空则保留现有 Key" : "粘贴 API Key（不会回显）",
                            text: $apiKey
                        )
                        .textFieldStyle(.roundedBorder)
                        Text("Key 仅写入 macOS Keychain，不进入 SQLite、日志、CSV 或仓库。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    providerGuidance

                    HStack(spacing: 10) {
                        Button {
                            Task { await runTest() }
                        } label: {
                            if isTesting {
                                ProgressView().controlSize(.small)
                                Text("测试中…")
                            } else {
                                Label("测试连接", systemImage: "bolt.horizontal.circle")
                            }
                        }
                        .disabled(isTesting || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("测试不会保存账户，也不会调用推理接口。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let testResult {
                        connectionResultView(testResult)
                    }
                    if let formError {
                        InlineErrorView(message: formError)
                    }
                }
                .padding(22)
            }

            Divider()

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    }
                    Text(isEditing ? "保存" : "添加并测试")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || isSaving)
            }
            .padding(18)
        }
        .frame(width: 620, height: 660)
    }

    private var canSave: Bool {
        if isEditing { return true }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var providerGuidance: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                switch provider {
                case .deepseek:
                    Label("DeepSeek", systemImage: "info.circle")
                        .font(.headline)
                    Text("使用 DeepSeek 普通 API Key。可读取总余额、赠送余额、充值余额与币种；官方不提供历史 token / 费用接口。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Link(
                        "DeepSeek 余额 API 文档",
                        destination: URL(string: "https://api-docs.deepseek.com/zh-cn/api/get-user-balance/")!
                    )
                    .font(.caption)
                case .openrouter:
                    Label("OpenRouter", systemImage: "info.circle")
                        .font(.headline)
                    Text("必须使用 Management Key。普通 API Key 无法读取 credits / activity。用量仅覆盖最近约 30 个 UTC 日，活动金额单位为 USD。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Management Key 具有账户级权限，请仅在可信设备上使用。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Link(
                        "OpenRouter Credits / Activity 文档",
                        destination: URL(string: "https://openrouter.ai/docs/api-reference/credits/get-credits")!
                    )
                    .font(.caption)
                default:
                    Label("演示平台", systemImage: "info.circle")
                        .font(.headline)
                    Text("该平台目前仅用于演示虚拟数据，未接入真实连接器，不能在真实模式添加账户。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func connectionResultView(_ result: ConnectionTestResult) -> some View {
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
            VStack(alignment: .leading, spacing: 4) {
                Text(result.message)
                    .font(.callout)
                    .textSelection(.enabled)
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

    private func runTest() async {
        formError = nil
        testResult = nil
        isTesting = true
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await model.testConnection(provider: provider, apiKey: key)
        testResult = result
        isTesting = false
    }

    private func save() {
        formError = nil
        isSaving = true
        defer { isSaving = false }
        do {
            if let account = editingAccount {
                let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                try model.updateAccount(
                    account,
                    name: name,
                    newAPIKey: key.isEmpty ? nil : key,
                    officialName: officialName,
                    iconName: iconName
                )
            } else {
                _ = try model.saveNewAccount(
                    provider: provider,
                    name: name,
                    apiKey: apiKey,
                    officialName: officialName,
                    iconName: iconName
                )
            }
            dismiss()
        } catch {
            formError = error.localizedDescription
        }
    }
}

private struct DemoTagIfNeeded: View {
    var isDemo: Bool
    var body: some View {
        if isDemo { DemoTag() }
    }
}
