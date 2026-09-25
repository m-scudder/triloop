import Foundation

enum CapabilityEvidenceSource: String, Codable, CaseIterable, Sendable {
    case onboardingBaseline
    case currentPrescription
    case completedWorkout
    case healthKitImport
    case athleteConfirmation

    var displayName: String {
        switch self {
        case .onboardingBaseline: "Reported"
        case .currentPrescription: "Prescribed"
        case .completedWorkout: "Recorded"
        case .healthKitImport: "Demonstrated"
        case .athleteConfirmation: "Confirmed"
        }
    }
}

enum TrainingDirection: String, Codable, Sendable {
    case building
    case holding
    case reducing
    case recovering
}

enum CapabilityRecoveryState: String, Codable, Sendable {
    case stable
    case recovering
    case needsAttention
}

struct CapabilityMetric: Equatable, Sendable {
    var value: Double
    var source: CapabilityEvidenceSource
    var observedAt: Date?

    static func strongest(_ metrics: [CapabilityMetric]) -> CapabilityMetric? {
        metrics.max { lhs, rhs in
            if lhs.value == rhs.value {
                return Self.rank(lhs.source) < Self.rank(rhs.source)
            }
            return lhs.value < rhs.value
        }
    }

    private static func rank(_ source: CapabilityEvidenceSource) -> Int {
        switch source {
        case .onboardingBaseline: 0
        case .currentPrescription: 1
        case .completedWorkout: 2
        case .healthKitImport: 3
        case .athleteConfirmation: 4
        }
    }
}

struct RunningCapability: Equatable, Sendable {
    var reportedContinuousSeconds: TimeInterval?
    /// Conservative reference inferred from onboarding. It is reported evidence,
    /// never demonstrated capability.
    var reportedDistanceMeters: Double? = nil
    var prescribedContinuousSeconds: TimeInterval?
    var demonstratedContinuousSeconds: TimeInterval?
    var longestRecordedDistanceMeters: Double
    /// Average distance from recent recorded run sessions when available.
    var recentAverageDistanceMeters: Double = 0
    var recentDirection: TrainingDirection

    var currentContinuousSeconds: TimeInterval? {
        [reportedContinuousSeconds, prescribedContinuousSeconds, demonstratedContinuousSeconds]
            .compactMap { $0 }
            .max()
    }

    var hasContinuousCapability: Bool {
        (currentContinuousSeconds ?? 0) >= 10 * 60 || longestRecordedDistanceMeters >= 3_000
    }

    var hasDemonstratedCapability: Bool {
        demonstratedContinuousSeconds != nil || longestRecordedDistanceMeters > 0
    }
}

struct CyclingCapability: Equatable, Sendable {
    var reportedComfortableSeconds: TimeInterval
    /// Conservative reference inferred from onboarding. Recorded rides remain
    /// the authoritative distance evidence.
    var reportedDistanceMeters: Double = 0
    var prescribedWorkSeconds: TimeInterval
    var bestRecentDurationSeconds: TimeInterval
    var longestRecordedDistanceMeters: Double
    /// Average distance from recent recorded ride sessions when available.
    var recentAverageDistanceMeters: Double = 0
    var recentDirection: TrainingDirection

    var currentComfortableSeconds: TimeInterval {
        max(reportedComfortableSeconds, prescribedWorkSeconds, bestRecentDurationSeconds)
    }

    var hasDemonstratedCapability: Bool {
        bestRecentDurationSeconds > 0 || longestRecordedDistanceMeters > 0
    }
}

struct SwimmingCapability: Equatable, Sendable {
    var foundationState: SwimFoundationState
    var reportedContinuousMeters: Double?
    var prescribedRepeatMeters: Double
    var prescribedTotalWorkoutMeters: Double
    var longestProvenContinuousMeters: Double?
    var longestRecordedTotalWorkoutMeters: Double
    var openWaterExperience: Bool
    var recentDirection: TrainingDirection

    var currentContinuousMeters: Double? {
        [reportedContinuousMeters, longestProvenContinuousMeters]
            .compactMap { $0 }
            .max()
    }

    var hasVerifiedContinuousEvidence: Bool {
        longestProvenContinuousMeters != nil
    }

    var hasDemonstratedCapability: Bool {
        hasVerifiedContinuousEvidence || longestRecordedTotalWorkoutMeters > 0
    }
}

struct DistanceCapabilityComparison: Equatable, Sendable {
    var sport: Sport
    var baselineMeters: Double
    var recordedMeters: Double?

