import Foundation

enum AssessmentStatus: String, Codable, CaseIterable, Sendable {
    case progress
    case maintain
    case reduce
    case recoveryRequired

    var displayName: String {
        switch self {
        case .progress: "Progress"
        case .maintain: "Maintain"
        case .reduce: "Reduce"
        case .recoveryRequired: "Recovery required"
        }
    }

    /// Ascending caution. A week takes the most conservative status any of its
    /// sessions produced, so one bad run cannot be averaged away by a good one.
    var caution: Int {
        switch self {
        case .progress: 0
        case .maintain: 1
        case .reduce: 2
        case .recoveryRequired: 3
        }
    }
}

/// Why an assessment landed where it did.
///
/// Structured rather than pre-rendered strings so the future explanation layer
/// receives facts to narrate instead of prose to re-parse.
enum AssessmentReason: Equatable, Sendable {
    case completedAsPrescribed
    case sessionIncomplete(completion: Double)
    case sessionLargelyMissed(completion: Double)
    case effortComfortable(rpe: Int)
    case effortElevated(rpe: Int)
    case effortTooHigh(rpe: Int)
    case noPainReported
    case painReported(score: Int)
    case painRequiresEvaluation(score: Int)
    case recoveryAcceptable(RecoveryFeeling)
    case recoveryIncomplete(RecoveryFeeling)
    case warningSymptom(WarningSymptom)
    case sessionsMissed(count: Int)
    case nextDayPain(score: Int)
    case lingeringSoreness(SorenessLevel)
    case lowEnergyNextDay(EnergyLevel)
    case recoveredOvernight

    var summary: String {
        switch self {
        case .completedAsPrescribed:
            "Completed the session as prescribed"
        case .sessionIncomplete(let completion):
            "Completed \(Self.percent(completion)) of the session"
        case .sessionLargelyMissed(let completion):
            "Only \(Self.percent(completion)) of the session was completed"
        case .effortComfortable(let rpe):
            "Effort was comfortable at \(rpe)/10"
        case .effortElevated(let rpe):
            "Effort was elevated at \(rpe)/10"
        case .effortTooHigh(let rpe):
            "Effort reached \(rpe)/10"
        case .noPainReported:
            "No pain reported"
        case .painReported(let score):
            "Pain reported at \(score)/10"
        case .painRequiresEvaluation(let score):
            "Pain reached \(score)/10"
        case .recoveryAcceptable(let feeling):
            "Recovery was \(feeling.displayName.lowercased())"
        case .recoveryIncomplete(let feeling):
            "Recovery was \(feeling.displayName.lowercased())"
        case .warningSymptom(let symptom):
            "\(symptom.displayName) was reported"
        case .sessionsMissed(let count):
            count == 1 ? "One session was not completed" : "\(count) sessions were not completed"
        case .nextDayPain(let score):
            "Pain the next day was \(score)/10"
        case .lingeringSoreness(let level):
            "\(level.displayName) soreness the next day"
        case .lowEnergyNextDay(let level):
            "Energy the next day was \(level.displayName.lowercased())"
        case .recoveredOvernight:
            "Recovered well overnight"
        }
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

/// A single change to a single training variable.
///
/// Modelled as an enum with one case per lever so §13's "change one primary
/// variable at a time" cannot be violated by construction.
enum TrainingAdjustment: Equatable, Sendable {
    /// Repeat the same workload. Named `hold` rather than `none` so it never
    /// collides with `Optional.none` at a use site.
    case hold
    /// Lengthen or shorten the running interval, leaving the count and walk recovery alone.
    case runIntervalDuration(deltaSeconds: TimeInterval)
    /// Shorten the walk between running intervals, leaving the running alone.
    case runWalkDuration(deltaSeconds: TimeInterval)
    /// Drop the walk breaks entirely and run the session as one block.
    case graduateToContinuousRun
    case runContinuousDuration(deltaSeconds: TimeInterval)
    case rideDuration(deltaSeconds: TimeInterval)
    /// Tighten rest between swim repeats before touching distance.
    case swimRestDuration(deltaSeconds: TimeInterval)
    case swimVolume(deltaMeters: Double)
    case reduceVolume(fraction: Double)
    case substituteRecovery

    var summary: String {
        switch self {
        case .hold:
            "Repeat a similar workload"
        case .runIntervalDuration(let delta):
            "\(Self.signed(Int(delta)))s per running interval"
        case .runWalkDuration(let delta):
            "\(Self.signed(Int(delta)))s of walking between intervals"
        case .graduateToContinuousRun:
            "Run continuously, without walk breaks"
        case .runContinuousDuration(let delta):
            "\(Self.signed(Int(delta / 60))) min of continuous running"
        case .rideDuration(let delta):
            "\(Self.signed(Int(delta / 60))) min of riding"
        case .swimRestDuration(let delta):
            "\(Self.signed(Int(delta)))s rest between repeats"
        case .swimVolume(let delta):
            "\(Self.signed(Int(delta))) m of swimming"
        case .reduceVolume(let fraction):
            "Reduce volume by \(Int((fraction * 100).rounded()))%"
        case .substituteRecovery:
            "Replace with recovery"
        }
    }

    private static func signed(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }
}

struct WorkoutAssessment: Equatable, Sendable {
    let sport: Sport
    let status: AssessmentStatus
    let reasons: [AssessmentReason]
    let adjustment: TrainingAdjustment

    var recommendsHarderTraining: Bool {
        status == .progress
    }
}
