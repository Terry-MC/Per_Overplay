import SwiftUI
import OverplayCore

extension DataStatus {
    var iconName: String? {
        switch self {
        case .actual: return nil
        case .missing: return "tray"
        case .unavailable: return "minus.circle"
        case .partial: return "exclamationmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .anomaly: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .actual: return .secondary
        case .missing, .unavailable: return .secondary
        case .partial: return .orange
        case .failed: return .red
        case .anomaly: return .orange
        }
    }

    func accessibilityText(value: String) -> String {
        guard let reason else { return value }
        switch self {
        case .actual:
            return value
        case .missing:
            return "\(emptyLabel)，原因：\(reason)"
        case .unavailable:
            return "不可用，原因：\(reason)"
        case .partial:
            return "暂无完整数据，原因：\(reason)"
        case .failed:
            return "同步失败，原因：\(reason)"
        case .anomaly:
            return "数据异常，原因：\(reason)"
        }
    }
}

struct DataValueLabel: View {
    var text: String
    var status: DataStatus
    var font: Font
    var valueColor: Color = .primary

    private var displayText: String {
        status.valueText(text)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(displayText)
                .font(font)
                .foregroundStyle(status.isActual ? valueColor : Color.secondary)
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
