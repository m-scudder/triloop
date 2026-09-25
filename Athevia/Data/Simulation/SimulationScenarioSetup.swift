#if DEBUG
import Foundation

extension SimulationDataset {
    /// Optional profile state paired with a health fixture so Journey/Progress
    /// scenarios can be reviewed immediately instead of waiting through weeks
    /// of real training.
    func scenarioSetup(
        asOf date: Date = .now,
        calendar: Calendar = .current
    ) -> AthleteSetup? {
        func eventDate(days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: date) ?? date
        }

        let triBaseline = AthleteBaseline(
            running: .runWalk,
            swimming: .continuous25,
            cycling: .twentyToThirty
        )
        let triPreferences = Sport.allCases.map {
            SportPreference(sport: $0, sessionsPerWeek: 2)
        }

        switch self {
        case .event5KDeveloping:
            return AthleteSetup(
                objective: .event(
                    sport: .running,
                    distance: EventDistance(kind: .run5K),
                    eventDate: eventDate(days: 70),
                    targetIntent: .finishComfortably
                ),
                baseline: AthleteBaseline(running: .none),
                schedule: .everyDay(),
                preferences: [SportPreference(sport: .running, sessionsPerWeek: 3)],
                stage: .complete
            )

        case .progressedRunner:
            return AthleteSetup(
                objective: .event(
                    sport: .running,
                    distance: EventDistance(kind: .run10K),
                    eventDate: eventDate(days: 56)
                ),
                baseline: AthleteBaseline(running: .runWalk),
                schedule: .everyDay(),
                preferences: [SportPreference(sport: .running, sessionsPerWeek: 3)],
                stage: .complete
            )

        case .sprintTriSwimGap:
            return AthleteSetup(
                objective: .event(
                    sport: .triathlon,
                    distance: EventDistance(kind: .triathlonSprint),
                    eventDate: eventDate(days: 56)
                ),
                baseline: triBaseline,
                schedule: .everyDay(),
                preferences: triPreferences,
                stage: .complete
            )

        case .sprintTriBrickComplete, .sprintTriSpecificBrick:
            return AthleteSetup(
                objective: .event(
                    sport: .triathlon,
                    distance: EventDistance(kind: .triathlonSprint),
                    eventDate: eventDate(days: 28)
                ),
                baseline: triBaseline,
                schedule: .everyDay(),
                preferences: triPreferences,
                stage: .complete
            )

        case .sprintTriEventReady:
            return AthleteSetup(
                objective: .event(
                    sport: .triathlon,
                    distance: EventDistance(kind: .triathlonSprint),
                    eventDate: eventDate(days: 21)
                ),
                baseline: triBaseline,
                schedule: .everyDay(),
                preferences: triPreferences,
                stage: .complete
            )

        case .sprintTriRecoveryProblem:
            return AthleteSetup(
                objective: .event(
                    sport: .triathlon,
                    distance: EventDistance(kind: .triathlonSprint),
                    eventDate: eventDate(days: 14)
                ),
                baseline: triBaseline,
                schedule: .everyDay(),
                preferences: triPreferences,
                stage: .complete
            )

        case .eventTaper:
            return AthleteSetup(
                objective: .event(
                    sport: .running,
                    distance: EventDistance(kind: .run10K),
                    eventDate: eventDate(days: 12)
                ),
                baseline: AthleteBaseline(running: .regular5K),
                schedule: .everyDay(),
                preferences: [SportPreference(sport: .running, sessionsPerWeek: 4)],
                stage: .complete
            )

        case .eventRaceWeek:
            return AthleteSetup(
                objective: .event(
                    sport: .running,
                    distance: EventDistance(kind: .run5K),
                    eventDate: eventDate(days: 5)
                ),
                baseline: AthleteBaseline(running: .regular5K),
                schedule: .everyDay(),
                preferences: [SportPreference(sport: .running, sessionsPerWeek: 3)],
                stage: .complete
            )

        case .eventPostRace:
            return AthleteSetup(
                objective: .event(
                    sport: .running,
                    distance: EventDistance(kind: .run10K),
                    eventDate: eventDate(days: -1)
                ),
                eventState: AthleteEventState(
                    status: .completed,
                    resolvedAt: eventDate(days: -1),
                    completionEvidence: .athleteConfirmation
                ),
                baseline: AthleteBaseline(running: .regular5K),
                schedule: .everyDay(),
                preferences: [SportPreference(sport: .running, sessionsPerWeek: 3)],
                stage: .complete
            )

        case .eventMissed:
            return AthleteSetup(
                objective: .event(
                    sport: .running,
                    distance: EventDistance(kind: .run5K),
                    eventDate: eventDate(days: -1)
                ),
                eventState: AthleteEventState(
                    status: .missed,
                    resolvedAt: date
                ),
                baseline: AthleteBaseline(running: .regular5K),
                schedule: .everyDay(),
                preferences: [SportPreference(sport: .running, sessionsPerWeek: 3)],
                stage: .complete
            )

        case .generalFitness:
            return AthleteSetup(
                objective: TrainingObjective(kind: .generalFitness),
                baseline: AthleteBaseline(
                    running: .continuous20To30Minutes,
                    cycling: .fortyFiveToSixty
                ),
                schedule: .everyDay(),
                preferences: [
                    SportPreference(sport: .running, sessionsPerWeek: 3),
                    SportPreference(sport: .cycling, sessionsPerWeek: 3)
                ],
                stage: .complete
            )

        case .openWaterReady:
            return AthleteSetup(
                objective: .event(
                    sport: .triathlon,
                    distance: EventDistance(kind: .triathlonSprint),
                    eventDate: eventDate(days: 28)
                ),
                openWaterTrainingConsent: OpenWaterTrainingConsent(
                    explicitlyConfirmed: true,
                    hasSafeVenue: true,
                    hasSupervisionOrBuddy: true
                ),
                baseline: AthleteBaseline(
                    running: .regular5K,
                    swimming: .continuous200Plus,
                    cycling: .sixtyPlus
                ),
                schedule: .everyDay(),
                preferences: triPreferences,
                stage: .complete
            )

        case .openWaterDisabled:
            return AthleteSetup(
                objective: .event(
                    sport: .triathlon,
                    distance: EventDistance(kind: .triathlonSprint),
                    eventDate: eventDate(days: 28)
                ),
                openWaterTrainingConsent: .unavailable,
                baseline: AthleteBaseline(
                    running: .regular5K,
                    swimming: .continuous200Plus,
                    cycling: .sixtyPlus
                ),
                schedule: .everyDay(),
                preferences: triPreferences,
                stage: .complete
            )

        case .event5KCompleted:
            return AthleteSetup(
                objective: .event(
                    sport: .running,
                    distance: EventDistance(kind: .run5K),
                    eventDate: eventDate(days: -1)
                ),
                eventState: AthleteEventState(
                    status: .completed,
                    resolvedAt: eventDate(days: -1),
                    completionEvidence: .athleteConfirmation
                ),
                baseline: AthleteBaseline(running: .runWalk),
                schedule: .everyDay(),
                preferences: [SportPreference(sport: .running, sessionsPerWeek: 3)],
                stage: .complete
            )

        default:
            return nil
        }
    }
}
#endif
