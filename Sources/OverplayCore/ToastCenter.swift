import Foundation

public enum NoticeStyle: String, Equatable, Sendable {
    case info
    case success
    case warning
    case error
}

public struct ToastMessage: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var message: String
    public var style: NoticeStyle
    public var alertId: String?
    public var isDemo: Bool
    public var duration: TimeInterval
    public var expiresAt: Date?
    public var autoDismiss: Bool

    public init(
        id: String,
        title: String,
        message: String,
        style: NoticeStyle,
        alertId: String? = nil,
        isDemo: Bool = false,
        duration: TimeInterval = 8,
        expiresAt: Date? = nil,
        autoDismiss: Bool
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.style = style
        self.alertId = alertId
        self.isDemo = isDemo
        self.duration = duration
        self.expiresAt = expiresAt
        self.autoDismiss = autoDismiss
    }

    public var isAlert: Bool { alertId != nil }
}

/// 顶部消息最多同时展示 3 条；error 插队到等待队列前面，且不会自动消失。
public struct ToastQueue: Equatable, Sendable {
    public private(set) var visible: [ToastMessage] = []
    public private(set) var pending: [ToastMessage] = []
    public let maxVisible: Int

    public init(maxVisible: Int = 3) {
        self.maxVisible = maxVisible
    }

    @discardableResult
    public mutating func enqueue(_ toast: ToastMessage, now: Date) -> [ToastMessage] {
        if toast.style == .error {
            pending.insert(toast, at: 0)
        } else {
            pending.append(toast)
        }
        return promote(now: now)
    }

    @discardableResult
    public mutating func expire(id: String, now: Date) -> [ToastMessage] {
        guard let index = visible.firstIndex(where: { $0.id == id }),
              visible[index].autoDismiss else { return [] }
        visible.remove(at: index)
        return promote(now: now)
    }

    @discardableResult
    public mutating func dismiss(id: String, now: Date) -> [ToastMessage] {
        visible.removeAll { $0.id == id }
        pending.removeAll { $0.id == id }
        return promote(now: now)
    }

    @discardableResult
    public mutating func removeAlert(alertId: String, now: Date) -> [ToastMessage] {
        pending.removeAll { $0.alertId == alertId }
        visible.removeAll { $0.alertId == alertId }
        return promote(now: now)
    }

    @discardableResult
    public mutating func removeAlerts(notIn ids: Set<String>, now: Date) -> [ToastMessage] {
        pending.removeAll { toast in
            guard let alertId = toast.alertId else { return false }
            return !ids.contains(alertId)
        }
        visible.removeAll { toast in
            guard let alertId = toast.alertId else { return false }
            return !ids.contains(alertId)
        }
        return promote(now: now)
    }

    public mutating func dismissAll() {
        visible.removeAll()
        pending.removeAll()
    }

    private mutating func promote(now: Date) -> [ToastMessage] {
        var promoted: [ToastMessage] = []
        while visible.count < maxVisible, !pending.isEmpty {
            var toast = pending.removeFirst()
            if toast.autoDismiss {
                toast.expiresAt = now.addingTimeInterval(toast.duration)
            }
            visible.append(toast)
            promoted.append(toast)
        }
        return promoted
    }
}

public enum AlertNoticePolicy {
    public static func style(for kind: AlertKind) -> NoticeStyle {
        switch kind {
        case .budgetExceeded, .balanceLow, .credentialInvalid, .syncFailed, .lineCritical:
            return .error
        case .budgetWarning, .lineWarning:
            return .info
        case .dataStale:
            return .warning
        }
    }

    public static func autoDismiss(for kind: AlertKind) -> Bool {
        style(for: kind) != .error
    }

    public static func toast(for alert: AlertEvent) -> ToastMessage {
        let style = style(for: alert.kind)
        return ToastMessage(
            id: "alert-\(alert.id)",
            title: alert.renderedTitle,
            message: L10n.f("core.toast.707e98502e", alert.accountName, alert.renderedValue, alert.renderedThreshold),
            style: style,
            alertId: alert.id,
            isDemo: alert.isDemo,
            duration: alert.kind == .lineWarning ? 5 : 8,
            autoDismiss: autoDismiss(for: alert.kind)
        )
    }
}
