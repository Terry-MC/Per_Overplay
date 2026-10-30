import Foundation

public enum AlertLineMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case followPublic
    case custom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off: return L10n.t("common.close")
        case .followPublic: return L10n.t("core.alertLine.c2bd3a4dfd")
        case .custom: return L10n.t("core.analysisRange.c493338e8c")
        }
    }
}

public enum AlertMetricKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case budgetPercent
    case quotaPercent
    case balanceAbsolute
    case tokenAbsolute

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .budgetPercent: return L10n.t("core.alertLine.c5cc604760")
        case .quotaPercent: return L10n.t("core.alertLine.4764ef595f")
        case .balanceAbsolute: return L10n.t("core.alertLine.2c2ac8be9c")
        case .tokenAbsolute: return L10n.t("core.alertLine.1a9c67fd3c")
        }
    }

    public var canonicalLabel: String {
        switch self {
        case .budgetPercent: return "预算 %"
        case .quotaPercent: return "配额 %"
        case .balanceAbsolute: return "余额绝对值"
        case .tokenAbsolute: return "Token 绝对值"
        }
    }

    public var usesPercent: Bool {
        self == .budgetPercent || self == .quotaPercent
    }

    public var isLowerBound: Bool {
        self == .balanceAbsolute
    }

    public var unit: String {
        switch self {
        case .budgetPercent, .quotaPercent: return "%"
        case .balanceAbsolute, .tokenAbsolute: return ""
        }
    }
}

public struct AlertLineRule: Codable, Equatable, Sendable {
    public var mode: AlertLineMode
    public var metric: AlertMetricKind
    public var value: Decimal?
    public var currency: String?

    public init(
        mode: AlertLineMode = .off,
        metric: AlertMetricKind = .budgetPercent,
        value: Decimal? = nil,
        currency: String? = nil
    ) {
        self.mode = mode
        self.metric = metric
        self.value = value
        self.currency = currency
    }

    public static let off = AlertLineRule()
}

public struct AccountAlertConfig: Codable, Equatable, Sendable {
    public var warning: AlertLineRule
    public var critical: AlertLineRule

    public init(
        warning: AlertLineRule = .off,
        critical: AlertLineRule = .off
    ) {
        self.warning = warning
        self.critical = critical
    }

    public static let off = AccountAlertConfig()
}

public struct PublicAlertConfig: Codable, Equatable, Sendable {
    public var warningPercent: Decimal
    public var criticalPercent: Decimal

    public init(warningPercent: Decimal = 80, criticalPercent: Decimal = 100) {
        self.warningPercent = warningPercent
        self.criticalPercent = criticalPercent
    }
}

public enum AlertSeverity: String, Codable, Equatable, Sendable {
    case warning
    case critical

    public var title: String {
        switch self {
        case .warning: return L10n.t("alert.lineWarning.title")
        case .critical: return L10n.t("alert.lineCritical.title")
        }
    }
}

public struct ResolvedAlertRule: Equatable, Sendable {
    public var severity: AlertSeverity
    public var metric: AlertMetricKind
    public var threshold: Decimal
    public var currency: String?
    public var source: String
    public var canonicalSource: String

    public init(
        severity: AlertSeverity,
        metric: AlertMetricKind,
        threshold: Decimal,
        currency: String?,
        source: String,
        canonicalSource: String? = nil
    ) {
        self.severity = severity
        self.metric = metric
        self.threshold = threshold
        self.currency = currency
        self.source = source
        self.canonicalSource = canonicalSource ?? source
    }
}

public extension AccountAlertConfig {
    func resolved(public publicConfig: PublicAlertConfig) -> [ResolvedAlertRule] {
        [
            resolve(line: warning, severity: .warning, public: publicConfig),
            resolve(line: critical, severity: .critical, public: publicConfig)
        ].compactMap { $0 }
    }

    private func resolve(
        line: AlertLineRule,
        severity: AlertSeverity,
        public publicConfig: PublicAlertConfig
    ) -> ResolvedAlertRule? {
        switch line.mode {
        case .off:
            return nil
        case .followPublic:
            guard line.metric.usesPercent else { return nil }
            let threshold = severity == .warning
                ? publicConfig.warningPercent
                : publicConfig.criticalPercent
            return ResolvedAlertRule(
                severity: severity,
                metric: line.metric,
                threshold: threshold,
                currency: nil,
                source: L10n.f("core.alertLine.545bd1de4c", severity == .warning ? L10n.t("baseInfo.d55a864f5c") : L10n.t("baseInfo.5cb58536e5")),
                canonicalSource: severity == .warning ? "公共告知线" : "公共警戒线"
            )
        case .custom:
            guard let value = line.value else { return nil }
            return ResolvedAlertRule(
                severity: severity,
                metric: line.metric,
                threshold: value,
                currency: line.currency,
                source: L10n.t("core.analysisRange.c493338e8c"),
                canonicalSource: "自定义"
            )
        }
    }
}
