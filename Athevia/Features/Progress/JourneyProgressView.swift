import SwiftUI

struct JourneyProgressView: View {
    let snapshot: JourneyProgressSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            capabilitySection

            if !snapshot.milestones.isEmpty {
                milestoneSection
            }

            Card {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(snapshot.nextAction)
                        .font(.subheadline)
                }
            }
        }
    }

    private var capabilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Event capability")

            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(snapshot.capabilities) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.sport.discipline.symbolName)
                                .foregroundStyle(item.sport.discipline.tint)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.requirement)
                                    .font(.subheadline.weight(.semibold))
                                Text(item.currentEvidence)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(item.state.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)

                        if item.id != snapshot.capabilities.last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
        }
    }

    private var milestoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Milestones")

            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(snapshot.milestones.suffix(4)) { milestone in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(milestone.kind.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text(milestone.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(milestone.achievedAt, format: .dateTime.day().month(.abbreviated).year())
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                        .padding(14)

                        if milestone.id != snapshot.milestones.suffix(4).last?.id {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
            }
        }
    }
}
