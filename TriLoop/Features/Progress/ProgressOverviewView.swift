import SwiftData
import SwiftUI

/// Deliberately minimal for Phase 1: weekly volume only. Meaningful trends
/// arrive once the training engine (Phase 3) produces real assessments.
struct ProgressOverviewView: View {
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]

    var body: some View {
        NavigationStack {
            List {
                Section("Training weeks") {
                    if plans.isEmpty {
                        Text("No weeks yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(plans, id: \.id) { plan in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Week \(plan.weekNumber)")
                                .font(.body.weight(.medium))
                            Text(summary(for: plan))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Progress")
        }
    }

    private func summary(for plan: WeeklyPlan) -> String {
        let sessions = plan.trainingSessions
        let minutes = sessions
            .compactMap(\.estimatedDurationSeconds)
            .reduce(0, +) / 60
        return "\(sessions.count) workouts · \(Int(minutes.rounded())) min planned"
    }
}

#Preview {
    ProgressOverviewView()
        .modelContainer(PreviewData.container)
}
