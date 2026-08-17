import SwiftData
import SwiftUI

/// Overview, per-sport volume and a few durable bests. No trend charts until
/// there is enough history for a trend to mean anything.
struct ProgressOverviewView: View {
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]

    private var stats: TrainingStatistics {
        TrainingStatistics(plans: plans)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    overview
                    if stats.hasData {
                        bySport
                        keyStats
                    }
                    weeks
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("Progress")
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Overview")
            Card {
                HStack(alignment: .top, spacing: 8) {
                    StatTile(value: "\(stats.sessions)", label: "Workouts")
                    StatTile(
                        value: TrainingFormatter.totalDuration(seconds: stats.totalDuration),
                        label: "Total time"
                    )
                    StatTile(
                        value: TrainingFormatter.distance(meters: stats.totalDistance),
                        label: "Total distance"
                    )
                }
            }
        }
    }

    private var bySport: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "By sport")
            Card {
                VStack(spacing: 16) {
                    ForEach(stats.bySport) { totals in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: totals.sport.discipline.symbolName)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Text(totals.sport.displayName)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(volume(for: totals))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(totals.sessions) workout\(totals.sessions == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ProportionBar(fraction: share(of: totals))
                        }
                    }
                }
            }
        }
    }

    private var keyStats: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Key stats")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    statRow("Longest run", TrainingFormatter.distance(meters: stats.longestRunMeters))
                    Divider().padding(.leading, 14)
                    statRow("Longest swim", TrainingFormatter.distance(meters: stats.longestSwimMeters))
                    Divider().padding(.leading, 14)
                    statRow("Longest ride", TrainingFormatter.totalDuration(seconds: stats.longestRideSeconds))
                    Divider().padding(.leading, 14)
                    statRow("Current streak", "\(stats.currentStreakDays) day\(stats.currentStreakDays == 1 ? "" : "s")")
                }
            }
        }
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var weeks: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Training weeks")

            if plans.isEmpty {
                Text("No weeks yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(plans, id: \.id) { plan in
                        NavigationLink {
                            WeekReviewView(plan: plan)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Week \(plan.weekNumber)")
                                        .font(.subheadline.weight(.medium))
                                    Text(summary(for: plan))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if plan.id != plans.last?.id {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
        }
    }

    private func volume(for totals: TrainingStatistics.SportTotals) -> String {
        totals.sport == .swimming
            ? TrainingFormatter.distance(meters: totals.distance)
            : TrainingFormatter.totalDuration(seconds: totals.duration)
    }

    /// Swimming is compared on distance and the others on time, so each bar is
    /// scaled against the largest value in its own unit.
    private func share(of totals: TrainingStatistics.SportTotals) -> Double {
        if totals.sport == .swimming {
            let peak = stats.bySport.filter { $0.sport == .swimming }.map(\.distance).max() ?? 0
            return peak > 0 ? totals.distance / peak : 0
        }
        let peak = stats.bySport.filter { $0.sport != .swimming }.map(\.duration).max() ?? 0
        return peak > 0 ? totals.duration / peak : 0
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
