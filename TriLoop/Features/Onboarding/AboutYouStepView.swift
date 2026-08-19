import SwiftUI

/// Asks for the athlete's date of birth, which anchors heart-rate zones.
///
/// Skippable on purpose: this is the one question with no training answer
/// behind it, and an athlete who declines still gets a full plan — only the
/// zone breakdown reports Unavailable.
struct AboutYouStepView: View {
    @Bindable var model: OnboardingModel

    /// A default in the middle of the likely range, so the wheel opens
    /// somewhere plausible rather than at today's date.
    private static let fallbackBirthDate = Calendar.current.date(
        byAdding: .year, value: -30, to: .now
    ) ?? .now

    private var range: ClosedRange<Date> {
        let calendar = Calendar.current
        let oldest = calendar.date(byAdding: .year, value: -100, to: .now) ?? .now
        let youngest = calendar.date(byAdding: .year, value: -10, to: .now) ?? .now
        return oldest...youngest
    }

    private var binding: Binding<Date> {
        Binding(
            get: { model.setup.birthDate ?? Self.fallbackBirthDate },
            set: { model.setBirthDate($0) }
        )
    }

    var body: some View {
        OnboardingStep(
            secondary: OnboardingSecondaryAction("Skip for now") {
                model.setBirthDate(nil)
                model.advance()
            },
            primary: model.advance
        ) {
            OnboardingHeader(
                title: "When were you born?",
                subtitle: "This sets your heart-rate zones, so TriLoop can tell an easy session from a hard one."
            )

            DatePicker(
                "Date of birth",
                selection: binding,
                in: range,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()

            if let birthDate = model.setup.birthDate,
               let maximum = HeartRateCeiling.ageBased(birthDate: birthDate, asOf: .now) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Estimated maximum heart rate: \(Int(maximum)) bpm")
                        .font(.subheadline)
                    Text("A population average, so it can be out by 10 bpm either way. If you record a harder effort than this, TriLoop uses what you actually did.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
