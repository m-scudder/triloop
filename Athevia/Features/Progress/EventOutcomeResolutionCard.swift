import SwiftData
import SwiftUI

struct EventOutcomeResolutionCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var profile: AthleteProfile

    private var setup: AthleteSetup { profile.setup ?? AthleteSetup() }

    private var event: AthleteEventGoal? { setup.objective.event }

    var shouldResolve: Bool {
        guard setup.eventState.status == .upcoming,
              let event,
              let days = event.daysRemaining() else {
            return false
        }
        return days < 0
    }

    var body: some View {
        if shouldResolve, let event {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(text: "Event update")

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What happened with \(event.displayName)?")
                            .font(.headline)

                        Button("I completed it") {
                            resolve(.completed, evidence: .athleteConfirmation)
                        }
                        .buttonStyle(.borderedProminent)

                        HStack {
                            Button("I did not participate") {
                                resolve(.missed)
                            }
                            .buttonStyle(.bordered)

                            Button("The event was cancelled") {
                                resolve(.cancelled)
                            }
                            .buttonStyle(.bordered)
                        }

                        NavigationLink {
                            TrainingProfileView(profile: profile)
                        } label: {
                            Label("Change the event", systemImage: "calendar.badge.clock")
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    private func resolve(
        _ status: AthleteEventStatus,
        evidence: EventCompletionEvidenceSource? = nil
    ) {
        var updated = setup
        let resolvedAt = status == .completed
            ? (event?.eventDate ?? .now)
            : .now
        updated.eventState = AthleteEventState(
            status: status,
            resolvedAt: resolvedAt,
            completionEvidence: evidence
        )
        profile.setup = updated
        try? modelContext.save()
    }
}
