import Foundation

public enum AlertLineMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case followPublic
    case custom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off: return "关闭"
        case .followPublic: return "跟随公共"
        case .custom: return "自定义"
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
        case .warning: return "告知线触发"
        case .critical: return "警戒线触发"
        }
    }
}

public struct ResolvedAlertRule: Equatable, Sendable {
    public var severity: AlertSeverity
    public var metric: AlertMetricKind
    public var threshold: Decimal
    public var currency: String?
    public var source: String

    public init(
        severity: AlertSeverity,
        metric: AlertMetricKind,
        threshold: Decimal,
        currency: String?,
        source: String
    ) {
        self.severity = severity
        self.metric = metric
        self.threshold = threshold
        self.currency = currency
        self.source = source
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
                source: "公共\(severity == .warning ? "告知" : "警戒")线"
            )
        case .custom:
            guard let value = line.value else { return nil }
            return ResolvedAlertRule(
                severity: severity,
                metric: line.metric,
                threshold: value,
                currency: line.currency,
                source: "自定义"
            )
        }
    }
}