    var deltaMeters: Double? {
        recordedMeters.map { $0 - baselineMeters }
    }

    var recordedToBaselineRatio: Double? {
        guard baselineMeters > 0, let recordedMeters else { return nil }
        return recordedMeters / baselineMeters
    }
}

struct AthleteCapabilityAssessment: Equatable, Sendable {
    var running: RunningCapability
    var cycling: CyclingCapability
    var swimming: SwimmingCapability

    var recentCompletedSessions: Int
    var recentPlannedSessions: Int
    var recentMissedOrSkippedSessions: Int
    var recentAdherence: Double?
    var recoveryState: CapabilityRecoveryState
    var completedBrickCount: Int

    var hasRecentTrainingEvidence: Bool {
        recentCompletedSessions > 0
    }

    var hasDemonstratedCapabilityEvidence: Bool {
        running.hasDemonstratedCapability
            || cycling.hasDemonstratedCapability
            || swimming.hasDemonstratedCapability
    }

    func demonstratedDistanceMeters(for sport: Sport) -> Double {
        switch sport {
        case .running: running.longestRecordedDistanceMeters
        case .swimming: swimming.longestProvenContinuousMeters ?? 0
        case .cycling: cycling.longestRecordedDistanceMeters
        }
    }

    func currentDistanceMeters(for sport: Sport) -> Double {
        switch sport {
        case .running:
            return running.longestRecordedDistanceMeters
        case .swimming:
            return swimming.currentContinuousMeters ?? 0
        case .cycling:
            return cycling.longestRecordedDistanceMeters
        }
    }

    /// Compares onboarding distance with like-for-like recorded evidence.
    ///
    /// Running and cycling use a recent-session average when possible so one
    /// unusually long activity does not redefine the baseline comparison.
    /// Swimming compares reported continuous distance with proven continuous
    /// distance rather than mixing continuous ability with total workout volume.
    func distanceComparison(for sport: Sport) -> DistanceCapabilityComparison? {
        switch sport {
        case .running:
            guard let baseline = running.reportedDistanceMeters else { return nil }
            let recorded = running.recentAverageDistanceMeters > 0
                ? running.recentAverageDistanceMeters
                : (running.longestRecordedDistanceMeters > 0 ? running.longestRecordedDistanceMeters : nil)
            return DistanceCapabilityComparison(
                sport: .running,
                baselineMeters: baseline,
                recordedMeters: recorded
            )

        case .swimming:
            guard let baseline = swimming.reportedContinuousMeters else { return nil }
            return DistanceCapabilityComparison(
                sport: .swimming,
                baselineMeters: baseline,
                recordedMeters: swimming.longestProvenContinuousMeters
            )

        case .cycling:
            let recorded = cycling.recentAverageDistanceMeters > 0
                ? cycling.recentAverageDistanceMeters
                : (cycling.longestRecordedDistanceMeters > 0 ? cycling.longestRecordedDistanceMeters : nil)
            return DistanceCapabilityComparison(
                sport: .cycling,
                baselineMeters: cycling.reportedDistanceMeters,
                recordedMeters: recorded
            )
        }
    }

    func hasDemonstratedEvidence(for sport: Sport) -> Bool {
        switch sport {
        case .running: running.hasDemonstratedCapability
        case .swimming: swimming.hasDemonstratedCapability
        case .cycling: cycling.hasDemonstratedCapability
        }
    }
}

/// Shared interpretation of where the athlete is now.
///
/// The onboarding baseline is deliberately only one input. Once training
/// history exists, current prescriptions and completed/imported evidence are
/// evaluated alongside it so Journey, Progress and generation do not each
/// invent their own athlete state.
struct AthleteCapabilityAssessmentBuilder: Sendable {
    var calendar: Calendar = .current
    var recentWindowDays = 42

