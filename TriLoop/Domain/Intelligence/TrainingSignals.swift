import Foundation

/// Everything the intelligence layer concluded, in one value (§50).
///
/// Phase 10's input. Each group is independently available, because an athlete
/// with workouts but no wearable has workload and adherence while having no
/// recovery at all — and a single "unavailable" for the whole struct would
/// throw away the parts that do exist.
struct TrainingSignals: Equatable, Sendable {
    var workload: WorkloadSignals
    var adherence: AdherenceSignals
    var intensity: IntensitySignals
    var recovery: RecoverySignals
    var performance: PerformanceSignals

    /// True when nothing at all could be derived.
    var isEmpty: Bool {
        workload.isEmpty && adherence.isEmpty && intensity.isEmpty
            && recovery.isEmpty && performance.isEmpty
    }
}

/// How much training is accumulating, and how fast that is changing.
struct WorkloadSignals: Equatable, Sendable {
    var currentWeek: IntelligenceValue<Double> = .unavailable
    var previousWeek: IntelligenceValue<Double> = .unavailable
    var fourWeekAverage: IntelligenceValue<Double> = .unavailable
    /// Fraction change from the previous week.
    var weekOnWeekChange: Double?
    /// Load per sport for the current week.
    var bySport: [Sport: Double] = [:]

    var isEmpty: Bool { !currentWeek.isAvailable && !fourWeekAverage.isAvailable }

    /// Change against the settled average rather than one week, which is noisy.
    var changeAgainstAverage: Double? {
        guard let current = currentWeek.value,
              let average = fourWeekAverage.value,
              average > 0 else { return nil }
        return (current - average) / average
    }
}

/// Whether execution matched prescription.
struct AdherenceSignals: Equatable, Sendable {
    var outcomes: [SessionAdherence] = []

    var isEmpty: Bool { outcomes.isEmpty }

    func count(of adherence: SessionAdherence) -> Int {
        outcomes.count { $0 == adherence }
    }

    /// Sessions that went harder than asked, which is the safety-relevant one.
    var aboveTargetCount: Int { count(of: .aboveTarget) }
    var completedCount: Int {
        outcomes.count { $0 != .skipped && $0 != .missed }
    }
}

/// Where training time is going.
struct IntensitySignals: Equatable, Sendable {
    var distribution: IntelligenceValue<IntensityDistribution> = .unavailable
    var balance: IntelligenceValue<SportBalance> = .unavailable

    var isEmpty: Bool { !distribution.isAvailable && !balance.isAvailable }

    var hardShare: Double? {
        distribution.value.map { $0.share(.hard) }
    }
}

/// How recovery indicators sit against the athlete's own recent range.
struct RecoverySignals: Equatable, Sendable {
    var baselines: [RecoveryMetricKey: PhysiologicalBaseline] = [:]
    var standings: [RecoveryMetricKey: BaselineStanding] = [:]

    var isEmpty: Bool { baselines.isEmpty }

    /// Indicators sitting outside their usual range, in either direction.
    ///
    /// Deliberately not summed into a recovery score: §61 forbids that, and the
    /// individual readings are what the athlete can actually act on.
    var outsideUsualRange: [RecoveryMetricKey] {
        standings.filter { $0.value != .withinRange }.map(\.key).sorted { $0.rawValue < $1.rawValue }
    }
}

/// Names the recovery metrics without depending on the data layer's enum.
enum RecoveryMetricKey: String, CaseIterable, Sendable {
    case restingHeartRate
    case heartRateVariability
    case sleepDuration
    case cardioFitness
    case heartRateRecovery
}

/// Which way each discipline is moving.
struct PerformanceSignals: Equatable, Sendable {
    var runningPace: IntelligenceValue<MetricTrend> = .unavailable
    var runningVolume: IntelligenceValue<MetricTrend> = .unavailable
    var swimmingLongestContinuous: IntelligenceValue<MetricTrend> = .unavailable
    var cyclingSpeed: IntelligenceValue<MetricTrend> = .unavailable

    var isEmpty: Bool {
        !runningPace.isAvailable && !runningVolume.isAvailable
            && !swimmingLongestContinuous.isAvailable && !cyclingSpeed.isAvailable
    }
}

/// Assembles the signals from completed sessions and recovery readings.
enum TrainingSignalsBuilder {

    static func build(
        weeks: [PlanWeekSessions],
        recovery: [RecoveryMetricKey: [RecoveryReading]],
        asOf now: Date,
        calendar: Calendar = .current
    ) -> TrainingSignals {
        let loads = weeks.compactMap { WeeklyTrainingLoad.load(for: $0).value }
        let sessions = weeks.flatMap(\.sessions)

        return TrainingSignals(
            workload: workload(from: loads),
            adherence: AdherenceSignals(outcomes: []),
            intensity: IntensitySignals(
                distribution: IntensityDistributionPolicy.distribution(for: sessions),
                balance: SportBalancePolicy.balance(of: sessions)
            ),
            recovery: recoverySignals(from: recovery, asOf: now, calendar: calendar),
            performance: performance(from: sessions, anchor: weeks.first?.startDate ?? now)
        )
    }

    private static func workload(from loads: [WeeklyLoad]) -> WorkloadSignals {
        let ordered = loads.sorted { $0.startDate < $1.startDate }
        let current = ordered.last
        let previous = ordered.dropLast().last

        return WorkloadSignals(
            currentWeek: IntelligenceValue(current?.total),
            previousWeek: IntelligenceValue(previous?.total),
            fourWeekAverage: WeeklyTrainingLoad.rollingAverage(of: ordered),
            weekOnWeekChange: WeeklyTrainingLoad.change(from: previous, to: current),
            bySport: current?.bySport ?? [:]
        )
    }

    private static func recoverySignals(
        from readings: [RecoveryMetricKey: [RecoveryReading]],
        asOf now: Date,
        calendar: Calendar
    ) -> RecoverySignals {
        var baselines: [RecoveryMetricKey: PhysiologicalBaseline] = [:]
        var standings: [RecoveryMetricKey: BaselineStanding] = [:]

        for (metric, values) in readings {
            guard let baseline = PhysiologicalBaselinePolicy.baseline(
                from: values,
                window: .sevenDay,
                asOf: now,
                calendar: calendar
            ).value else { continue }

            baselines[metric] = baseline
            if let standing = baseline.standing(
                tolerance: baseline.average * PhysiologicalBaselinePolicy.tolerance
            ) {
                standings[metric] = standing
            }
        }

        return RecoverySignals(baselines: baselines, standings: standings)
    }

    private static func performance(from sessions: [LoadedSession], anchor: Date) -> PerformanceSignals {
        PerformanceSignals(
            runningPace: RunningTrends.pace(sessions, anchoredTo: anchor),
            runningVolume: RunningTrends.weeklyDistance(sessions, anchoredTo: anchor),
            swimmingLongestContinuous: SwimmingTrends.longestContinuous(sessions, anchoredTo: anchor),
            cyclingSpeed: CyclingTrends.speed(sessions, anchoredTo: anchor)
        )
    }
}
