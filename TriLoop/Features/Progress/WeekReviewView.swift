import SwiftData
import SwiftUI

extension AssessmentStatus {
    var tint: Color {
        switch self {
        case .progress: .green
        case .maintain: .blue
        case .reduce: .orange
        case .recoveryRequired: .red
        }
    }
}

/// The §18 week review. Reports what happened and what follows from it, without
/// inventing a readiness score.
struct WeekReviewView: View {
    let plan: WeeklyPlan

    @Environment(\.modelContext) private var context
    @Query private var plans: [WeeklyPlan]

    private var analysis: WeeklyAnalysis {
        WeeklyAnalyser().analyse(plan)
    }

    private var nextWeekExists: Bool {
        plans.contains { $0.weekNumber == plan.weekNumber + 1 }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Workouts") {
                    Text("\(analysis.completedSessions) / \(analysis.plannedSessions) completed")
                }
            }

            ForEach(analysis.sports, id: \.sport) { sport in
                Section(sport.sport.displayName) {
                    LabeledContent("Status") {
                        Text(sport.status.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(sport.status.tint)
                    }
                    LabeledContent("Sessions") {
                        Text("\(sport.completedSessions) / \(sport.plannedSessions)")
                    }
                    if let rpe = sport.averageRPE {
                        LabeledContent("Average effort") {
                            Text("\(rpe.formatted(.number.precision(.fractionLength(0...1)))) / 10")
                        }
                    }
                    LabeledContent("Highest pain") {
                        Text("\(sport.highestPain) / 10")
                    }
                    if let volume = volume(for: sport) {
                        LabeledContent("Volume") { Text(volume) }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recommendation")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(sport.adjustment.summary)
                            .font(.subheadline)
                        if !sport.reasons.isEmpty {
                            Text(sport.reasons.map(\.summary).joined(separator: ". ") + ".")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if !nextWeekExists {
                Section {
                    Button("Generate week \(plan.weekNumber + 1)") {
                        PlanStore(context: context).generateNextWeek(after: plan)
                    }
                    .disabled(!analysis.isReadyForNextWeek)
                } footer: {
                    Text(
                        analysis.isReadyForNextWeek
                            ? "Builds next week from these results."
                            : "Available once every session this week has been reported on."
                    )
                }
            }
        }
        .navigationTitle("Week \(analysis.weekNumber) review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func volume(for sport: SportAnalysis) -> String? {
        if sport.sport == .swimming, sport.totalDistanceMeters > 0 {
            return TrainingFormatter.distance(meters: sport.totalDistanceMeters)
        }
        if sport.totalDurationSeconds > 0 {
            return TrainingFormatter.totalDuration(seconds: sport.totalDurationSeconds)
        }
        return nil
    }
}
