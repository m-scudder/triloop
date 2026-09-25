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
    case progressedRunner
    case sprintTriSwimGap
    case sprintTriBrickComplete
    case sprintTriEventReady
    case sprintTriRecoveryProblem
    case sprintTriSpecificBrick
    case eventTaper
    case eventRaceWeek
    case eventPostRace
    case eventMissed
    case generalFitness
    case openWaterReady
    case openWaterDisabled
    case highAvailabilityBeginner
    case highAvailabilityExperienced
    case returningRunner
    case poolMismatchBeginner
    case firstWeekSpecificEvent
    case firstWeekEventDay

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
        case .progressedRunner: "Progressed Runner — Baseline Superseded"
        case .sprintTriSwimGap: "Sprint Tri — 750 m Total / 100 m Continuous"
        case .sprintTriBrickComplete: "Sprint Tri — Brick Complete"
        case .sprintTriEventReady: "Sprint Tri — Demonstrated Event Capability"
        case .sprintTriRecoveryProblem: "Sprint Tri — Recovery Problem"
        case .sprintTriSpecificBrick: "Sprint Tri — Specific Phase Brick"
        case .eventTaper: "Event — Taper"
        case .eventRaceWeek: "Event — Race Week"
        case .eventPostRace: "Event — Completed + Recovery"
        case .eventMissed: "Event — Missed"
        case .generalFitness: "General Fitness — No Event"
        case .openWaterReady: "Sprint Tri — Open Water Enabled"
        case .openWaterDisabled: "Sprint Tri — Open Water Disabled"
        case .highAvailabilityBeginner: "Capacity — Beginner / 6 Available Days"
        case .highAvailabilityExperienced: "Capacity — Experienced / 6 Available Days"
        case .returningRunner: "Returning Runner — Lifetime 10K / Recent Short"
        case .poolMismatchBeginner: "Swim Safety — 25 m Ability / 50 m Pool"
        case .firstWeekSpecificEvent: "Week 1 — Specific Phase"
        case .firstWeekEventDay: "Week 1 — Event Inside Week"
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
        case .progressedRunner: "Started as run/walk; recorded running now exceeds 5 km."
        case .sprintTriSwimGap: "750 m total swim volume but only 100 m verified continuous, with stronger bike/run evidence."
        case .sprintTriBrickComplete: "Includes a real multisport bike-transition-run activity."
        case .sprintTriEventReady: "Run, bike and continuous swim requirements plus a completed brick are all demonstrated."
        case .sprintTriRecoveryProblem: "Strong event history paired with poor recovery signals for safety review."
        case .sprintTriSpecificBrick: "Specific-phase triathlon evidence intended to surface brick and race-specific sessions."
        case .eventTaper: "Mature event history suitable for inspecting taper-state screens."
        case .eventRaceWeek: "Mature event history with an event inside seven days."
        case .eventPostRace: "Confirmed event scenario for bounded post-event recovery and next-goal UI."
        case .eventMissed: "Past event scenario explicitly marked missed; no completion milestone should appear."
        case .generalFitness: "Non-event training history for current focus and progression UI."
        case .openWaterReady: "Strong swim continuity with explicit safe-venue and buddy consent."
        case .openWaterDisabled: "Strong swim continuity but open-water consent remains disabled; pool work only."
        case .highAvailabilityBeginner: "Six available days with beginner baselines; training capacity should leave recovery days."
        case .highAvailabilityExperienced: "The same six available days with established baselines; more slots may carry training."
        case .returningRunner: "Preserves an old 10K while recent runs stay near 3–4 km for conservative readiness."
        case .poolMismatchBeginner: "Reports 25 m continuous swimming while the debug profile uses a 50 m pool."
        case .firstWeekSpecificEvent: "Opening profile is already inside the event-specific phase so Week 1 must be phase-aware."
        case .firstWeekEventDay: "A 5K falls inside the opening week and must replace the normal/recovery slot on that date."
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
        case .event5KCompleted, .progressedRunner: 8
        case .sprintTriSwimGap, .sprintTriBrickComplete, .sprintTriEventReady,
             .sprintTriRecoveryProblem, .sprintTriSpecificBrick, .openWaterReady,
             .openWaterDisabled: 8
        case .eventTaper, .eventRaceWeek: 10
        case .eventPostRace: 12
        case .eventMissed: 8
        case .generalFitness: 6
        case .highAvailabilityBeginner, .highAvailabilityExperienced,
             .poolMismatchBeginner, .firstWeekSpecificEvent, .firstWeekEventDay: 1
        case .returningRunner: 12
        }
    }

    var hasHeartRate: Bool { self != .missingHeartRate && self != .noData }

    var hasPower: Bool {
        switch self {
        case .experiencedRunner, .experiencedTriathlete, .powerCyclist, .highLoad,
             .sprintTriBrickComplete, .sprintTriEventReady, .sprintTriSpecificBrick: true
        default: false
        }
    }

    /// Running dynamics need a recent watch, so most fixtures do without them.
    var hasRunningDynamics: Bool {
        switch self {
        case .experiencedRunner, .experiencedTriathlete, .event5KCompleted, .progressedRunner,
             .eventTaper, .eventRaceWeek, .eventPostRace: true
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
        case .experiencedRunner, .event5KDeveloping, .event5KCompleted, .progressedRunner,
             .eventTaper, .eventRaceWeek, .eventPostRace, .eventMissed, .returningRunner,
             .firstWeekSpecificEvent, .firstWeekEventDay, .highAvailabilityBeginner,
             .highAvailabilityExperienced: [.running]
        case .powerCyclist, .missingPower: [.cycling]
        case .poolMismatchBeginner: [.swimming]
        case .beginnerFirstWeek, .sparseHistory: [.running, .swimming]
        case .generalFitness: [.running, .cycling]
        default: [.running, .swimming, .cycling]
        }
    }
}
#endif
