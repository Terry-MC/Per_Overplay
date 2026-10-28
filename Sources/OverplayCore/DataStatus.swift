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
        case .missing: return "无数据"
        case .unavailable: return "不可用"
        case .partial: return "暂无完整数据"
        case .failed: return "同步失败"
        case .anomaly: return "数据异常"
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
            return .missing("\(label)：\(reason)")
        case .unavailable(let reason):
            return .unavailable("\(label)：\(reason)")
        case .partial(let reason):
            return .partial("\(label)：\(reason)")
        case .failed(let reason):
            return .failed("\(label)：\(reason)")
        case .anomaly(let reason):
            return .anomaly("\(label)：\(reason)")
        }
    }
}
