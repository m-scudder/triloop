import SwiftData
import SwiftUI

/// Overview, per-sport volume and a few durable bests. No trend charts until
/// there is enough history for a trend to mean anything.
struct ProgressOverviewView: View {
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]

    private var stats: TrainingStatistics {
        TrainingStatistics(plans: plans)
    }

    private var current: CurrentTraining? {
        CurrentTraining(plans: plans)
    }

    /// Newest first, across every week, so an older session is one tap away
    /// rather than several weeks of navigation.
    private var recentSessions: [PlannedWorkout] {
        plans
            .flatMap(\.trainingSessions)
            .filter { $0.isCompleted }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let current, current.hasData {
                        currentTraining(current)
                    }
                    overview
                    if stats.hasData {
                        bySport
                        keyStats
                    }
                    if !recentSessions.isEmpty {
                        history
                    }
                    weeks
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("Progress")
        }
    }

    /// The headline TriLoop can give that a workout log cannot: what you are on
    /// now, and which way it is going.
    private func currentTraining(_ current: CurrentTraining) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Where you are now")

            VStack(spacing: 10) {
                ForEach(current.states) { state in
                    HStack(spacing: 14) {
                        Image(systemName: state.sport.discipline.symbolName)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(state.sport.discipline.gradient, in: .rect(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.sport.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(state.prescription)
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        if let status = state.status {
                            HStack(spacing: 4) {
                                Image(systemName: status.directionSymbol)
                                Text(status.directionLabel)
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(status.tint.opacity(0.16), in: .capsule)
                            .foregroundStyle(status.tint)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(state.sport.discipline.tint.opacity(0.14))
                    )
                }
            }
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
                                    .foregroundStyle(totals.sport.discipline.tint)
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
                            ProportionBar(
                                fraction: share(of: totals),
                                tint: totals.sport.discipline.tint
                            )
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

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Sessions")

            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(recentSessions, id: \.id) { session in
                        NavigationLink {
                            WorkoutDetailView(workout: session)
                        } label: {
                            sessionRow(session)
                        }
                        .buttonStyle(.plain)

                        if session.id != recentSessions.last?.id {
                            Divider().padding(.leading, 62)
                        }
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: PlannedWorkout) -> some View {
        HStack(spacing: 12) {
            DisciplineBadge(discipline: session.discipline, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.subheadline.weight(.medium))
                Text(sessionDetail(session))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if session.awaitingFeedback {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func sessionDetail(_ session: PlannedWorkout) -> String {
        var parts: [String] = []

        if let summary = session.importedSummary {
            if session.discipline == .swimming, let distance = summary.distanceMeters, distance > 0 {
                parts.append(TrainingFormatter.distance(meters: distance))
            } else {
                parts.append(TrainingFormatter.totalDuration(seconds: summary.duration))
            }
            if let heartRate = summary.averageHeartRate {
                parts.append("\(Int(heartRate.rounded())) bpm")
            }
        } else if let summary = WorkoutSummaryText.make(for: session) {
            parts.append(summary)
        }

        if let rpe = session.feedback?.rpe {
            parts.append("RPE \(rpe)")
        }

        return parts.isEmpty ? session.title : parts.joined(separator: " · ")
    }

    private var weeks: some View {        VStack(alignment: .leading, spacing: 10) {
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
