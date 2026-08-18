import SwiftData
import SwiftUI

/// The §18 week review: what happened per sport, and what follows from it.
struct WeekReviewView: View {
    let plan: WeeklyPlan

    @Query private var plans: [WeeklyPlan]

    private var analysis: WeeklyAnalysis {
        WeeklyAnalyser().analyse(plan)
    }

    private var nextWeekExists: Bool {
        plans.contains { $0.weekNumber == plan.weekNumber + 1 }
    }

    /// The week takes its most cautious sport, matching how the engine decides.
    private var overallStatus: AssessmentStatus {
        analysis.sports.map(\.status).max { $0.caution < $1.caution } ?? .maintain
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(TrainingFormatter.weekRange(start: analysis.startDate, end: analysis.endDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                banner

                ForEach(analysis.sports) { sport in
                    sportCard(sport)
                }

                if analysis.sports.isEmpty {
                    Text("No sessions have been reported for this week yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !nextWeekExists {
                    NavigationLink {
                        NextWeekPreviewView(previousWeek: plan)
                    } label: {
                        Text("Preview Week \(plan.weekNumber + 1)")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(!analysis.isReadyForNextWeek)

                    if !analysis.isReadyForNextWeek {
                        Text("Available once every session this week has been reported on.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .navigationTitle("Week \(analysis.weekNumber) Analysis")
        .navigationBarTitleDisplayMode(.large)
    }

    private var banner: some View {
        HStack(spacing: 8) {
            Image(systemName: overallStatus == .progress ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.footnote)
            Text(overallStatus.weekHeadline)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
            Text("\(analysis.completedSessions)/\(analysis.plannedSessions)")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
        .padding(12)
        .background(overallStatus.tint.opacity(0.14), in: .rect(cornerRadius: 12))
        .foregroundStyle(overallStatus.tint)
    }

    private func sportCard(_ sport: SportAnalysis) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: sport.sport.discipline.symbolName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(sport.sport.displayName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    StatusPill(status: sport.status)
                }

                HStack(alignment: .top, spacing: 8) {
                    StatTile(value: "\(sport.completedSessions) / \(sport.plannedSessions)", label: "Sessions")
                    StatTile(value: volume(for: sport), label: sport.sport == .swimming ? "Distance" : "Duration")
                    StatTile(
                        value: sport.averageRPE.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—",
                        label: "Avg RPE"
                    )
                    StatTile(value: "\(sport.highestPain)", label: "Pain")
                }

                Divider()

                Text(sport.adjustment.summary)
                    .font(.subheadline)

                if !sport.reasons.isEmpty {
                    Text(sport.reasons.map(\.summary).joined(separator: ". ") + ".")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func volume(for sport: SportAnalysis) -> String {
        if sport.sport == .swimming {
            return sport.totalDistanceMeters > 0
                ? TrainingFormatter.distance(meters: sport.totalDistanceMeters)
                : "—"
        }
        return sport.totalDurationSeconds > 0
            ? TrainingFormatter.totalDuration(seconds: sport.totalDurationSeconds)
            : "—"
    }
}
