import SwiftUI
import OverplayCore

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var onAddAccount: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.22), Color.purple.opacity(0.22)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 86, height: 86)
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.tint)
                    }
                    Text("Overplay")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(L10n.t("onboarding.697a94c8f0"))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(alignment: .top, spacing: 16) {
                    feature(
                        symbol: "lock.shield",
                        title: L10n.t("onboarding.d760777ab8"),
                        text: L10n.t("onboarding.fd68e8ceac")
                    )
                    feature(
                        symbol: "externaldrive",
                        title: L10n.t("onboarding.6cfa4f14e7"),
                        text: L10n.t("onboarding.57c63148e4")
                    )
                    feature(
                        symbol: "gauge.with.dots.needle.50percent",
                        title: L10n.t("onboarding.c9c671069a"),
                        text: L10n.t("onboarding.bc023c8242")
                    )
                }
                .frame(maxWidth: 980)

                SectionCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(L10n.t("onboarding.1990a19d6b"), systemImage: "info.circle")
                            .font(.headline)
                        capabilityRow(
                            "DeepSeek",
                            L10n.t("onboarding.ff702c64b7"),
                            L10n.t("onboarding.fa35fc2544")
                        )
                        Divider()
                        capabilityRow(
                            "OpenRouter",
                            L10n.t("onboarding.76b7839d3e"),
                            L10n.t("onboarding.aabb35eda2")
                        )
                        Divider()
                        Text(L10n.t("onboarding.0c0b9fc645"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 700)

                VStack(spacing: 10) {
                    Button(action: onAddAccount) {
                        Label(L10n.t("onboarding.b1d3898482"), systemImage: "plus.circle.fill")
                            .frame(minWidth: 260)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        model.requestEnterDemoMode()
                    } label: {
                        Label(L10n.t("app.fb7f73f291"), systemImage: "flask")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Text(L10n.t("onboarding.b9ff3e7884"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                Text(L10n.t("onboarding.941a2c1544"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
    }

    private func feature(symbol: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(title).font(.headline)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func capabilityRow(_ title: String, _ summary: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Text(summary).font(.subheadline)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}
