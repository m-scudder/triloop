import Foundation

/// One tile in At a Glance.
struct GlanceTile: Equatable, Identifiable {
    enum Slot: String {
        case sessions
        case training
        case intensity
        case adherence
        case recovery
        case history
    }

    let slot: Slot
    let value: String
    let label: String

    var id: String { slot.rawValue }
}

/// The week so far, in four tiles.
///
/// Sessions and training time are fixed because they mean something in every
/// week. The other two slots are chosen: an indicator sitting outside its usual
/// range is worth more than a distribution, and a figure is withheld entirely
/// rather than shown before the evidence supports it.
enum TodayGlanceBuilder {

    /// Below this, an "adherence" percentage is one session's completion
    /// wearing a weekly label.
    static let minimumSessionsForAdherence = 2

    /// Share of training time one band needs before the week has a character
    /// rather than a mixture.
    static let dominantIntensityShare = 0.6

    static func tiles(
        plan: WeeklyPlan?,
        sessions: [LoadedSession],
        recovery: RecoverySignals = RecoverySignals()
    ) -> [GlanceTile] {
        guard let plan else { return [] }

        let training = plan.trainingSessions
        guard !training.isEmpty else { return [] }

        let reported = training.filter(\.hasReport)

        return [
            GlanceTile(
                slot: .sessions,
                value: "\(reported.count) / \(training.count)",
                label: "Sessions"
            ),
            GlanceTile(
                slot: .training,
                value: TrainingFormatter.totalDuration(seconds: trainingSeconds(of: reported)),
                label: "Training"
            ),
            recoveryTile(recovery) ?? intensityTile(sessions) ?? buildingTile,
            adherenceTile(reported) ?? buildingTile
        ]
    }

    // MARK: - Tiles

    /// §61 forbids compositing indicators into a single recovery score, so the
    /// tile names the indicator it is actually reporting.
    ///
    /// Ordered by how much the reading can be acted on today rather than
    /// alphabetically: a resting heart rate above range changes what an athlete
    /// does this morning, a shifted cardio fitness estimate does not.
    private static let recoveryPriority: [RecoveryMetricKey] = [
        .restingHeartRate,
        .heartRateVariability,
        .sleepDuration,
        .heartRateRecovery,
        .cardioFitness
    ]

    private static func recoveryTile(_ recovery: RecoverySignals) -> GlanceTile? {
        let flagged = Set(recovery.outsideUsualRange)
        guard let metric = recoveryPriority.first(where: flagged.contains),
              let standing = recovery.standings[metric],
              standing != .withinRange
        else { return nil }

        return GlanceTile(
            slot: .recovery,
            value: standing == .below ? "Below Range" : "Above Range",
            label: shortName(of: metric)
        )
    }

    private static func intensityTile(_ sessions: [LoadedSession]) -> GlanceTile? {
        guard let distribution = IntensityDistributionPolicy.distribution(for: sessions).value,
              distribution.totalSeconds > 0,
              let dominant = WorkoutIntensity.allCases.max(by: {
                  distribution.share($0) < distribution.share($1)
              })
        else { return nil }

        let value = distribution.share(dominant) >= dominantIntensityShare
            ? "Mostly \(dominant.rawValue.capitalized)"
            : "Mixed"

        return GlanceTile(slot: .intensity, value: value, label: "Intensity")
    }

    private static func adherenceTile(_ reported: [PlannedWorkout]) -> GlanceTile? {
        guard reported.count >= minimumSessionsForAdherence else { return nil }

        let mean = reported.map(\.recordedCompletion).reduce(0, +) / Double(reported.count)
        let percent = Int((min(mean, 1) * 100).rounded())

        return GlanceTile(slot: .adherence, value: "\(percent)%", label: "Adherence")
    }

    /// The honest filler: the week has not yet produced the figure.
    private static var buildingTile: GlanceTile {
        GlanceTile(slot: .history, value: "Building", label: "History")
    }

    // MARK: - Helpers

    private static func trainingSeconds(of reported: [PlannedWorkout]) -> TimeInterval {
        reported
            .compactMap { $0.importedSummary?.duration ?? $0.estimatedDurationSeconds }
            .reduce(0, +)
    }

    private static func shortName(of metric: RecoveryMetricKey) -> String {
        switch metric {
        case .restingHeartRate: "Resting HR"
        case .heartRateVariability: "HRV"
        case .sleepDuration: "Sleep"
        case .cardioFitness: "Cardio Fitness"
        case .heartRateRecovery: "HR Recovery"
        }
    }
}
