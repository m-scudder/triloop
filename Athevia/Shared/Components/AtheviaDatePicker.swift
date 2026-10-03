import SwiftUI

/// Shared date-only control for Athevia.
///
/// Screens show only the selected date by default. Tapping the date opens the
/// native iOS wheel picker, keeping the roller hidden until the athlete asks
/// to edit the value. The selected value is rendered as dd/MMM/yyyy.
struct AtheviaDatePicker: View {
    let title: String
    @Binding var selection: Date
    var minimumDate: Date? = nil
    var maximumDate: Date? = nil
    var showsTitle = true

    @State private var isPresentingWheel = false

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
        Button {
            isPresentingWheel = true
        } label: {
            HStack(spacing: 12) {
                if showsTitle {
                    Text(title)
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: showsTitle ? 12 : 0)

                Text(TrainingFormatter.pickerDate(selection))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Image(systemName: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(
            TrainingFormatter.pickerDate(selection)
        )
        .sheet(isPresented: $isPresentingWheel) {
            NavigationStack {
                VStack(spacing: 12) {
                    Text(
                        TrainingFormatter.pickerDate(selection)
                    )
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()

                    NativeWheelDatePicker(
                        title: title,
                        selection: $selection,
                        minimumDate: minimumDate,
                        maximumDate: maximumDate
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(
                        placement: .confirmationAction
                    ) {
                        Button("Done") {
                            isPresentingWheel = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

/// Internal native roller used by the shared picker and screens that already
/// present a dedicated date sheet (for example Plan's calendar button).
struct NativeWheelDatePicker: View {
    let title: String
    @Binding var selection: Date
    var minimumDate: Date? = nil
    var maximumDate: Date? = nil

    var body: some View {
        picker
            .datePickerStyle(.wheel)
            .labelsHidden()
    }

    @ViewBuilder
    private var picker: some View {
        if let minimumDate, let maximumDate {
            DatePicker(
                title,
                selection: $selection,
                in: minimumDate...maximumDate,
                displayedComponents: .date
            )
        } else if let minimumDate {
            DatePicker(
                title,
                selection: $selection,
                in: minimumDate...,
                displayedComponents: .date
            )
        } else if let maximumDate {
            DatePicker(
                title,
                selection: $selection,
                in: ...maximumDate,
                displayedComponents: .date
            )
        } else {
            DatePicker(
                title,
                selection: $selection,
                displayedComponents: .date
            )
        }
    }
}
