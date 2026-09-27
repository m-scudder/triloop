import SwiftUI

/// Small event context used where a countdown is useful without turning Today
/// or Plan into a second dashboard.
struct EventCountdownView: View {
    let objective: TrainingObjective
    var asOf: Date = .now

    var body: some View {
        if let event = objective.event,
           let eventDate = event.eventDate,
           let countdown = event.countdownLabel(asOf: asOf) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.displayName.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        .lineLimit(1)

                    Text(TrainingFormatter.shortDate(eventDate, includeYear: true))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 8)

                Text(countdown)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(event.displayName), \(TrainingFormatter.shortDate(eventDate, includeYear: true)), \(countdown)"
            )
        }
    }
}

