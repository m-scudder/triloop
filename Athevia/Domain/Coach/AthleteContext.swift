import Foundation

enum CoachEvidenceKind: String, Codable, Equatable, Sendable {
    case measured
    case estimated
    case userReported
    case planned
}

enum CoachHealthAccess: String, Codable, Equatable, Sendable {
    case unavailable
    case notDetermined
    case denied
    case authorized

    init(_ status: HealthAuthorizationStatus) {
        switch status {
        case .unavailable: self = .unavailable
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized: self = .authorized
        }
    }
}

struct CoachAvailabilityContext: Codable, Equatable, Sendable {
    let weekday: Weekday
    let isAvailable: Bool
    let maxDurationMinutes: Int?
}

struct CoachBaselineContext: Codable, Equatable, Sendable {
    let assessedAt: Date
    let runningDescription: String
    let runningReferenceMeters: Double?
    let swimmingContinuousMeters: Double?
    let cyclingComfortableMinutes: Int
    let cyclingReferenceMeters: Double

    let evidenceKind: CoachEvidenceKind = .userReported
}

struct CoachSportCapabilityContext: Codable, Equatable, Sendable {
    let sport: Sport
    let baselineMeters: Double?
    let recentBestMeters: Double?
    let recentAverageMeters: Double?
    let lifetimeBestMeters: Double?
    /// Meaningful only for swimming; never mixes time and distance units.
    let recentContinuousMeters: Double?
    /// Meaningful for time-based demonstrated capability such as running/cycling.
    let recentDurationSeconds: TimeInterval?
    let evidenceKind: CoachEvidenceKind
}

struct CoachCapabilityContext: Codable, Equatable, Sendable {
    let sports: [CoachSportCapabilityContext]
    let recentCompletedSessions: Int
    let recentPlannedSessions: Int
    let recentMissedOrSkippedSessions: Int
    let recentAdherence: Double?
    let recoveryState: String
    let capabilityWindowDays: Int
    let readinessStatus: String
    let readinessReasons: [String]
}

struct CoachWeekHistoryContext: Codable, Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    let plannedSessions: Int
    let completedSessions: Int
    let skippedOrMissedSessions: Int
    let completedDurationSeconds: TimeInterval
    let completedDistanceMetersBySport: [String: Double]
}

struct CoachHealthWorkoutEvidence: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let sport: Sport
    let startDate: Date
    let endDate: Date
    let durationSeconds: TimeInterval
    let distanceMeters: Double?
    let longestContinuousSwimMeters: Double?
    let source: String?
    let evidenceKind: CoachEvidenceKind

    init(_ workout: ImportedWorkout) {
        id = workout.healthKitUUID
        sport = workout.sport
        startDate = workout.startDate
        endDate = workout.endDate
        durationSeconds = workout.duration
        distanceMeters = workout.distanceMeters
        longestContinuousSwimMeters = workout.longestContinuousSwimMeters
        source = workout.source
        evidenceKind = .measured
    }
}

struct CoachRecoveryEvidence: Codable, Equatable, Sendable, Identifiable {
    let metric: String
    let value: Double
    let unit: String
    let observedAt: Date
    let sampleCount: Int
    let source: String
    let evidenceKind: CoachEvidenceKind

    var id: String { metric }
}

/// A bounded, timestamped view of the evidence the conversation is allowed to
/// use. It deliberately contains aggregates and short recent records, never GPS
/// routes, free-form feedback notes, complete HealthKit history or unrelated
/// personal information.
struct AthleteContextSnapshot: Codable, Equatable, Sendable {
    let athleteScopeID: String
    let generatedAt: Date
    let windowStart: Date
    let windowEnd: Date
    let trainingObjective: TrainingObjective
    let experienceLevel: ExperienceLevel
    let baseline: CoachBaselineContext
    let availableSports: [Sport]
    let availability: [CoachAvailabilityContext]
    let capability: CoachCapabilityContext
    let recentWeeks: [CoachWeekHistoryContext]
    let recentHealthWorkouts: [CoachHealthWorkoutEvidence]
    let recoveryEvidence: [CoachRecoveryEvidence]
    let healthAccess: CoachHealthAccess
    let caveats: [String]

    /// Fingerprint only the evidence and constraints, not the moment the
    /// snapshot object happened to be rebuilt. A fresh Apply check should stay
    /// valid when the underlying evidence is unchanged, while any real evidence
    /// or plan-context change still invalidates the preview.
    var version: String {
        struct EvidenceVersionPayload: Codable {
            let athleteScopeID: String
            let trainingObjective: TrainingObjective
            let experienceLevel: ExperienceLevel
            let baseline: CoachBaselineContext
            let availableSports: [Sport]
            let availability: [CoachAvailabilityContext]
            let capability: CoachCapabilityContext
            let recentWeeks: [CoachWeekHistoryContext]
            let recentHealthWorkouts: [CoachHealthWorkoutEvidence]
            let recoveryEvidence: [CoachRecoveryEvidence]
            let healthAccess: CoachHealthAccess
            let caveats: [String]
        }

        return CoachStableFingerprint.value(
            for: EvidenceVersionPayload(
                athleteScopeID: athleteScopeID,
                trainingObjective: trainingObjective,
                experienceLevel: experienceLevel,
                baseline: baseline,
                availableSports: availableSports,
                availability: availability,
                capability: capability,
                recentWeeks: recentWeeks,
                recentHealthWorkouts: recentHealthWorkouts,
                recoveryEvidence: recoveryEvidence,
                healthAccess: healthAccess,
                caveats: caveats
            )
        )
    }

