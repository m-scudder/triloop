import SwiftUI

/// Shared date-only control for Athevia.
///
/// Every date input uses the native iOS wheel picker so the interaction is
/// consistent across onboarding, profile, plans, events and workout editing.
/// The selected value is also rendered explicitly as dd/MMM/yyyy.
struct AtheviaDatePicker: View {
    let title: String
    @Binding var selection: Date
    var minimumDate: Date? = nil
    var maximumDate: Date? = nil
    var showsTitle = true

    init(
        title: String,
        selection: Binding<Date>,
        minimumDate: Date? = nil,
        maximumDate: Date? = nil,
        showsTitle: Bool = true
    ) {
        self.title = title
        _selection = selection
        self.minimumDate = minimumDate
        self.maximumDate = maximumDate
        self.showsTitle = showsTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    Spacer(minLength: 12)

                    selectedDate
                }
            } else {
                selectedDate
                    .frame(
                        maxWidth: .infinity,
                        alignment: .trailing
                    )
            }

            wheelPicker
        }
        .accessibilityElement(children: .contain)
    }

    private var selectedDate: some View {
        Text(TrainingFormatter.pickerDate(selection))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .accessibilityLabel(
                "\(title), \(TrainingFormatter.pickerDate(selection))"
            )
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
}
