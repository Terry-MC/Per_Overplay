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
                    Text("统一查看 DeepSeek 与 OpenRouter 的官方余额、额度和近 30 天用量")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(alignment: .top, spacing: 16) {
                    feature(
                        symbol: "lock.shield",
                        title: "密钥只进 Keychain",
                        text: "API Key 不写入数据库、日志、导出文件或仓库；界面不回显明文。"
                    )
                    feature(
                        symbol: "externaldrive",
                        title: "数据只存本机",
                        text: "账户、用量、快照与告警保存在本地 SQLite，无云端、无遥测。"
                    )
                    feature(
                        symbol: "gauge.with.dots.needle.50percent",
                        title: "预算与告警",
                        text: "OpenRouter 月度预算 80% / 100%、DeepSeek 余额低水位与同步异常。"
                    )
                }
                .frame(maxWidth: 980)

                SectionCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("能力说明", systemImage: "info.circle")
                            .font(.headline)
                        capabilityRow(
                            "DeepSeek",
                            "普通 API Key · 余额（CNY / USD）与快照曲线",
                            "官方不提供历史 token / 费用接口，界面会明确显示“厂商未提供”。"
                        )
                        Divider()
                        capabilityRow(
                            "OpenRouter",
                            "Management Key · credits、额度、最近约 30 天 activity",
                            "普通 API Key 无法读取 credits / activity；用量日期按厂商 UTC 日桶。"
                        )
                        Divider()
                        Text("本应用不会调用推理接口，也不代理任何 LLM 请求。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 700)

                VStack(spacing: 10) {
                    Button(action: onAddAccount) {
                        Label("添加 DeepSeek / OpenRouter 账户", systemImage: "plus.circle.fill")
                            .frame(minWidth: 260)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        model.requestEnterDemoMode()
                    } label: {
                        Label("进入演示模式", systemImage: "flask")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Text("演示模式仅使用本地模拟数据，不发起网络请求、不读写 Keychain。进入前需确认免责声明。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                Text("数据仅保存在本地。删除账户会一并删除 Keychain 凭证；历史数据是否保留由你选择（默认保留）。")
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