    var evidencePeriodLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(formatter.string(from: windowStart)) – \(formatter.string(from: windowEnd))"
    }
}

struct AthleteContextBuilder: Sendable {
    var calendar: Calendar = .current
    var historyWindowDays = 28
    var capabilityWindowDays = 42
    var maximumHealthWorkoutRecords = 24

    func build(
        profile: AthleteProfile,
        plans: [WeeklyPlan],
        healthWorkouts: [ImportedWorkout] = [],
        recoveryEvidence: [CoachRecoveryEvidence] = [],
        healthAccess: CoachHealthAccess,
        retrievalFailed: Bool = false,
        asOf now: Date = .now
    ) -> AthleteContextSnapshot? {
        guard let setup = profile.setup else { return nil }

        let windowEnd = now
        let windowStart = calendar.date(
            byAdding: .day,
            value: -historyWindowDays,
            to: now
        ) ?? .distantPast

        var capabilityBuilder = AthleteCapabilityAssessmentBuilder()
        capabilityBuilder.calendar = calendar
        capabilityBuilder.recentWindowDays = capabilityWindowDays
        let assessment = capabilityBuilder.build(
            setup: setup,
            plans: plans,
            asOf: now
        )
        let journey = TrainingJourneyPlanner(calendar: calendar).plan(
            setup: setup,
            capability: assessment,
            asOf: now
        )

        let sportContexts: [CoachSportCapabilityContext] = [
            CoachSportCapabilityContext(
                sport: .running,
                baselineMeters: assessment.running.reportedDistanceMeters,
                recentBestMeters: positive(assessment.running.recentBestDistanceMeters),
                recentAverageMeters: positive(assessment.running.recentAverageDistanceMeters),
                lifetimeBestMeters: positive(assessment.running.longestRecordedDistanceMeters),
                recentContinuousMeters: nil,
                recentDurationSeconds: assessment.running.demonstratedContinuousSeconds,
                evidenceKind: assessment.running.recentBestDistanceMeters > 0 ? .measured : .userReported
            ),
            CoachSportCapabilityContext(
                sport: .swimming,
                baselineMeters: assessment.swimming.reportedContinuousMeters,
                recentBestMeters: assessment.swimming.recentLongestProvenContinuousMeters,
                recentAverageMeters: nil,
                lifetimeBestMeters: assessment.swimming.longestProvenContinuousMeters,
                recentContinuousMeters: assessment.swimming.recentLongestProvenContinuousMeters,
                recentDurationSeconds: nil,
                evidenceKind: assessment.swimming.recentLongestProvenContinuousMeters != nil ? .measured : .userReported
            ),
            CoachSportCapabilityContext(
                sport: .cycling,
                baselineMeters: assessment.cycling.reportedDistanceMeters,
                recentBestMeters: positive(assessment.cycling.recentBestDistanceMeters),
                recentAverageMeters: positive(assessment.cycling.recentAverageDistanceMeters),
                lifetimeBestMeters: positive(assessment.cycling.longestRecordedDistanceMeters),
                recentContinuousMeters: nil,
                recentDurationSeconds: positive(assessment.cycling.bestRecentDurationSeconds),
                evidenceKind: assessment.cycling.recentBestDistanceMeters > 0 ? .measured : .userReported
            )
        ]

        let weeks = plans
            .filter { $0.endDate >= windowStart && $0.startDate <= windowEnd }
            .sorted { $0.startDate < $1.startDate }
            .map { weekContext($0, asOf: now) }

        let boundedHealth = healthWorkouts
            .filter { $0.endDate >= windowStart && $0.startDate <= windowEnd }
            .sorted { $0.startDate > $1.startDate }
            .prefix(maximumHealthWorkoutRecords)
            .map(CoachHealthWorkoutEvidence.init)

        var caveats: [String] = []
        if healthAccess != .authorized {
            caveats.append("Apple Health history is not available to the coach, so explanations use Athevia's stored plan and feedback history.")
        } else if retrievalFailed {
            caveats.append("Apple Health was authorized, but recent health evidence could not be refreshed for this conversation.")
        }
        if boundedHealth.isEmpty {
            caveats.append("No recent Apple Health workouts were available in the selected history window.")
        }
        if recoveryEvidence.isEmpty {
            caveats.append("No current sleep, HRV, or resting-heart-rate readings are being used.")
        }

        let readinessReasons = journey.readiness.sports
            .flatMap(\.gaps)
            .map(\.message)

        return AthleteContextSnapshot(
            athleteScopeID: profile.id.uuidString,
            generatedAt: now,
            windowStart: windowStart,
            windowEnd: windowEnd,
            trainingObjective: setup.objective,
            experienceLevel: profile.experienceLevel,
            baseline: CoachBaselineContext(
                assessedAt: setup.baseline.assessedAt,
                runningDescription: setup.baseline.running.displayName,
                runningReferenceMeters: setup.baseline.running.baselineDistanceMeters,
                swimmingContinuousMeters: setup.baseline.swimming.continuousMeters,
                cyclingComfortableMinutes: setup.baseline.cycling.comfortableMinutes,
                cyclingReferenceMeters: setup.baseline.cycling.baselineDistanceMeters
            ),
            availableSports: setup.selectedSports,
            availability: Weekday.trainingWeek.map {
                let day = setup.schedule.availability(on: $0)
                return CoachAvailabilityContext(
                    weekday: $0,
                    isAvailable: day.isAvailable,
                    maxDurationMinutes: day.maxDurationMinutes
                )
            },
            capability: CoachCapabilityContext(
                sports: sportContexts,
                recentCompletedSessions: assessment.recentCompletedSessions,
                recentPlannedSessions: assessment.recentPlannedSessions,
                recentMissedOrSkippedSessions: assessment.recentMissedOrSkippedSessions,
                recentAdherence: assessment.recentAdherence,
                recoveryState: assessment.recoveryState.rawValue,
                capabilityWindowDays: capabilityWindowDays,
                readinessStatus: journey.readiness.status.rawValue,
                readinessReasons: readinessReasons
            ),
            recentWeeks: weeks,
            recentHealthWorkouts: Array(boundedHealth),
            recoveryEvidence: recoveryEvidence.sorted { $0.metric < $1.metric },
            healthAccess: healthAccess,
            caveats: caveats
        )
    }