    func build(
        setup: AthleteSetup,
        plans: [WeeklyPlan],
        asOf date: Date = .now
    ) -> AthleteCapabilityAssessment {
        let orderedPlans = plans.sorted { $0.startDate < $1.startDate }
        let currentParameters = orderedPlans.last?.parameters ?? StartingParameterResolver().resolve(
            baseline: setup.baseline,
            goal: setup.goal,
            poolLengthMeters: 25
        )
        let previousParameters = orderedPlans.dropLast().last?.parameters

        let cutoff = calendar.date(byAdding: .day, value: -recentWindowDays, to: date) ?? .distantPast
        let allCompleted = orderedPlans
            .flatMap(\.trainingSessions)
            .filter(\.isCompleted)
        let recentCompleted = allCompleted.filter {
            ($0.completedAt ?? $0.date) >= cutoff && ($0.completedAt ?? $0.date) <= date
        }
        let recentPlanned = orderedPlans
            .flatMap(\.prescribedTrainingSessions)
            .filter { $0.date >= cutoff && $0.date <= date }

        let missedOrSkipped = recentPlanned.filter {
            $0.isSkipped || $0.isMissed(asOf: date, calendar: calendar)
        }.count

        let adherence: Double? = recentPlanned.isEmpty
            ? nil
            : Double(recentCompleted.filter { $0.origin.isPrescribedByAthevia }.count) / Double(recentPlanned.count)

        let recovery = recoveryState(from: recentCompleted)

        let multisportSegments = allCompleted.flatMap {
            $0.importedSummary?.metrics?.multisportSegments ?? []
        }
        let runSegments = multisportSegments.filter { $0.sport == .running }
        let cycleSegments = multisportSegments.filter { $0.sport == .cycling }
        let swimSegments = multisportSegments.filter { $0.sport == .swimming }

        let runImported = allCompleted
            .filter { $0.discipline == .running }
            .compactMap(\.importedSummary)
        let longestRun = max(
            runImported.compactMap(\.distanceMeters).max() ?? 0,
            runSegments.compactMap(\.distanceMeters).max() ?? 0
        )

        var continuousRunCandidates: [TimeInterval] = []
        for plan in orderedPlans {
            guard plan.parameters.runIsContinuous else { continue }
            for workout in plan.trainingSessions where workout.discipline == .running && workout.isCompleted {
                let prescribed = plan.parameters.runContinuousSeconds * workout.recordedCompletion
                continuousRunCandidates.append(prescribed)
            }
        }

        let swimImported = allCompleted
            .filter { $0.discipline == .swimming }
            .compactMap(\.importedSummary)
        let longestSwimContinuous = swimImported.compactMap(\.longestContinuousSwimMeters).max()
        let longestSwimTotal = max(
            swimImported.compactMap(\.distanceMeters).max() ?? 0,
            swimSegments.compactMap(\.distanceMeters).max() ?? 0
        )

        let cycleImported = allCompleted
            .filter { $0.discipline == .cycling }
            .compactMap(\.importedSummary)
        let longestRide = max(
            cycleImported.compactMap(\.distanceMeters).max() ?? 0,
            cycleSegments.compactMap(\.distanceMeters).max() ?? 0
        )
        let bestRideDuration = max(
            cycleImported.map(\.duration).max() ?? 0,
            cycleSegments.map(\.durationSeconds).max() ?? 0
        )

        let recentMultisportSegments = recentCompleted.flatMap {
            $0.importedSummary?.metrics?.multisportSegments ?? []
        }
        let recentRunDistances = recentCompleted
            .filter { $0.discipline == .running }
            .compactMap { $0.importedSummary?.distanceMeters }
            + recentMultisportSegments
                .filter { $0.sport == .running }
                .compactMap(\.distanceMeters)
        let recentRideDistances = recentCompleted
            .filter { $0.discipline == .cycling }
            .compactMap { $0.importedSummary?.distanceMeters }
            + recentMultisportSegments
                .filter { $0.sport == .cycling }
                .compactMap(\.distanceMeters)

        func average(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            return values.reduce(0, +) / Double(values.count)
        }

        let runDirection = direction(
            current: runLoad(currentParameters),
            previous: previousParameters.map(runLoad),
            recovery: recovery
        )
        let swimDirection = direction(
            current: swimLoad(currentParameters),
            previous: previousParameters.map(swimLoad),
            recovery: recovery
        )
        let cycleDirection = direction(
            current: cycleLoad(currentParameters),
            previous: previousParameters.map(cycleLoad),
            recovery: recovery
        )

        let reportedRunSeconds: TimeInterval? = switch setup.baseline.running {
        case .none, .runWalk: nil
        case .continuous10Minutes: 10 * 60
        case .continuous20To30Minutes: 20 * 60
        case .regular5K: 30 * 60
        }

        let currentSwimMeters = max(
            setup.baseline.swimming.continuousMeters ?? 0,
            longestSwimContinuous ?? 0
        )

        return AthleteCapabilityAssessment(
            running: RunningCapability(
                reportedContinuousSeconds: reportedRunSeconds,
                reportedDistanceMeters: setup.baseline.running.baselineDistanceMeters,
                prescribedContinuousSeconds: currentParameters.runIsContinuous
                    ? currentParameters.runContinuousSeconds
                    : nil,
                demonstratedContinuousSeconds: continuousRunCandidates.max(),
                longestRecordedDistanceMeters: longestRun,
                recentAverageDistanceMeters: average(recentRunDistances),
                recentDirection: runDirection
            ),
            cycling: CyclingCapability(
                reportedComfortableSeconds: TimeInterval(setup.baseline.cycling.comfortableMinutes * 60),
                reportedDistanceMeters: setup.baseline.cycling.baselineDistanceMeters,
                prescribedWorkSeconds: currentParameters.rideWorkSeconds,
                bestRecentDurationSeconds: bestRideDuration,
                longestRecordedDistanceMeters: longestRide,
                recentAverageDistanceMeters: average(recentRideDistances),
                recentDirection: cycleDirection
            ),
            swimming: SwimmingCapability(
                foundationState: SwimFoundationState(continuousMeters: currentSwimMeters),
                reportedContinuousMeters: setup.baseline.swimming.continuousMeters,
                prescribedRepeatMeters: currentParameters.swimRepeatDistanceMeters,
                prescribedTotalWorkoutMeters: currentParameters.swimTotalMeters,
                longestProvenContinuousMeters: longestSwimContinuous,
                longestRecordedTotalWorkoutMeters: longestSwimTotal,
                openWaterExperience: swimImported.contains {
                    $0.metrics?.swimEnvironment == .openWater
                } || swimSegments.contains {
                    $0.swimEnvironment == .openWater
                },
                recentDirection: swimDirection
            ),
            recentCompletedSessions: recentCompleted.count,
            recentPlannedSessions: recentPlanned.count,
            recentMissedOrSkippedSessions: missedOrSkipped,
            recentAdherence: adherence,
            recoveryState: recovery,
            completedBrickCount: allCompleted.filter { $0.isBrickWorkout }.count
        )
    }

