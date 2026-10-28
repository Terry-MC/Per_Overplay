import SwiftUI

enum DataStatus: Equatable {
    case actual
    case missing(String)
    case anomaly(String)

    var reason: String? {
        switch self {
        case .actual: return nil
        case .missing(let reason), .anomaly(let reason): return reason
        }
    }

    var isMissing: Bool {
        if case .missing = self { return true }
        return false
    }

    var isAnomaly: Bool {
        if case .anomaly = self { return true }
        return false
    }

    var iconName: String? {
        switch self {
        case .actual: return nil
        case .missing: return "questionmark.circle"
        case .anomaly: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .actual: return .secondary
        case .missing: return .secondary
        case .anomaly: return .orange
        }
    }

    func accessibilityText(value: String) -> String {
        guard let reason else { return value }
        switch self {
        case .actual: return value
        case .missing: return "\(value)，占位值，原因：\(reason)"
        case .anomaly: return "\(value)，数据异常：\(reason)"
        }
    }

    func prefixed(_ label: String) -> DataStatus {
        switch self {
        case .actual:
            return .actual
        case .missing(let reason):
            return .missing("\(label)：\(reason)")
        case .anomaly(let reason):
            return .anomaly("\(label)：\(reason)")
        }
    }
}

struct DataValueLabel: View {
    var text: String
    var status: DataStatus
    var font: Font
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(text)
                .font(font)
                .foregroundStyle(status.isMissing ? Color.secondary : valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let iconName = status.iconName {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(status.tint)
                    .help(status.reason ?? "")
                    .accessibilityLabel(status.accessibilityText(value: text))
            }
        }
        .help(status.reason ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.accessibilityText(value: text))
    }
}
