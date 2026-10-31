import Foundation

/// 指标数据状态。只有 `.actual` 允许展示数值（包括真实的 0）；
/// 其它状态一律展示空状态，不允许用 0 / 0? / 0% 占位。
public enum DataStatus: Equatable, Sendable {
    case actual
    case missing(String)
    case unavailable(String)
    case partial(String)
    case failed(String)
    case anomaly(String)

    public var reason: String? {
        switch self {
        case .actual:
            return nil
        case .missing(let reason),
             .unavailable(let reason),
             .partial(let reason),
             .failed(let reason),
             .anomaly(let reason):
            return reason
        }
    }

    public var isActual: Bool {
        if case .actual = self { return true }
        return false
    }

    public var isMissing: Bool {
        if case .missing = self { return true }
        return false
    }

    public var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    public var isPartial: Bool {
        if case .partial = self { return true }
        return false
    }

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    public var isAnomaly: Bool {
        if case .anomaly = self { return true }
        return false
    }

    public var emptyLabel: String {
        switch self {
        case .actual: return ""
        case .missing: return L10n.t("dataStatus.6ffa7e6d35")
        case .unavailable: return L10n.t("dataStatus.beff4a1cd1")
        case .partial: return L10n.t("dataStatus.d70cea022c")
        case .failed: return L10n.t("metric.syncFailure")
        case .anomaly: return L10n.t("dataStatus.ff09dc6102")
        }
    }

    public func valueText(_ actualText: String) -> String {
        isActual ? actualText : emptyLabel
    }

    public func prefixed(_ label: String) -> DataStatus {
        switch self {
        case .actual:
            return .actual
        case .missing(let reason):
            return .missing(L10n.f("common.labeledReason", label, L10n.t(reason)))
        case .unavailable(let reason):
            return .unavailable(L10n.f("common.labeledReason", label, L10n.t(reason)))
        case .partial(let reason):
            return .partial(L10n.f("common.labeledReason", label, L10n.t(reason)))
        case .failed(let reason):
            return .failed(L10n.f("common.labeledReason", label, L10n.t(reason)))
        case .anomaly(let reason):
            return .anomaly(L10n.f("common.labeledReason", label, L10n.t(reason)))
        }
    }
}