    private func recoveryState(from workouts: [PlannedWorkout]) -> CapabilityRecoveryState {
        var state: CapabilityRecoveryState = .stable

        for workout in workouts {
            if let feedback = workout.feedback {
                if feedback.painScore >= 5 || !feedback.symptoms.isEmpty {
                    return .needsAttention
                }
                if feedback.painScore >= 3 || feedback.recoveryFeeling == .exhausted {
                    state = .recovering
                }
            }

            if let checkIn = workout.recoveryCheckIn {
                if checkIn.painScore >= 5 || !checkIn.symptoms.isEmpty || checkIn.soreness == .significant {
                    return .needsAttention
                }
                if checkIn.painScore >= 3 || checkIn.soreness == .moderate || checkIn.energy == .low {
                    state = .recovering
                }
            }
        }

        return state
    }

    private func direction(
        current: Double,
        previous: Double?,
        recovery: CapabilityRecoveryState
    ) -> TrainingDirection {
        if recovery != .stable { return .recovering }
        guard let previous else { return .holding }
        if current > previous * 1.02 { return .building }
        if current < previous * 0.98 { return .reducing }
        return .holding
    }

    private func runLoad(_ parameters: TrainingParameters) -> Double {
        parameters.runIsContinuous
            ? parameters.runContinuousSeconds
            : parameters.runIntervalSeconds * Double(parameters.runRepeatCount)
    }

    private func swimLoad(_ parameters: TrainingParameters) -> Double {
        parameters.swimTotalMeters + parameters.swimRepeatDistanceMeters
    }

    private func cycleLoad(_ parameters: TrainingParameters) -> Double {
        parameters.rideWorkSeconds
    }
}

extension SwimFoundationState {
    init(continuousMeters: Double) {
        switch continuousMeters {
        case ..<25: self = .waterComfort
        case 25..<50: self = .breathing
        case 50..<100: self = .shortContinuity
        case 100..<200: self = .continuous
        default: self = .endurance
        }
    }
}

extension PlannedWorkout {
    /// Temporary bridge for legacy brick rows. New brick generation uses
    /// explicit multisport semantics; existing completed history must remain
    /// readable so capability/milestone derivation recognizes the old title.
    var isBrickWorkout: Bool {
        if discipline == .multisport { return true }
        return title == "Bike + Run Brick"
    }
}
