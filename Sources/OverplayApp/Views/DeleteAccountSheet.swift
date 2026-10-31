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
                Text(L10n.t("deleteAccount.9259840611"))
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
                Text(L10n.t("deleteAccount.ffcda38662"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $removeHistory) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("deleteAccount.6633a293b2"))
                        Text(L10n.t("deleteAccount.0a1581eea8"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                if !removeHistory {
                    Text(L10n.t("deleteAccount.6d4ca0bf06"))
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
                Button(L10n.t("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(role: .destructive) {
                    model.deleteAccount(account, removeHistory: removeHistory)
                    dismiss()
                } label: {
                    Text(L10n.t("deleteAccount.9259840611"))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 520)
    }
}
