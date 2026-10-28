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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isDemo { DemoTag() }
            }
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
                if valueLines.isEmpty {
                    Text(emptyText)
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
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

struct ProviderMark: View {
    var provider: ProviderKind

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(provider == .deepseek ? Color.blue.opacity(0.16) : Color.purple.opacity(0.16))
            .frame(width: 34, height: 34)
            .overlay(
                Text(provider == .deepseek ? "D" : "O")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(provider == .deepseek ? Color.blue : Color.purple)
            )
            .accessibilityLabel(provider.displayName)
    }
}

struct HealthBadge: View {
    var health: AccountHealth

    private var color: Color {
        switch health {
        case .healthy: return .green
        case .partial, .stale: return .orange
        case .failed, .invalidCredential: return .red
        case .syncing: return .blue
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

struct BannerView: View {
    var banner: Banner
    var onDismiss: () -> Void

    private var color: Color {
        switch banner.style {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var symbol: String {
        switch banner.style {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(banner.message)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(color.opacity(0.1))
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
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "退出 Overplay？"
        alert.informativeText = "将停止定时刷新、取消进行中的请求并退出应用。已保存的数据不会丢失。"
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            model.prepareForTermination()
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
