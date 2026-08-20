import Foundation

/// Everything known about one completed session, normalized.
///
/// The single input to every intelligence calculation. Whether a session came
/// from a plan, an import or the historical browser, it arrives here in the
/// same shape — which is what stops the same workout being read differently
/// depending on which screen is asking.
struct WorkoutEvidence: Equatable, Sendable {
    let date: Date
    let sport: Sport
    let durationSeconds: TimeInterval?
    let distanceMeters: Double?
    let averageHeartRate: Double?
    /// Empty when no series was recorded or none was fetched.
    let heartRateSamples: [HeartRateReading]
    let longestContinuousSwimMeters: Double?
    let metrics: RecordedMetrics
    let effort: EffortEvidence

    // Prescription, absent for a workout that no plan asked for.
    let plannedDurationSeconds: TimeInterval?
    let targetRPE: RPERange?
    let completion: ExecutionComparison.Completion

    init(
        date: Date,
        sport: Sport,
        durationSeconds: TimeInterval? = nil,
        distanceMeters: Double? = nil,
        averageHeartRate: Double? = nil,
        heartRateSamples: [HeartRateReading] = [],
        longestContinuousSwimMeters: Double? = nil,
        metrics: RecordedMetrics = RecordedMetrics(),
        effort: EffortEvidence = EffortEvidence(),
        plannedDurationSeconds: TimeInterval? = nil,
        targetRPE: RPERange? = nil,
        completion: ExecutionComparison.Completion = .recorded
    ) {
        self.date = date
        self.sport = sport
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.heartRateSamples = heartRateSamples
        self.longestContinuousSwimMeters = longestContinuousSwimMeters
        self.metrics = metrics
        self.effort = effort
        self.plannedDurationSeconds = plannedDurationSeconds
        self.targetRPE = targetRPE
        self.completion = completion
    }
}

/// What the intelligence layer concluded about one session.
struct WorkoutInterpretation: Equatable, Sendable {
    let zones: HeartRateZoneBreakdown?
    let intensity: IntelligenceValue<WorkoutIntensityReading>
    let load: IntelligenceValue<SessionLoad>
    let adherence: ExecutionComparison.Outcome?
}

/// The one place a workout is interpreted.
///
/// Every caller — workout detail, Progress, the historical browser,
/// `TrainingSignalsBuilder` — routes through here, so §3's contract holds: the
/// same evidence always produces the same zones, intensity, load and adherence.
enum WorkoutIntelligence {

    static func interpret(
        _ evidence: WorkoutEvidence,
        maximumHeartRate: Double?,
        zoneSource: HeartRateZoneSource = .ageBasedMaximum
    ) -> WorkoutInterpretation {
        let zones = zoneBreakdown(
            for: evidence,
            maximumHeartRate: maximumHeartRate,
            source: zoneSource
        )

        // Time in zone is the strongest evidence; an average is a fallback used
        // only when no series was recorded.
        let intensity = WorkoutIntensityPolicy.intensity(
            zones: zones,
            effort: evidence.effort,
            averageHeartRate: zones == nil ? evidence.averageHeartRate : nil,
            maximumHeartRate: maximumHeartRate
        )

        let load = SessionLoadPolicy.load(
            durationSeconds: evidence.durationSeconds,
            zones: zones,
            effort: evidence.effort,
            intensity: intensity.value?.intensity
        )

        let adherence = ExecutionComparison.compare(
            plannedSeconds: evidence.plannedDurationSeconds,
            actualSeconds: evidence.durationSeconds,
            targetRPE: evidence.targetRPE,
            reportedRPE: evidence.effort.reportedRPE,
            completion: evidence.completion
        )

        return WorkoutInterpretation(
            zones: zones,
            intensity: intensity,
            load: load,
            adherence: adherence
        )
    }

    /// Nil when there is no series to measure or no ceiling to measure against.
    static func zoneBreakdown(
        for evidence: WorkoutEvidence,
        maximumHeartRate: Double?,
        source: HeartRateZoneSource
    ) -> HeartRateZoneBreakdown? {
        guard let maximumHeartRate, evidence.heartRateSamples.count > 1 else { return nil }

        return HeartRateZoneCalculator(
            maximumHeartRate: maximumHeartRate,
            source: source
        )
        .breakdown(from: evidence.heartRateSamples)
    }

    /// Turns an interpreted session into the aggregation input.
    static func session(from evidence: WorkoutEvidence, interpretation: WorkoutInterpretation) -> LoadedSession {
        LoadedSession(
            date: evidence.date,
            sport: evidence.sport,
            load: interpretation.load.value,
            durationSeconds: evidence.durationSeconds,
            intensity: interpretation.intensity.value?.intensity,
            distanceMeters: evidence.distanceMeters,
            averageHeartRate: evidence.averageHeartRate,
            longestContinuousSwimMeters: evidence.longestContinuousSwimMeters,
            metrics: evidence.metrics
        )
    }
}
