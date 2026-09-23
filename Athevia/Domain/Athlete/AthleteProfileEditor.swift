import Foundation

/// Why an edit reaches beyond the profile.
enum ProfileEditReason: String, Equatable, CaseIterable, Sendable {
    case goal
    case event
    case eventDate
    case targetIntent
    case runningBaseline
    case swimmingBaseline
    case swimStroke
    case cyclingBaseline
    case availability
    case weeklyCommitment

    var displayName: String {
        switch self {
        case .goal: "Training goal"
        case .event: "Event"
        case .eventDate: "Event date"
        case .targetIntent: "Event target"
        case .runningBaseline: "Running ability"
        case .swimmingBaseline: "Swimming ability"
        case .swimStroke: "Stroke"
        case .cyclingBaseline: "Cycling ability"
        case .availability: "Training days"
        case .weeklyCommitment: "How often you train"
        }
    }
}

/// What an edit means for training that has already been prescribed.
enum ProfileEditImpact: Equatable, Sendable {
    /// Saves immediately and changes nothing already planned.
    case safe
    /// Changes what Athevia would prescribe from now on.
    case trainingImpacting([ProfileEditReason])

    var isTrainingImpacting: Bool { self != .safe }

    var reasons: [ProfileEditReason] {
        switch self {
        case .safe: []
        case .trainingImpacting(let reasons): reasons
        }
    }
}

/// Decides whether a profile edit is a preference or a training change.
///
/// §10.1.1.11: the distinction lives here rather than in the view, so two
/// screens cannot disagree about whether an edit needs the athlete's consent
/// before the week ahead is rebuilt.
///
/// Deliberately says nothing about applying the change. Rebuilding is the
/// existing plan logic's job; this only names the consequence.
enum AthleteProfileEditor {

    static func impact(from old: AthleteSetup, to new: AthleteSetup) -> ProfileEditImpact {
        var reasons: [ProfileEditReason] = []

        if old.objective.kind != new.objective.kind {
            reasons.append(.goal)
        } else if old.objective.kind == .event {
            let oldEvent = old.objective.event
            let newEvent = new.objective.event

            if oldEvent?.sport != newEvent?.sport || oldEvent?.distance != newEvent?.distance {
                reasons.append(.event)
            }
            if oldEvent?.eventDate != newEvent?.eventDate {
                reasons.append(.eventDate)
            }
            if oldEvent?.targetIntent != newEvent?.targetIntent {
                reasons.append(.targetIntent)
            }
        }

        if old.baseline.running != new.baseline.running { reasons.append(.runningBaseline) }
        if old.baseline.swimming != new.baseline.swimming { reasons.append(.swimmingBaseline) }
        if old.baseline.stroke != new.baseline.stroke { reasons.append(.swimStroke) }
        if old.baseline.cycling != new.baseline.cycling { reasons.append(.cyclingBaseline) }

        if old.schedule.availableDays.map(\.weekday) != new.schedule.availableDays.map(\.weekday) {
            reasons.append(.availability)
        }

        if commitment(old) != commitment(new) { reasons.append(.weeklyCommitment) }

        // Date of birth only anchors heart-rate zones, and the stage the athlete
        // reached is bookkeeping. Neither changes what is prescribed.
        return reasons.isEmpty ? .safe : .trainingImpacting(reasons)
    }

    /// Sessions asked for per sport, ignoring the order they happen to be stored in.
    private static func commitment(_ setup: AthleteSetup) -> [Sport: Int] {
        setup.preferences.reduce(into: [:]) { totals, preference in
            totals[preference.sport] = preference.sessionsPerWeek
        }
    }
}
