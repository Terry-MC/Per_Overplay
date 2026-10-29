import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OverplayCore

struct DemoTag: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flask.fill")
            Text("演示数据")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.orange)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.orange.opacity(0.14)))
        .accessibilityLabel("演示数据，仅用于功能展示，不代表真实账单")
    }
}

struct DemoBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flask.fill")
            Text(DemoMode.shortBadge)
                .font(.callout.weight(.medium))
            Spacer()
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.orange.opacity(0.25)).frame(height: 1)
        }
    }
}

struct SectionCard<Content: View>: View {
    var title: String?
    var subtitle: String?
    var isDemo: Bool = false
    @ViewBuilder var content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        isDemo: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isDemo = isDemo
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || subtitle != nil || isDemo {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let title {
                        Text(title).font(.headline)
                    }
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isDemo { DemoTag() }
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct MetricCard: View {
    var title: String
    var valueLines: [(String, String?)]
    var footnote: String?
    var symbol: String
    var isDemo: Bool
    var emptyText: String = "无数据"
    var status: DataStatus = .actual
    var accessory: AnyView?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isDemo { DemoTag() }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !status.isActual || valueLines.isEmpty {
                    DataValueLabel(
                        text: status.isActual ? emptyText : status.emptyLabel,
                        status: status,
                        font: .system(size: 21, weight: .semibold, design: .rounded)
                    )
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(valueLines.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(line.0)
                                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                    if let note = line.1 {
                                        Text(note).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        if let iconName = status.iconName {
                            Image(systemName: iconName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(status.tint)
                                .help(status.reason ?? "")
                        }
                    }
                }
                Spacer(minLength: 0)
                if let accessory { accessory }
            }
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minHeight: 128, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct ProviderStyle {
    var abbreviation: String
    var color: Color
}

func providerStyle(for provider: ProviderKind) -> ProviderStyle {
    switch provider {
    case .deepseek: return ProviderStyle(abbreviation: "D", color: .blue)
    case .openrouter: return ProviderStyle(abbreviation: "O", color: .purple)
    case .kimi: return ProviderStyle(abbreviation: "K", color: .teal)
    case .glm: return ProviderStyle(abbreviation: "G", color: .cyan)
    case .minimax: return ProviderStyle(abbreviation: "MM", color: .orange)
    case .qwen: return ProviderStyle(abbreviation: "Q", color: .indigo)
    case .seed: return ProviderStyle(abbreviation: "S", color: .green)
    case .hunyuan: return ProviderStyle(abbreviation: "H", color: .teal)
    case .openai: return ProviderStyle(abbreviation: "AI", color: .mint)
    case .anthropic: return ProviderStyle(abbreviation: "C", color: .orange)
    case .gemini: return ProviderStyle(abbreviation: "GM", color: .blue)
    case .meta: return ProviderStyle(abbreviation: "L", color: .blue)
    case .xai: return ProviderStyle(abbreviation: "X", color: .gray)
    case .mistral: return ProviderStyle(abbreviation: "MI", color: .red)
    }
}

struct ProviderMark: View {
    var provider: ProviderKind

    var body: some View {
        let style = providerStyle(for: provider)
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(style.color.opacity(0.16))
            .frame(width: 34, height: 34)
            .overlay(
                Text(style.abbreviation)
                    .font(style.abbreviation.count > 1 ? .caption.weight(.bold) : .headline.weight(.bold))
                    .foregroundStyle(style.color)
            )
            .accessibilityLabel(provider.displayName)
    }
}

struct HealthBadge: View {
    var health: AccountHealth

    private var color: Color {
        switch health {
        case .healthy: return .green
        case .partial, .stale, .accountAbnormal: return .orange
        case .failed, .invalidCredential: return .red
        case .syncing: return .blue
        case .connectedNoData: return .secondary
        case .disabled, .neverSynced: return .secondary
        }
    }

    private var symbol: String {
        switch health {
        case .healthy: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        case .stale: return "clock.badge.exclamationmark"
        case .failed: return "xmark.octagon.fill"
        case .invalidCredential: return "key.slash.fill"
        case .accountAbnormal: return "exclamationmark.triangle.fill"
        case .connectedNoData: return "tray"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .disabled: return "pause.circle"
        case .neverSynced: return "questionmark.circle"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(health.label)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.12)))
        .accessibilityLabel("状态：\(health.label)")
    }
}

struct EmptyStateView<Actions: View>: View {
    var symbol: String
    var title: String
    var message: String
    @ViewBuilder var actions: Actions

    init(
        symbol: String,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            actions.padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

struct ToastStackView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(model.toasts) { toast in
                ToastCardView(model: model, toast: toast)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: 380, alignment: .trailing)
        .animation(.easeInOut(duration: 0.2), value: model.toasts)
    }
}

struct ToastCardView: View {
    @ObservedObject var model: AppModel
    var toast: ToastMessage

    private var color: Color {
        switch toast.style {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var icon: String {
        switch toast.style {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = remainingSeconds(at: context.date)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Text(toast.title)
                        .font(.subheadline.weight(.semibold))
                    if toast.isDemo { DemoTag() }
                    Spacer()
                    if toast.autoDismiss {
                        Text("\(remaining)s")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        model.dismissToast(toast.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(toast.isAlert ? "关闭提示；消息仍保留在消息中心" : "关闭提示")
                }
                Text(toast.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if toast.isAlert {
                        Button("查看消息") {
                            model.dismissToast(toast.id)
                            model.showMessageCenter = true
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    Spacer()
                    if toast.autoDismiss {
                        Text(toast.isAlert ? "\(remaining)s 后归档到消息" : "\(remaining)s 后关闭")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(toast.isAlert ? "需手动关闭；消息仍保留在消息中心" : "需手动关闭")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.14), radius: 10, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(color.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private func remainingSeconds(at date: Date) -> Int {
        guard let expiresAt = toast.expiresAt else {
            return Int(toast.duration.rounded())
        }
        return max(0, Int(ceil(expiresAt.timeIntervalSince(date))))
    }
}

struct AnomalyNotice: View {
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("数据异常")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct InlineErrorView: View {
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

enum UIFormat {
    static func costLines(_ costs: [String: Decimal], emptyText: String = "厂商未提供") -> [(String, String?)] {
        if costs.isEmpty { return [(emptyText, nil)] }
        return costs.keys.sorted().map { currency in
            (Money.formatCost(costs[currency] ?? 0, currency: currency), nil)
        }
    }

    static func compactDate(_ date: Date) -> String {
        DateFormatters.mediumDateTime.string(from: date)
    }
}

@MainActor
enum AppPanels {
    static func saveCSV(
        filename: String,
        data: Data,
        isDemo: Bool = false,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.title = isDemo ? "导出用量 CSV · 演示数据" : "导出用量 CSV"
        if isDemo {
            panel.message = DemoMode.shortBadge
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }

    static func confirmQuit(model: AppModel) {
        guard model.hasUnsavedChanges else {
            NSApp.terminate(nil)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "有未保存的内容，仍要退出 Overplay？"
        alert.informativeText = "退出将停止定时刷新、取消进行中的请求并关闭窗口。已保存的数据不会丢失；未保存的表单或设置将不会被保留。"
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    static func errorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

struct MessageCenterEntryCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SectionCard(
            title: "消息中心",
            subtitle: model.unacknowledgedAlertCount > 0
                ? "\(model.unacknowledgedAlertCount) 条未确认"
                : "无未确认消息",
            isDemo: model.isDemo
        ) {
            HStack(spacing: 10) {
                Image(
                    systemName: model.unacknowledgedAlertCount > 0
                        ? "bell.badge.fill"
                        : "bell"
                )
                .foregroundStyle(model.unacknowledgedAlertCount > 0 ? Color.orange : Color.secondary)
                Text("顶部提示倒计时结束后归档到消息中心；关闭提示不会删除消息。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("打开消息中心") {
                    model.showMessageCenter = true
                }
            }
        }
    }
}

struct AlertRowView: View {
    var alert: AlertEvent
    var isDemo: Bool
    var onAcknowledge: () -> Void

    private var color: Color {
        switch alert.kind {
        case .budgetExceeded, .credentialInvalid, .syncFailed:
            return .red
        case .budgetWarning, .balanceLow:
            return .orange
        case .dataStale:
            return .yellow
        }
    }

    private var symbol: String {
        switch alert.kind {
        case .budgetWarning: return "chart.pie.fill"
        case .budgetExceeded: return "exclamationmark.octagon.fill"
        case .balanceLow: return "creditcard.trianglebadge.exclamationmark"
        case .syncFailed: return "arrow.triangle.2.circlepath.circle.fill"
        case .credentialInvalid: return "key.slash.fill"
        case .dataStale: return "clock.badge.exclamationmark"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(alert.kind.title).font(.subheadline.weight(.semibold))
                    if isDemo || alert.isDemo { DemoTag() }
                    if alert.acknowledged {
                        Text("已确认").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(alert.accountName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("当前 \(alert.value) · 阈值 \(alert.threshold) · \(alert.metric)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(UIFormat.compactDate(alert.firedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if !alert.acknowledged {
                Button("确认", action: onAcknowledge)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }
}

struct BudgetProgressBar: View {
    var ratio: Decimal?
    var isDemo: Bool

    private var fraction: Double {
        guard let ratio else { return 0 }
        return min(max(NSDecimalNumber(decimal: ratio).doubleValue / 100.0, 0), 1)
    }

    private var color: Color {
        guard let ratio else { return .secondary }
        if ratio >= 100 { return .red }
        if ratio >= 80 { return .orange }
        return .green
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.16))
                Capsule()
                    .fill(color)
                    .frame(width: max(geometry.size.width * fraction, ratio == nil ? 0 : 2))
                ForEach([80.0, 100.0], id: \.self) { marker in
                    Rectangle()
                        .fill(Color.primary.opacity(0.28))
                        .frame(width: 1.5, height: 12)
                        .offset(x: min(geometry.size.width - 1.5, geometry.size.width * marker / 100.0))
                }
            }
        }
        .frame(height: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("使用率")
        .accessibilityValue(ratio.map { Money.percent($0) } ?? "不可用")
    }
}
