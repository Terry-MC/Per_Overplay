import Foundation

/// Pure presentation model for the menu bar status item, so the demo badge
/// rules can be unit tested without AppKit.
public struct StatusItemPresentation: Equatable, Sendable {
    public enum Severity: String, Equatable, Sendable {
        case failure
        case critical
        case warning
        case normal
    }

    public var symbolName: String
    public var severity: Severity
    public var showsDemoBadge: Bool
    public var accessibilityLabel: String

    public init(
        symbolName: String,
        severity: Severity,
        showsDemoBadge: Bool,
        accessibilityLabel: String
    ) {
        self.symbolName = symbolName
        self.severity = severity
        self.showsDemoBadge = showsDemoBadge
        self.accessibilityLabel = accessibilityLabel
    }

    public static func make(isDemo: Bool, alerts: [AlertEvent]) -> StatusItemPresentation {
        let unacknowledged = alerts.filter { !$0.acknowledged }
        let failure = unacknowledged.contains {
            $0.kind == .credentialInvalid || $0.kind == .syncFailed
        }
        let critical = unacknowledged.contains {
            $0.kind == .budgetExceeded || $0.kind == .balanceLow
        }
        let warning = unacknowledged.contains {
            $0.kind == .budgetWarning || $0.kind == .dataStale
        }

        let symbolName: String
        let severity: Severity
        if failure {
            symbolName = "xmark.octagon.fill"
            severity = .failure
        } else if critical {
            symbolName = "exclamationmark.triangle.fill"
            severity = .critical
        } else if warning {
            symbolName = "exclamationmark.circle.fill"
            severity = .warning
        } else {
            symbolName = "chart.bar.xaxis"
            severity = .normal
        }

        return StatusItemPresentation(
            symbolName: symbolName,
            severity: severity,
            showsDemoBadge: isDemo,
            accessibilityLabel: isDemo
                ? "Overplay 菜单栏图标 · 演示数据"
                : "Overplay 菜单栏图标"
        )
    }
}
