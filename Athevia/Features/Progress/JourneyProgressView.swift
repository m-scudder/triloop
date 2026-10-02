import SwiftUI

/// Progress only surfaces milestones from the richer journey snapshot.
/// Capability gaps and next-action reasoning remain internal inputs to planning.
struct JourneyProgressView: View {
    let snapshot: JourneyProgressSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Milestones")

            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(snapshot.milestones.suffix(4)) { milestone in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(
                                    AtheviaAdaptiveStyle(
                                        .secondary,
                                        gaming: .secondaryText
                                    )
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(milestone.kind.displayName)
                                    .font(.subheadline.weight(.semibold))

                                Text(milestone.detail)
                                    .font(.caption)
                                    .foregroundStyle(
                                        AtheviaAdaptiveStyle(
                                            .secondary,
                                            gaming: .secondaryText
                                        )
                                    )

                                Text(
                                    milestone.achievedAt,
                                    format: .dateTime
                                        .day()
                                        .month(.abbreviated)
                                        .year()
                                )
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }

                            Spacer()
                        }
                        .padding(14)

                        if milestone.id
                            != snapshot.milestones.suffix(4).last?.id {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
            }
        }
    }
}
