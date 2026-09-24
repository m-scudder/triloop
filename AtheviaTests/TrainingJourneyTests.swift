import Foundation
import Testing

@testable import Athevia

@Suite("Training journey")
struct TrainingJourneyTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return value
    }

    private func date(_ year: Int = 2026, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func setup(
        sport: EventSport,
        distance: EventDistance,
        date eventDate: Date,
        baseline: AthleteBaseline,
        sports: [Sport]
    ) -> AthleteSetup {
        AthleteSetup(
            objective: .event(sport: sport, distance: distance, eventDate: eventDate),
            baseline: baseline,
            schedule: .everyDay(),
            preferences: sports.map { SportPreference(sport: $0, sessionsPerWeek: 1) },
            stage: .complete,
            completedAt: date(9, 1)
        )
    }

    @Test("Beginner first 5K at ten weeks stays in foundation with run walk focus")
    func beginner5K() {
        let athlete = setup(
            sport: .running,
            distance: EventDistance(kind: .run5K),
            date: date(12, 3),
            baseline: AthleteBaseline(running: .runWalk),
            sports: [.running]
        )
        let journey = TrainingJourneyPlanner(calendar: calendar)
            .plan(setup: athlete, asOf: date(9, 24))

        #expect(journey.phase == .foundation)
        #expect(journey.sportPriorities.first?.sport == .running)
        #expect(journey.primaryFocus?.kind == .runWalkContinuity)
        #expect(journey.weeklyObjectives.contains(where: { $0.kind == .racePacing }) == false)
    }

    @Test("Existing 5K athlete preparing for first 10K builds endurance")
    func first10K() {
        let athlete = setup(
            sport: .running,
            distance: EventDistance(kind: .run10K),
            date: date(11, 19),
            baseline: AthleteBaseline(running: .regular5K),
            sports: [.running]
        )
        let journey = TrainingJourneyPlanner(calendar: calendar)
            .plan(setup: athlete, recentPlans: [SeedWeekOne.makePlan()], asOf: date(9, 24))

        #expect(journey.phase == .build)
        #expect(journey.primaryFocus?.kind == .endurance)
        #expect(journey.primaryFocus?.kind != .runWalkContinuity)
    }

    @Test("Sprint triathlon with weak swim prioritises swimming")
    func weakSwimmerSprint() {
        let athlete = setup(
            sport: .triathlon,
            distance: EventDistance(kind: .triathlonSprint),
            date: date(11, 19),
            baseline: AthleteBaseline(
                running: .regular5K,
                swimming: .continuous50,
                cycling: .fortyFiveToSixty
            ),
            sports: [.running, .swimming, .cycling]
        )
        let journey = TrainingJourneyPlanner(calendar: calendar)
            .plan(setup: athlete, asOf: date(9, 24))

        #expect(journey.phase == .foundation)
        #expect(journey.sportPriorities.first?.sport == .swimming)
        #expect(journey.weeklyObjectives.first?.kind == .swimContinuity)
    }

    @Test("Strong swimmer and weak runner reverses priorities")
    func weakRunnerSprint() {
        let athlete = setup(
            sport: .triathlon,
            distance: EventDistance(kind: .triathlonSprint),
            date: date(11, 19),
            baseline: AthleteBaseline(
                running: .runWalk,
                swimming: .continuous200Plus,
                cycling: .sixtyPlus
            ),
            sports: [.running, .swimming, .cycling]
        )
        let journey = TrainingJourneyPlanner(calendar: calendar)
            .plan(setup: athlete, asOf: date(9, 24))

        #expect(journey.sportPriorities.first?.sport == .running)
        #expect(journey.primaryFocus?.kind == .runWalkContinuity)
    }

    @Test("Race proximity changes phase but never produces a progression override")
    func raceProximity() {
        let athlete = setup(
            sport: .running,
            distance: EventDistance(kind: .run5K),
            date: date(9, 28),
            baseline: AthleteBaseline(running: .regular5K),
            sports: [.running]
        )
        let journey = TrainingJourneyPlanner(calendar: calendar)
            .plan(setup: athlete, asOf: date(9, 24))

        #expect(journey.phase == .raceWeek)
        #expect(journey.primaryFocus?.kind == .taper)

        let safety = TrainingSafetyPolicy().evaluate(
            FeedbackSummary(
                WorkoutFeedback(rpe: 5, painScore: 7, recoveryFeeling: .okay)
            )
        )
        guard case .requiresRecovery = safety else {
            Issue.record("Safety must remain authoritative near an event")
            return
        }
    }

    @Test("Changing event date recalculates journey without touching completed plan")
    func dateChange() {
        let completed = SeedWeekOne.makePlan()
        let session = completed.trainingSessions.first!
        session.recordCompletion(with: FeedbackDraft(rpe: 4, painScore: 0))
        let completedAt = session.completedAt

        var athlete = setup(
            sport: .running,
            distance: EventDistance(kind: .run10K),
            date: date(10, 8),
            baseline: AthleteBaseline(running: .regular5K),
            sports: [.running]
        )
        let planner = TrainingJourneyPlanner(calendar: calendar)
        let near = planner.plan(setup: athlete, asOf: date(9, 24))

        athlete.objective = .event(
            sport: .running,
            distance: EventDistance(kind: .run10K),
            eventDate: date(12, 17)
        )
        let far = planner.plan(setup: athlete, asOf: date(9, 24))

        #expect(near.phase != far.phase)
        #expect(session.completedAt == completedAt)
        #expect(session.isCompleted)
    }
}
