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
                Text(isEditing ? L10n.t("accountEditor.608f93e8ea") : L10n.t("dashboard.c771c7d8e2"))
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
                            Text(L10n.t("core.csv.0c131e3964")).font(.headline)
                            Picker(L10n.t("core.csv.0c131e3964"), selection: $provider) {
                                ForEach(ProviderKind.realAccountProviders) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    } else if let editingAccount {
                        Label(L10n.f("accountEditor.c54feccf51", editingAccount.provider.displayName, editingAccount.displayName), systemImage: "person.crop.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("accountEditor.75ae6a8a7d")).font(.headline)
                        TextField(L10n.t("accountEditor.1ebeee1f0f"), text: $name)
                            .textFieldStyle(.roundedBorder)
                        Text(L10n.t("accountEditor.1fb78166cb"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.t("addProvider.b0fb41120b")).font(.headline)
                            TextField(L10n.t("accountEditor.eb6ff786e8"), text: $officialName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 300)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.t("addProvider.1f24c1e5aa")).font(.headline)
                            Picker(L10n.t("addProvider.1f24c1e5aa"), selection: $iconName) {
                                Text(L10n.t("addProvider.74812bf1e2")).tag("")
                                ForEach(AccountIconCatalog.options, id: \.self) { icon in
                                    Label(icon, systemImage: icon).tag(icon)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(isEditing ? L10n.t("accountEditor.ef85b26aa9") : "API Key")
                            .font(.headline)
                        SecureField(
                            isEditing ? L10n.t("accountEditor.74da57609f") : L10n.t("accountEditor.84b09ee560"),
                            text: $apiKey
                        )
                        .textFieldStyle(.roundedBorder)
                        Text(L10n.t("accountEditor.fe076ab14f"))
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
                                Text(L10n.t("accountEditor.49562bf14c"))
                            } else {
                                Label(L10n.t("addProvider.10b7d8eccc"), systemImage: "bolt.horizontal.circle")
                            }
                        }
                        .disabled(isTesting || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text(L10n.t("accountEditor.b66494f6c6"))
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
                Button(L10n.t("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    }
                    Text(isEditing ? L10n.t("common.save") : L10n.t("accountEditor.d04dabaa4f"))
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
                    Text(L10n.t("accountEditor.d54d8d21cf"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Link(
                        L10n.t("accountEditor.c55bee1059"),
                        destination: URL(string: "https://api-docs.deepseek.com/zh-cn/api/get-user-balance/")!
                    )
                    .font(.caption)
                case .openrouter:
                    Label("OpenRouter", systemImage: "info.circle")
                        .font(.headline)
                    Text(L10n.t("accountEditor.aaa26fa3df"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(L10n.t("accountEditor.47978e9688"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Link(
                        L10n.t("accountEditor.2dac9d2cc3"),
                        destination: URL(string: "https://openrouter.ai/docs/api-reference/credits/get-credits")!
                    )
                    .font(.caption)
                default:
                    Label(L10n.t("accountEditor.357a15eebb"), systemImage: "info.circle")
                        .font(.headline)
                    Text(L10n.t("accountEditor.34fb350973"))
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
                Text(L10n.t(result.message))
                    .font(.callout)
                    .textSelection(.enabled)
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
