import Foundation

/// Where the athlete currently stands in each sport.
///
/// This is what TriLoop knows that a workout log cannot: not what you have done,
/// but what you are currently prescribed and which way it is moving.
struct CurrentTraining: Equatable, Sendable {
    struct SportState: Equatable, Sendable, Identifiable {
        let sport: Sport
        /// The prescription in one line, e.g. "1:15 run / 2:00 walk × 6".
        let prescription: String
        /// Direction from the most recently reported week, if there is one.
        let status: AssessmentStatus?

        var id: Sport { sport }
    }

    var weekNumber: Int
    var states: [SportState] = []

    var hasData: Bool { !states.isEmpty }
}

extension CurrentTraining {
    /// Built from the newest plan's parameters, with direction taken from the
    /// most recent week that was actually reported on.
    init?(plans: [WeeklyPlan]) {
        guard let latest = plans.max(by: { $0.weekNumber < $1.weekNumber }) else { return nil }

        let lastReported = plans
            .filter { $0.trainingSessions.contains(where: \.hasReport) }
            .max(by: { $0.weekNumber < $1.weekNumber })
        let analysis = lastReported.map { WeeklyAnalyser().analyse($0) }

        let parameters = latest.parameters
        let prescribed = Set(latest.trainingSessions.compactMap { $0.discipline.sport })

        weekNumber = latest.weekNumber
        states = Sport.allCases
            .filter { prescribed.contains($0) }
            .map { sport in
                SportState(
                    sport: sport,
                    prescription: Self.prescription(for: sport, parameters: parameters),
                    status: analysis?.analysis(for: sport)?.status
                )
            }
    }

    private static func prescription(for sport: Sport, parameters: TrainingParameters) -> String {
        switch sport {
        case .running:
            if parameters.runIsContinuous {
                return "\(TrainingFormatter.totalDuration(seconds: parameters.runContinuousSeconds)) continuous"
            }
            let run = TrainingFormatter.intervalDuration(seconds: parameters.runIntervalSeconds)
            let walk = TrainingFormatter.intervalDuration(seconds: parameters.runWalkSeconds)
            return "\(parameters.runRepeatCount) × \(run) run / \(walk) walk"

        case .swimming:
            let rest = Int(parameters.swimRestSeconds)
            return "\(TrainingFormatter.distance(meters: parameters.swimTotalMeters)) · \(rest)s rest"

        case .cycling:
            let total = parameters.rideWarmUpSeconds + parameters.rideWorkSeconds + parameters.rideCooldownSeconds
            return TrainingFormatter.totalDuration(seconds: total)
        }
    }
}

extension AssessmentStatus {
    var directionSymbol: String {
        switch self {
        case .progress: "arrow.up.right"
        case .maintain: "arrow.right"
        case .reduce: "arrow.down.right"
        case .recoveryRequired: "pause"
        }
    }

    var directionLabel: String {
        switch self {
        case .progress: "Building"
        case .maintain: "Holding"
        case .reduce: "Easing back"
        case .recoveryRequired: "Recovering"
        }
    }
}
