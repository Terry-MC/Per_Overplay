import SwiftUI
import OverplayCore

struct AnalysisRangeControls: View {
    @ObservedObject var model: AppModel
    var showsGranularity = false
    var granularities: [AnalysisGranularity] = [.automatic, .day, .month, .year]
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 10) {
                Picker("时间范围", selection: $model.rangePreset) {
                    Section("自然时间") {
                        ForEach(AnalysisRangePreset.allCases.filter(\.isNatural)) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    Section("滚动窗口") {
                        ForEach([AnalysisRangePreset.last7Days, .last30Days, .last90Days]) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    Section("自定义") {
                        Text(AnalysisRangePreset.custom.label).tag(AnalysisRangePreset.custom)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: compact ? 130 : 150)
                .labelsHidden()

                if showsGranularity {
                    Picker("粒度", selection: granularityBinding) {
                        ForEach(granularities) { granularity in
                            Text(granularity.label).tag(granularity)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 90)
                    .labelsHidden()
                    .help(granularityHelp)
                }

                Text(model.analysisRange.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            if model.rangePreset == .custom {
                HStack(spacing: 8) {
                    DatePicker(
                        "开始",
                        selection: $model.customRangeStart,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    Text("至")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker(
                        "结束",
                        selection: $model.customRangeEnd,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                }
                if let error = model.analysisRangeError {
                    Label(
                        "\(error.message)；统计暂按近 30 天兜底显示，修正后自动恢复",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Text("自然单位按本机时区；厂商用量按 UTC 日桶存储。分钟 / 小时仅用于余额快照等带真实时间戳的数据。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var granularityBinding: Binding<AnalysisGranularity> {
        Binding(
            get: {
                granularities.contains(model.selectedGranularity)
                    ? model.selectedGranularity
                    : .automatic
            },
            set: { model.selectedGranularity = $0 }
        )
    }

    private var granularityHelp: String {
        if granularities.contains(.minute) {
            return "余额快照支持分钟 / 小时；token / 费用仅有日级数据"
        }
        return "当前数据源仅支持自动 / 日 / 月 / 年粒度，不伪造分钟或小时点"
    }
}
