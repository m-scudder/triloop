import SwiftData
import SwiftUI

/// The analytical side of Progress: how much training load the athlete carried,
/// how hard it was, and how it was distributed across sports.
struct TrainingIntelligenceView: View {
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]
    @Query private var profiles: [AthleteProfile]
    @Query private var summaries: [ImportedWorkoutSummary]
    @Environment(\.healthProvider) private var health

    @State private var range: TrendRange = .fourWeeks
    @State private var selectedSport: Sport?
    @State private var interpreted: [TrainingIntelligenceBuilder.Interpreted] = []

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
                UnavailableNote(text: "Complete a few workouts to build your training trends.")
                    .padding(.top, 16)
            } else {
                TrainingLoadSection(weeks: weeklyLoads, average: rollingAverage)

                Divider()

                IntensityDistributionSection(
                    distribution: distribution,
                    sports: IntensityDistributionPolicy.sportsPresent(in: sessions),
                    selectedSport: $selectedSport
                )

                Divider()

                SportBalanceSection(balance: balance, comparisons: comparisons)
            }
        }
        .task { await loadTraining() }
        .onChange(of: plans.count) { _, _ in
            Task { await loadTraining() }
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

    private var consideredInterpreted: [TrainingIntelligenceBuilder.Interpreted] {
        guard let start = consideredPlans.first?.startDate,
              let end = consideredPlans.last?.endDate else { return [] }
        return interpreted.filter {
            $0.evidence.date >= start && $0.evidence.date <= end
        }
    }

    private var sessions: [LoadedSession] {
        consideredInterpreted.map(\.session)
    }

    private var weeklyLoads: [WeeklyLoad] {
        builder.weeks(from: consideredPlans, interpreted: consideredInterpreted)
            .compactMap { WeeklyTrainingLoad.load(for: $0).value }
    }

    /// The rolling average still uses full history so changing the visible range
    /// never changes what "4-week average" means.
    private var rollingAverage: IntelligenceValue<Double> {
        let all = builder.weeks(from: plans, interpreted: interpreted)
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

    private func loadTraining() async {
        interpreted = builder.interpret(await builder.evidence(in: plans, provider: health))
    }
}
