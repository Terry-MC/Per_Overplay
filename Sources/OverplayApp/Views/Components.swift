import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OverplayCore

struct DemoTag: View {
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flask.fill")
            Text(L10n.t("component.1e5e74525b"))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.orange)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.orange.opacity(0.14)))
        .accessibilityLabel(L10n.t("component.927484dbe6"))
    }
}

struct DemoBanner: View {
    @Environment(\.locale) private var locale

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
    var emptyText: String = L10n.t("dataStatus.6ffa7e6d35")
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
    case .genericHTTP: return ProviderStyle(abbreviation: "HTTP", color: .gray)
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

enum AccountIconCatalog {
    static let options = [
        "server.rack", "cloud", "creditcard", "chart.bar.xaxis",
        "network", "building.2", "bolt.horizontal.circle"
    ]

    static func normalized(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              options.contains(name) else { return nil }
        return name
    }
}

enum BrandIconCatalog {
    private static let fileNames: [ProviderKind: String] = [
        .deepseek: "brand-deepseek",
        .openrouter: "brand-openrouter",
        .kimi: "brand-kimi",
        .glm: "brand-glm",
        .minimax: "brand-minimax",
        .qwen: "brand-qwen",
        .seed: "brand-seed",
        .hunyuan: "brand-hunyuan",
        .openai: "brand-openai",
        .anthropic: "brand-anthropic",
        .gemini: "brand-gemini",
        .meta: "brand-meta",
        .xai: "brand-xai",
        .mistral: "brand-mistral"
    ]

    private static let images: [ProviderKind: NSImage] = {
        var result: [ProviderKind: NSImage] = [:]
        for (provider, name) in fileNames {
            guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
                  let image = NSImage(contentsOf: url) else { continue }
            result[provider] = image
        }
        return result
    }()

    static func image(for provider: ProviderKind) -> NSImage? {
        images[provider]
    }
}

struct ProviderMark: View {
    var provider: ProviderKind
    var iconName: String?

    init(provider: ProviderKind, iconName: String? = nil) {
        self.provider = provider
        self.iconName = iconName
    }

    var body: some View {
        let style = providerStyle(for: provider)
        let customIcon = AccountIconCatalog.normalized(iconName)
        let brandIcon = customIcon == nil ? BrandIconCatalog.image(for: provider) : nil
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(brandIcon == nil ? style.color.opacity(0.16) : Color.white.opacity(0.96))
            .frame(width: 34, height: 34)
            .overlay {
                if let customIcon {
                    Image(systemName: customIcon)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(style.color)
                } else if let brandIcon {
                    Image(nsImage: brandIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 21, height: 21)
                } else {
                    Text(style.abbreviation)
                        .font(style.abbreviation.count > 1 ? .caption.weight(.bold) : .headline.weight(.bold))
                        .foregroundStyle(style.color)
                }
            }
            .overlay {
                if brandIcon != nil {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.black.opacity(0.10), lineWidth: 1)
                }
            }
            .accessibilityLabel(provider.displayName)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestRow: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                widestRow = max(widestRow, rowWidth)
                totalHeight += rowHeight + lineSpacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        widestRow = max(widestRow, rowWidth)
        totalHeight += rowHeight
        let width = maxWidth.isFinite ? min(widestRow, maxWidth) : widestRow
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct HealthBadge: View {
    @Environment(\.locale) private var locale
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
        .accessibilityLabel(L10n.f("component.9b4e99d7ac", health.label))
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
                    Text(L10n.t(toast.title))
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
                    .help(toast.isAlert ? L10n.t("component.23cf98c788") : L10n.t("component.c620893e29"))
                }
                Text(L10n.t(toast.message))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if toast.isAlert {
                        Button(L10n.t("component.8774d48dc1")) {
                            model.dismissToast(toast.id)
                            model.showMessageCenter = true
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    Spacer()
                    if toast.autoDismiss {
                        Text(toast.isAlert ? L10n.f("component.859b0f08aa", remaining) : L10n.f("component.aeca3d65dc", remaining))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(toast.isAlert ? L10n.t("component.d86f575901") : L10n.t("component.981e2f1ede"))
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
    @Environment(\.locale) private var locale
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("dataStatus.ff09dc6102"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(L10n.t(message))
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
    @Environment(\.locale) private var locale
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(L10n.t(message))
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
    static func costLines(_ costs: [String: Decimal], emptyText: String = L10n.t("providerDetail.567cdafa2a")) -> [(String, String?)] {
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
        panel.title = isDemo ? L10n.t("component.404d799301") : L10n.t("component.4d045824c0")
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
        _ = model
        NSApp.terminate(nil)
    }

    static func confirmDiscardUnsaved(model: AppModel, action: String) -> Bool {
        guard model.hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.f("component.1b4f849b89", action)
        alert.informativeText = L10n.t("component.b10c2b2f24")
        alert.addButton(withTitle: L10n.t("component.1cead06d6b"))
        alert.addButton(withTitle: L10n.t("component.11d0241540"))
        if alert.runModal() == .alertFirstButtonReturn {
            model.hasUnsavedChanges = false
            model.providerFormResetToken = UUID()
            return true
        }
        return false
    }

    static func errorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.t("component.27e4fe4c3f"))
        alert.runModal()
    }
}

struct MessageCenterEntryCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SectionCard(
            title: L10n.t("messages.6ef1e2d287"),
            subtitle: model.unacknowledgedAlertCount > 0
                ? L10n.f("menuBar.dd296b0bc0", model.unacknowledgedAlertCount)
                : L10n.t("component.1f1833e81c"),
            isDemo: model.isDemo
        ) {
            HStack(spacing: 10) {
                Image(
                    systemName: model.unacknowledgedAlertCount > 0
                        ? "bell.badge.fill"
                        : "bell"
                )
                .foregroundStyle(model.unacknowledgedAlertCount > 0 ? Color.orange : Color.secondary)
                Text(L10n.t("component.d3a317766b"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.t("dashboard.4d7ebd8d8f")) {
                    model.showMessageCenter = true
                }
            }
        }
    }
}

struct AlertRowView: View {
    @Environment(\.locale) private var locale
    var alert: AlertEvent
    var isDemo: Bool
    var onAcknowledge: () -> Void

    private var color: Color {
        switch alert.kind {
        case .budgetExceeded, .credentialInvalid, .syncFailed, .lineCritical:
            return .red
        case .budgetWarning, .balanceLow, .lineWarning:
            return .orange
        case .dataStale:
            return .yellow
        }
    }

    private var symbol: String {
        switch alert.kind {
        case .budgetWarning, .lineWarning: return "chart.pie.fill"
        case .budgetExceeded, .lineCritical: return "exclamationmark.octagon.fill"
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
                    Text(alert.renderedTitle).font(.subheadline.weight(.semibold))
                    if isDemo || alert.isDemo { DemoTag() }
                    if alert.acknowledged {
                        Text(L10n.t("core.messages.d9fea67ad2")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(alert.accountName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.f("component.2e2635addf", alert.renderedValue, alert.renderedThreshold, AlertMetricText.localized(alert.metric)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(UIFormat.compactDate(alert.firedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if !alert.acknowledged {
                Button(L10n.t("component.b56d9ac6c5"), action: onAcknowledge)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }
}

struct BudgetProgressBar: View {
    @Environment(\.locale) private var locale
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
        .accessibilityLabel(L10n.t("quota.8ca02f90d1"))
        .accessibilityValue(ratio.map { Money.percent($0) } ?? L10n.t("dataStatus.beff4a1cd1"))
    }
}
