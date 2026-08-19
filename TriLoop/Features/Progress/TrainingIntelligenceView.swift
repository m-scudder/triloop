import SwiftData
import SwiftUI

/// The §47 training-intelligence view of Progress.
///
/// Beginner-first by §48: time, sessions and adherence lead, with load,
/// intensity and recovery below. Advanced readings appear only when the data
/// supports them, so the screen shortens rather than filling with zeros.
struct TrainingIntelligenceView: View {
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]
    @Query private var profiles: [AthleteProfile]
    @Query private var summaries: [ImportedWorkoutSummary]
    @Environment(\.healthProvider) private var health

    @State private var range: TrendRange = .fourWeeks
    @State private var selectedSport: Sport?
    @State private var recovery: [RecoveryMetric: [RecoveryReading]] = [:]

    enum TrendRange: String, CaseIterable, Identifiable {
        case thisWeek = "This Week"
        case fourWeeks = "4 Weeks"
        case twelveWeeks = "12 Weeks"

        var id: Self { self }

        var weeks: Int {
            switch self {
            case .thisWeek: 1
            case .fourWeeks: 4
            case .twelveWeeks: 12
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Picker("Range", selection: $range) {
                ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if sessions.isEmpty {
                UnavailableNote(text: "Once you complete and report a few sessions, your training will be summarised here.")
            } else {
                overview
                TrainingLoadSection(weeks: weeklyLoads, average: rollingAverage)
                IntensityDistributionSection(
                    distribution: distribution,
                    sports: IntensityDistributionPolicy.sportsPresent(in: sessions),
                    selectedSport: $selectedSport
                )
                SportBalanceSection(balance: balance, comparisons: comparisons)
            }

            RecoverySection(readings: recovery, asOf: .now)
        }
        .task(id: range) { await loadRecovery() }
    }

    // MARK: - Overview

    private var overview: some View {
        HStack(alignment: .top, spacing: 20) {
            figure(
                value: TrainingFormatter.totalDuration(seconds: sessions.compactMap(\.durationSeconds).reduce(0, +)),
                caption: "Training"
            )
            figure(value: "\(sessions.count)", caption: sessions.count == 1 ? "Session" : "Sessions")

            if let adherence = adherenceShare {
                figure(value: "\(Int((adherence * 100).rounded()))%", caption: "Reported")
            }
        }
    }

    private func figure(value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Inputs

    private var builder: TrainingIntelligenceBuilder {
        TrainingIntelligenceBuilder(
            birthDate: profiles.first?.setup?.birthDate,
            observedMaximumHeartRate: summaries.compactMap(\.maximumHeartRate).max()
        )
    }

    /// The most recent plan weeks, oldest first.
    private var consideredPlans: [WeeklyPlan] {
        Array(plans.sorted { $0.startDate < $1.startDate }.suffix(range.weeks))
    }

    private var sessions: [LoadedSession] {
        builder.completedSessions(in: consideredPlans)
    }

    private var weeklyLoads: [WeeklyLoad] {
        builder.weeks(from: consideredPlans)
            .compactMap { WeeklyTrainingLoad.load(for: $0).value }
    }

    /// Always computed over the full history rather than the selected range, so
    /// a four-week average does not become a one-week average on This Week.
    private var rollingAverage: IntelligenceValue<Double> {
        let all = builder.weeks(from: plans)
            .compactMap { WeeklyTrainingLoad.load(for: $0).value }
        return WeeklyTrainingLoad.rollingAverage(of: all)
    }

    private var distribution: IntelligenceValue<IntensityDistribution> {
        IntensityDistributionPolicy.distribution(for: sessions, sport: selectedSport)
    }

    private var balance: IntelligenceValue<SportBalance> {
        SportBalancePolicy.balance(of: sessions)
    }

    private var comparisons: [SportBalanceComparison] {
        SportBalancePolicy.compare(
            planned: builder.plannedSessions(in: consideredPlans),
            actual: sessions
        )
    }

    /// Share of completed sessions the athlete actually reported on.
    private var adherenceShare: Double? {
        let workouts = consideredPlans
            .flatMap(\.orderedWorkouts)
            .filter { $0.discipline.sport != nil && !$0.isSkipped }
        guard !workouts.isEmpty else { return nil }
        return Double(workouts.count(where: \.hasReport)) / Double(workouts.count)
    }

    private func loadRecovery() async {
        let end = Date.now
        guard let start = Calendar.current.date(byAdding: .day, value: -28, to: end) else { return }

        var collected: [RecoveryMetric: [RecoveryReading]] = [:]
        for metric in RecoveryMetric.allCases {
            let points = (try? await health.recoverySeries(metric, from: start, to: end)) ?? []
            collected[metric] = points.map { RecoveryReading(date: $0.date, value: $0.value) }
        }
        recovery = collected
    }
}
