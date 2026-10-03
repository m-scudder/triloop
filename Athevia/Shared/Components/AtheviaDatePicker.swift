import SwiftUI

/// Athevia's shared date-only picker.
///
/// Native DatePicker presentation follows the device locale, which means the
/// same date can appear as 12/13/95, 13/12/95, or another regional variant.
/// This wrapper keeps the actual Date value and native calendar/wheel controls,
/// but always presents the selected value as dd/MMM/yyyy.
struct AtheviaDatePicker: View {
    enum Presentation {
        case compact
        case wheel
        case graphical
    }

    let title: String
    @Binding var selection: Date
    var minimumDate: Date? = nil
    var maximumDate: Date? = nil
    var presentation: Presentation = .compact
    var showsTitle = true

    @State private var isPresentingPicker = false

    init(
        title: String,
        selection: Binding<Date>,
        minimumDate: Date? = nil,
        maximumDate: Date? = nil,
        presentation: Presentation = .compact,
        showsTitle: Bool = true
    ) {
        self.title = title
        _selection = selection
        self.minimumDate = minimumDate
        self.maximumDate = maximumDate
        self.presentation = presentation
        self.showsTitle = showsTitle
    }

    var body: some View {
        switch presentation {
        case .compact:
            compactField
        case .wheel:
            inlinePicker(style: .wheel)
        case .graphical:
            inlinePicker(style: .graphical)
        }
    }

    private var compactField: some View {
        Button {
            isPresentingPicker = true
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Text(TrainingFormatter.pickerDate(selection))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Image(systemName: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(
            TrainingFormatter.pickerDate(selection)
        )
        .sheet(isPresented: $isPresentingPicker) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text(
                        TrainingFormatter.pickerDate(selection)
                    )
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()

                    graphicalPicker
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(
                        placement: .confirmationAction
                    ) {
                        Button("Done") {
                            isPresentingPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func inlinePicker(
        style: Presentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    Spacer(minLength: 12)

                    Text(
                        TrainingFormatter.pickerDate(selection)
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            } else {
                Text(
                    TrainingFormatter.pickerDate(selection)
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            switch style {
            case .wheel:
                wheelPicker
            case .graphical, .compact:
                graphicalPicker
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var wheelPicker: some View {
        if let minimumDate, let maximumDate {
            DatePicker(
                title,
                selection: $selection,
                in: minimumDate...maximumDate,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
        } else if let minimumDate {
            DatePicker(
                title,
                selection: $selection,
                in: minimumDate...,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
        } else if let maximumDate {
            DatePicker(
                title,
                selection: $selection,
                in: ...maximumDate,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
        } else {
            DatePicker(
                title,
                selection: $selection,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var graphicalPicker: some View {
        if let minimumDate, let maximumDate {
            DatePicker(
                title,
                selection: $selection,
                in: minimumDate...maximumDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
        } else if let minimumDate {
            DatePicker(
                title,
                selection: $selection,
                in: minimumDate...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
        } else if let maximumDate {
            DatePicker(
                title,
                selection: $selection,
                in: ...maximumDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
        } else {
            DatePicker(
                title,
                selection: $selection,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
        }
    }
}
