import SwiftData
import SwiftUI

/// Weekly volume plus a per-week review. Meaningful trends arrive once there is
/// more than a week or two of history to trend.
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
                        NavigationLink {
                            WeekReviewView(plan: plan)
                        } label: {
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
            }
            .navigationTitle("Progress")
        }
    }

    private func summary(for plan: WeeklyPlan) -> String {
        let sessions = plan.trainingSessions
        let completed = sessions.filter(\.hasReport).count
        let minutes = sessions
            .compactMap(\.estimatedDurationSeconds)
            .reduce(0, +) / 60
        return "\(completed)/\(sessions.count) completed · \(Int(minutes.rounded())) min planned"
    }
}

#Preview {
    ProgressOverviewView()
        .modelContainer(PreviewData.container)
}