    private func weekContext(_ plan: WeeklyPlan, asOf now: Date) -> CoachWeekHistoryContext {
        let planned = plan.prescribedTrainingSessions
        let completed = planned.filter(\.isCompleted)
        let skippedOrMissed = planned.filter {
            $0.isSkipped || $0.isMissed(asOf: now, calendar: calendar)
        }

        var distances: [String: Double] = [:]
        for workout in completed {
            guard let sport = workout.discipline.sport else { continue }
            let measured = workout.importedSummary?.distanceMeters
            if let measured {
                distances[sport.rawValue, default: 0] += measured
            }
        }

        return CoachWeekHistoryContext(
            startDate: plan.startDate,
            endDate: plan.endDate,
            plannedSessions: planned.count,
            completedSessions: completed.count,
            skippedOrMissedSessions: skippedOrMissed.count,
            completedDurationSeconds: completed.compactMap {
                $0.importedSummary?.duration ?? $0.estimatedDurationSeconds
            }.reduce(0, +),
            completedDistanceMetersBySport: distances
        )
    }

    private func positive(_ value: Double) -> Double? {
        value > 0 ? value : nil
    }
}

@MainActor
struct AthleteContextLoader {
    var provider: any HealthDataProviding
    var builder: AthleteContextBuilder = AthleteContextBuilder()
    var calendar: Calendar = .current

    func load(
        profile: AthleteProfile,
        plans: [WeeklyPlan],
        asOf now: Date = .now
    ) async -> AthleteContextSnapshot? {
        let status = await provider.authorizationStatus
        let access = CoachHealthAccess(status)
        let start = calendar.date(byAdding: .day, value: -builder.historyWindowDays, to: now)
            ?? .distantPast

        var workouts: [ImportedWorkout] = []
        var recovery: [CoachRecoveryEvidence] = []
        var retrievalFailed = false

        if status == .authorized {
            do {
                workouts = try await provider.workouts(from: start, to: now)
            } catch {
                retrievalFailed = true
            }

            for metric in [RecoveryMetric.sleepDuration, .heartRateVariability, .restingHeartRate] {
                do {
                    let points = try await provider.recoverySeries(metric, from: start, to: now)
                        .sorted { $0.date < $1.date }
                    if let latest = points.last {
                        recovery.append(
                            CoachRecoveryEvidence(
                                metric: metric.rawValue,
                                value: latest.value,
                                unit: metric.unitLabel,
                                observedAt: latest.date,
                                sampleCount: points.count,
                                source: "Apple Health",
                                evidenceKind: .measured
                            )
                        )
                    }
                } catch {
                    retrievalFailed = true
                }
            }
        }

        return builder.build(
            profile: profile,
            plans: plans,
            healthWorkouts: workouts,
            recoveryEvidence: recovery,
            healthAccess: access,
            retrievalFailed: retrievalFailed,
            asOf: now
        )
    }
}
