import SwiftUI

struct TrainingJourneySummaryView: View {
    let journey: TrainingJourney

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Journey")

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(journey.phase.displayName, systemImage: "flag.checkered")
                            .font(.headline)
                        Spacer()
                        if let weeks = journey.weeksRemaining {
                            Text("\(weeks) wk")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let focus = journey.primaryFocus {
                        LabeledContent("This week's focus", value: focus.kind.displayName)
                            .font(.subheadline)
                    }

                    LabeledContent("Readiness", value: journey.readiness.status.displayName)
                        .font(.subheadline)

                    ForEach(journey.sportPriorities.prefix(3)) { priority in
                        HStack(spacing: 10) {
                            Image(systemName: priority.sport.discipline.symbolName)
                                .foregroundStyle(priority.sport.discipline.tint)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(priority.sport.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text(priority.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    let gaps = journey.readiness.sports.flatMap(\.gaps)
                        .filter { $0 != .insufficientRecentEvidence }
                    if let gap = gaps.first {
                        Divider()
                        Text(gap.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
