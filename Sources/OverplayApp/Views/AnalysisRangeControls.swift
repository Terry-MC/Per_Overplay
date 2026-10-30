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
                Picker(L10n.t("range.2be9040878"), selection: $model.rangePreset) {
                    Section(L10n.t("range.e360e9b947")) {
                        ForEach(AnalysisRangePreset.allCases.filter(\.isNatural)) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    Section(L10n.t("range.f4ad4453d0")) {
                        ForEach([AnalysisRangePreset.last7Days, .last30Days, .last90Days]) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    Section(L10n.t("core.analysisRange.c493338e8c")) {
                        Text(AnalysisRangePreset.custom.label).tag(AnalysisRangePreset.custom)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: compact ? 130 : 150)
                .labelsHidden()

                if showsGranularity {
                    Picker(L10n.t("range.baf051c677"), selection: granularityBinding) {
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
                        L10n.t("range.79cc871ca9"),
                        selection: $model.customRangeStart,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    Text(L10n.t("range.43401e739e"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker(
                        L10n.t("range.76b9880829"),
                        selection: $model.customRangeEnd,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                }
                if let error = model.analysisRangeError {
                    Label(
                        L10n.f("range.b0a4820e46", error.message),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Text(L10n.t("range.2c69f1823f"))
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
            return L10n.t("range.9c7924ec7d")
        }
        return L10n.t("range.b3511ff1ae")
    }
}
