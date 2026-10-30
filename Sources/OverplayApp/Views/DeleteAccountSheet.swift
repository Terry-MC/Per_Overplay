import SwiftUI
import OverplayCore

struct DeleteAccountSheet: View {
    @ObservedObject var model: AppModel
    let account: Account
    @Environment(\.dismiss) private var dismiss
    @State private var removeHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("删除账户")
                    .font(.title3.weight(.semibold))
            }
            .padding(20)
            Divider()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ProviderMark(provider: account.provider, iconName: account.iconName)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName).font(.headline)
                        Text(account.provider.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("将删除该账户的 Keychain 凭证并停止同步。此操作不可撤销。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $removeHistory) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("同时删除历史数据")
                        Text("默认关闭：保留历史用量与余额快照，但不再展示于默认统计，也不再参与告警。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                if !removeHistory {
                    Text("已保留的历史数据仍保存在本机数据库中，可在后续版本的历史查询或导出中查看。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(20)

            Divider()
            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(role: .destructive) {
                    model.deleteAccount(account, removeHistory: removeHistory)
                    dismiss()
                } label: {
                    Text("删除账户")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 520)
    }
}
