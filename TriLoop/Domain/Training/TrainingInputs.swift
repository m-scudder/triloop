import Foundation

/// A symptom that is never a training-load problem to be progressed around.
///
/// Not currently collected by the feedback sheet. The type exists now so the
/// safety policy can be written and tested against it, and so surfacing it in
/// the UI later is additive rather than a redesign.
enum WarningSymptom: String, Codable, CaseIterable, Sendable {
    case radiatingPain
    case numbness
    case weakness
    case dizziness
    case chestDiscomfort

    var displayName: String {
        switch self {
        case .radiatingPain: "Radiating pain"
        case .numbness: "Numbness"
        case .weakness: "Weakness"
        case .dizziness: "Dizziness"
        case .chestDiscomfort: "Chest discomfort"
        }
    }
}

/// What actually happened in a session, normalized away from any framework.
///
/// Phase 3 populates this by hand or from a completed `PlannedWorkout`. Phase 5
/// will populate the same type from HealthKit, so the engine never learns that
/// HealthKit exists.
struct WorkoutResult: Equatable, Sendable {
    let sport: Sport
    /// Share of the prescribed work actually completed, 0...1.
    let completion: Double
    let durationSeconds: TimeInterval?
    let distanceMeters: Double?
    let averageHeartRate: Double?
    /// Rest prescribed between intervals. Drives the swimming lever, which
    /// tightens rest before adding volume, and the running walk break.
    let prescribedRestSeconds: TimeInterval?
    /// Length of one running interval. `nil` once running is continuous, which
    /// is how the engine knows the walk breaks are already gone.
    let prescribedIntervalSeconds: TimeInterval?
    /// Distance of one swim repeat, so the engine knows whether continuity has
    /// room to grow before volume does.
    let prescribedRepeatDistanceMeters: Double?

    init(
        sport: Sport,
        completion: Double,
        durationSeconds: TimeInterval? = nil,
        distanceMeters: Double? = nil,
        averageHeartRate: Double? = nil,
        prescribedRestSeconds: TimeInterval? = nil,
        prescribedIntervalSeconds: TimeInterval? = nil,
        prescribedRepeatDistanceMeters: Double? = nil
    ) {
        self.sport = sport
        // Over-completion is still just "finished it" as far as triage is concerned.
        self.completion = min(max(completion, 0), 1)
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.prescribedRestSeconds = prescribedRestSeconds
        self.prescribedIntervalSeconds = prescribedIntervalSeconds
        self.prescribedRepeatDistanceMeters = prescribedRepeatDistanceMeters
    }
}

/// Value snapshot of a `WorkoutFeedback`, so the engine stays free of SwiftData.
///
/// `notes` is carried for the future explanation layer but is deliberately not
/// interpreted by any rule: scanning free text for symptoms misreads negations
/// such as "no dizziness".
struct FeedbackSummary: Equatable, Sendable {
    let rpe: Int
    let painScore: Int
    let painLocations: Set<PainLocation>
    let recoveryFeeling: RecoveryFeeling
    let symptoms: Set<WarningSymptom>
    let notes: String

    init(
        rpe: Int,
        painScore: Int = 0,
        painLocations: Set<PainLocation> = [],
        recoveryFeeling: RecoveryFeeling = .good,
        symptoms: Set<WarningSymptom> = [],
        notes: String = ""
    ) {
        self.rpe = min(max(rpe, RPEScale.minimum), RPEScale.maximum)
        self.painScore = min(max(painScore, PainScale.minimum), PainScale.maximum)
        self.painLocations = painLocations
        self.recoveryFeeling = recoveryFeeling
        self.symptoms = symptoms
        self.notes = notes
    }
}

extension FeedbackSummary {
    init(_ feedback: WorkoutFeedback) {
        self.init(
            rpe: feedback.rpe,
            painScore: feedback.painScore,
            painLocations: Set(feedback.painLocations),
            recoveryFeeling: feedback.recoveryFeeling,
            symptoms: Set(feedback.symptoms),
            notes: feedback.notes
        )
    }
}

/// How the athlete was the day after a session.
///
/// Optional everywhere it is used: a skipped check-in must never be read as a
/// good one.
struct RecoverySummary: Equatable, Sendable {
    let painScore: Int
    let soreness: SorenessLevel
    let energy: EnergyLevel
    let symptoms: Set<WarningSymptom>

    init(
        painScore: Int = 0,
        soreness: SorenessLevel = .none,
        energy: EnergyLevel = .normal,
        symptoms: Set<WarningSymptom> = []
    ) {
        self.painScore = min(max(painScore, PainScale.minimum), PainScale.maximum)
        self.soreness = soreness
        self.energy = energy
        self.symptoms = symptoms
    }
}

extension RecoverySummary {
    init(_ checkIn: RecoveryCheckIn) {
        self.init(
            painScore: checkIn.painScore,
            soreness: checkIn.soreness,
            energy: checkIn.energy,
            symptoms: Set(checkIn.symptoms)
        )
    }
}
