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
    case event5KDeveloping
    case event5KCompleted
    case sprintTriSwimGap
    case sprintTriBrickComplete
    case eventTaper
    case eventPostRace

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
        case .event5KDeveloping: "Event — 5K Developing"
        case .event5KCompleted: "Event — First 5K Complete"
        case .sprintTriSwimGap: "Sprint Tri — Swim Gap"
        case .sprintTriBrickComplete: "Sprint Tri — Brick Complete"
        case .eventTaper: "Event — Taper"
        case .eventPostRace: "Event — Post Race"
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
        case .event5KDeveloping: "Running history builds toward 5 km without demonstrating it yet."
        case .event5KCompleted: "Contains a completed 5 km run for capability and milestone checks."
        case .sprintTriSwimGap: "Triathlon history where swim continuity trails run and bike capability."
        case .sprintTriBrickComplete: "Triathlon history with bike/run evidence for brick and milestone UI."
        case .eventTaper: "Mature event history suitable for inspecting taper-state screens."
        case .eventPostRace: "Completed event-distance history suitable for post-event recovery screens."
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
        case .event5KDeveloping: 6
        case .event5KCompleted: 8
        case .sprintTriSwimGap, .sprintTriBrickComplete: 8
        case .eventTaper: 10
        case .eventPostRace: 12
        }
    }

    var hasHeartRate: Bool { self != .missingHeartRate && self != .noData }

    var hasPower: Bool {
        switch self {
        case .experiencedRunner, .experiencedTriathlete, .powerCyclist, .highLoad, .sprintTriBrickComplete: true
        default: false
        }
    }

    /// Running dynamics need a recent watch, so most fixtures do without them.
    var hasRunningDynamics: Bool {
        switch self {
        case .experiencedRunner, .experiencedTriathlete, .event5KCompleted, .eventTaper, .eventPostRace: true
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
        case .experiencedRunner, .event5KDeveloping, .event5KCompleted, .eventTaper, .eventPostRace: [.running]
        case .powerCyclist, .missingPower: [.cycling]
        case .beginnerFirstWeek, .sparseHistory: [.running, .swimming]
        default: [.running, .swimming, .cycling]
        }
    }
}
#endif
