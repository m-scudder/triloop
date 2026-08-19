#if DEBUG
import Foundation

/// A complete, controlled health history.
///
/// Everything a fixture produces lives here, so the provider is a lookup rather
/// than a generator and the same dataset always answers identically.
struct SimulatedHealthData: Sendable {
    var workouts: [ImportedWorkout] = []
    /// Time series per workout, keyed by the workout's identifier.
    var samples: [UUID: WorkoutSamples] = [:]
    var dailySteps: [SamplePoint] = []
    var hourlySteps: [SamplePoint] = []
    var recovery: [RecoveryMetric: [SamplePoint]] = [:]
    var authorization: HealthAuthorizationStatus = .authorized

    var workoutCount: Int { workouts.count }
}

/// The controlled histories Phase 9 is developed against.
///
/// Each is a named situation rather than a random sample, so a screenshot, a
/// test failure and a bug report all refer to the same data.
enum SimulationDataset: String, CaseIterable, Identifiable, Sendable {
    case noData
    case beginnerFirstWeek
    case beginnerFourWeeks
    case beginnerTwelveWeeks
    case experiencedRunner
    case experiencedTriathlete
    case powerCyclist
    case partialData
    case missingHeartRate
    case missingPower
    case sparseHistory
    case highLoad
    case poorRecovery
    case conflictingSignals

    var id: Self { self }

    var displayName: String {
        switch self {
        case .noData: "No Data"
        case .beginnerFirstWeek: "Beginner — First Week"
        case .beginnerFourWeeks: "Beginner — 4 Weeks"
        case .beginnerTwelveWeeks: "Beginner — 12 Weeks"
        case .experiencedRunner: "Experienced Runner"
        case .experiencedTriathlete: "Experienced Triathlete — 12 Weeks"
        case .powerCyclist: "Cyclist With Power Meter"
        case .partialData: "Partial Health Data"
        case .missingHeartRate: "Missing Heart Rate"
        case .missingPower: "Missing Power"
        case .sparseHistory: "Sparse History"
        case .highLoad: "High Training Load"
        case .poorRecovery: "Poor Recovery"
        case .conflictingSignals: "Conflicting Signals"
        }
    }

    var detail: String {
        switch self {
        case .noData: "Empty Health history."
        case .beginnerFirstWeek: "Run/walk, 25 m swim repeats, short rides."
        case .beginnerFourWeeks: "Realistic beginner progression with a missed session."
        case .beginnerTwelveWeeks: "The canonical beginner fixture for trends and baselines."
        case .experiencedRunner: "Longer continuous runs across several intensities."
        case .experiencedTriathlete: "The canonical advanced fixture across all three sports."
        case .powerCyclist: "Cycling with cadence and power."
        case .partialData: "Workouts and heart rate, but no HRV, sleep or power."
        case .missingHeartRate: "Workouts and RPE only — intensity must fall back."
        case .missingPower: "Advanced cycling without power or FTP."
        case .sparseHistory: "Too little history to trend."
        case .highLoad: "A sharp week-on-week load rise."
        case .poorRecovery: "Rising resting HR, falling HRV and sleep."
        case .conflictingSignals: "Easy heart rate against a high reported effort."
        }
    }

    /// Weeks of history the fixture covers.
    var weeks: Int {
        switch self {
        case .noData: 0
        case .sparseHistory: 1
        case .beginnerFirstWeek: 1
        case .beginnerFourWeeks, .missingHeartRate, .missingPower, .conflictingSignals: 4
        case .partialData, .poorRecovery: 4
        case .highLoad: 8
        case .beginnerTwelveWeeks, .experiencedRunner, .experiencedTriathlete, .powerCyclist: 12
        }
    }

    var hasHeartRate: Bool { self != .missingHeartRate && self != .noData }

    var hasPower: Bool {
        switch self {
        case .experiencedRunner, .experiencedTriathlete, .powerCyclist, .highLoad: true
        default: false
        }
    }

    /// Running dynamics need a recent watch, so most fixtures do without them.
    var hasRunningDynamics: Bool {
        switch self {
        case .experiencedRunner, .experiencedTriathlete: true
        default: false
        }
    }

    /// Apple's effort score is absent where the fixture is testing RPE fallback.
    var hasEffortScore: Bool {
        switch self {
        case .noData, .missingHeartRate, .partialData, .sparseHistory: false
        default: true
        }
    }

    /// §40's recovery metrics. Partial-data fixtures deliberately lack them.
    func provides(_ metric: RecoveryMetric) -> Bool {
        switch self {
        case .noData:
            false
        case .partialData:
            // Workouts and heart rate, but nothing about recovery.
            false
        case .sparseHistory:
            metric == .restingHeartRate
        case .missingHeartRate:
            metric == .sleepDuration
        default:
            true
        }
    }

    /// Recovery readings are kept even for short fixtures, so a baseline can be
    /// tested against a history longer than the training itself.
    var recoveryDays: Int {
        switch self {
        case .noData: 0
        case .sparseHistory: 5
        default: max(weeks * 7, 28)
        }
    }

    var sports: [Sport] {
        switch self {
        case .noData: []
        case .experiencedRunner: [.running]
        case .powerCyclist, .missingPower: [.cycling]
        case .beginnerFirstWeek, .sparseHistory: [.running, .swimming]
        default: [.running, .swimming, .cycling]
        }
    }
}
#endif
