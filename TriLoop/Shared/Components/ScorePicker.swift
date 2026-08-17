import SwiftUI

/// Horizontal number selector used for the effort and pain scales.
///
/// Uses an adaptive grid rather than a fixed row so an 11-point scale still
/// keeps 44pt hit targets at large Dynamic Type sizes.
struct ScorePicker: View {
    let range: ClosedRange<Int>
    @Binding var selection: Int
    let accessibilityPrefix: String

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(range), id: \.self) { value in
                let isSelected = value == selection

                Button {
                    selection = value
                } label: {
                    Text(value, format: .number)
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary))
                        )
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(accessibilityPrefix) \(value)")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

/// Multi- or single-select pill list, sized for one-handed tapping.
struct ChipGrid<Value: Hashable & Identifiable>: View {
    let values: [Value]
    let title: (Value) -> String
    let isSelected: (Value) -> Bool
    let toggle: (Value) -> Void

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(values) { value in
                let selected = isSelected(value)

                Button {
                    toggle(value)
                } label: {
                    Text(title(value))
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary))
                        )
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

extension PainLocation: Identifiable {
    var id: String { rawValue }
}

extension RecoveryFeeling: Identifiable {
    var id: String { rawValue }
}

extension WarningSymptom: Identifiable {
    var id: String { rawValue }
}

extension SorenessLevel: Identifiable {
    var id: String { rawValue }
}

extension EnergyLevel: Identifiable {
    var id: String { rawValue }
}
