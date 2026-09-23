import Foundation
import Testing

@testable import Athevia

@Suite("Training objective and event model")
struct TrainingObjectiveTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }

    @Test("Every legacy goal decodes into a valid structured objective")
    func legacyGoalsDecode() throws {
        let cases: [(String, TrainingObjectiveKind, EventSport?)] = [
            ("generalFitness", .generalFitness, nil),
            ("firstTriathlon", .event, .triathlon),
            ("improveEndurance", .improveEndurance, nil),
            ("returnToTraining", .returnToTraining, nil)
        ]

        for (rawGoal, expectedKind, expectedSport) in cases {
            let data = Data(#"{"goal":"\#(rawGoal)"}"#.utf8)
            let setup = try JSONDecoder().decode(AthleteSetup.self, from: data)

            #expect(setup.objective.kind == expectedKind)
            #expect(setup.objective.event?.sport == expectedSport)
            #expect(setup.goal.rawValue == rawGoal)
        }
    }

    @Test("Legacy first triathlon remains valid without event details")
    func legacyTriathlonAllowsUnknownDetails() throws {
        let data = Data(#"{"goal":"firstTriathlon"}"#.utf8)
        let setup = try JSONDecoder().decode(AthleteSetup.self, from: data)

        #expect(setup.objective.kind == .event)
        #expect(setup.objective.event?.sport == .triathlon)
        #expect(setup.objective.event?.distance == nil)
        #expect(setup.objective.event?.eventDate == nil)
    }

    @Test("Standard running distances carry actual metres")
    func runningDistances() {
        #expect(EventDistance(kind: .run5K).components.runMeters == 5_000)
        #expect(EventDistance(kind: .run10K).components.runMeters == 10_000)
        #expect(EventDistance(kind: .runHalfMarathon).components.runMeters == 21_097.5)
        #expect(EventDistance(kind: .runMarathon).components.runMeters == 42_195)
    }

    @Test("Standard triathlon distances carry all three components")
    func triathlonDistances() {
        let sprint = EventDistance(kind: .triathlonSprint).components
        #expect(sprint.swimMeters == 750)
        #expect(sprint.bikeMeters == 20_000)
        #expect(sprint.runMeters == 5_000)

        let olympic = EventDistance(kind: .triathlonOlympic).components
        #expect(olympic.swimMeters == 1_500)
        #expect(olympic.bikeMeters == 40_000)
        #expect(olympic.runMeters == 10_000)

        let half = EventDistance(kind: .triathlon703).components
        #expect(half.swimMeters == 1_900)
        #expect(half.bikeMeters == 90_000)
        #expect(half.runMeters == 21_097.5)
    }

    @Test("Cycling and swimming standard distances carry actual metres")
    func cyclingAndSwimmingDistances() {
        #expect(EventDistance(kind: .cycling20K).components.bikeMeters == 20_000)
        #expect(EventDistance(kind: .cycling50K).components.bikeMeters == 50_000)
        #expect(EventDistance(kind: .cycling100K).components.bikeMeters == 100_000)
        #expect(EventDistance(kind: .swimming500M).components.swimMeters == 500)
        #expect(EventDistance(kind: .swimming1K).components.swimMeters == 1_000)
        #expect(EventDistance(kind: .swimming2K).components.swimMeters == 2_000)
    }

    @Test("Custom event distances preserve structured components")
    func customEvent() throws {
        let objective = TrainingObjective.event(
            sport: .triathlon,
            distance: .custom(
                for: .triathlon,
                swimMeters: 600,
                bikeMeters: 25_000,
                runMeters: 6_000
            ),
            targetIntent: .finishComfortably
        )

        let encoded = try JSONEncoder().encode(objective)
        let restored = try JSONDecoder().decode(TrainingObjective.self, from: encoded)

        #expect(restored == objective)
        #expect(restored.event?.distance?.components.swimMeters == 600)
        #expect(restored.event?.distance?.components.bikeMeters == 25_000)
        #expect(restored.event?.distance?.components.runMeters == 6_000)
    }

    @Test("Invalid custom distances are recoverable validation issues")
    func invalidCustomDistance() {
        let objective = TrainingObjective.event(
            sport: .running,
            distance: .custom(for: .running, runMeters: 0)
        )

        let issues = TrainingObjectiveValidator.issues(
            for: objective,
            selectedSports: [.running],
            asOf: date(2026, 9, 24),
            calendar: calendar
        )

        #expect(issues.contains(.invalidEventDistance))
    }

    @Test("Event distance must belong to the selected event sport")
    func distanceSportMismatch() {
        let objective = TrainingObjective.event(
            sport: .running,
            distance: EventDistance(kind: .cycling20K)
        )

        let issues = TrainingObjectiveValidator.issues(
            for: objective,
            selectedSports: [.running],
            asOf: date(2026, 9, 24),
            calendar: calendar
        )

        #expect(issues.contains(.eventDistanceSportMismatch))
    }

    @Test("A dated event reports deterministic time remaining")
    func futureDates() {
        let today = date(2026, 9, 24)

        let tenWeeks = AthleteEventGoal(
            sport: .running,
            distance: EventDistance(kind: .run5K),
            eventDate: date(2026, 12, 3)
        )
        #expect(tenWeeks.daysRemaining(asOf: today, calendar: calendar) == 70)
        #expect(tenWeeks.weeksRemaining(asOf: today, calendar: calendar) == 10)

        let thisWeek = AthleteEventGoal(
            sport: .running,
            distance: EventDistance(kind: .run5K),
            eventDate: date(2026, 9, 27)
        )
        #expect(thisWeek.daysRemaining(asOf: today, calendar: calendar) == 3)
        #expect(thisWeek.weeksRemaining(asOf: today, calendar: calendar) == 1)

        let monthsAway = AthleteEventGoal(
            sport: .cycling,
            distance: EventDistance(kind: .cycling100K),
            eventDate: date(2027, 1, 22)
        )
        #expect(monthsAway.daysRemaining(asOf: today, calendar: calendar) == 120)
        #expect(monthsAway.weeksRemaining(asOf: today, calendar: calendar) == 18)
    }

    @Test("No event date remains a valid open-ended event")
    func noEventDate() {
        let event = AthleteEventGoal(
            sport: .running,
            distance: EventDistance(kind: .run10K),
            eventDate: nil
        )

        #expect(event.daysRemaining(asOf: date(2026, 9, 24), calendar: calendar) == nil)
        #expect(event.weeksRemaining(asOf: date(2026, 9, 24), calendar: calendar) == nil)
        #expect(event.countdownLabel(asOf: date(2026, 9, 24), calendar: calendar) == nil)
    }

    @Test("A past event date is rejected by domain validation")
    func pastEventDate() {
        let objective = TrainingObjective.event(
            sport: .running,
            distance: EventDistance(kind: .run5K),
            eventDate: date(2026, 9, 23)
        )

        let issues = TrainingObjectiveValidator.issues(
            for: objective,
            selectedSports: [.running],
            asOf: date(2026, 9, 24),
            calendar: calendar
        )

        #expect(issues.contains(.eventDateInPast))
    }

    @Test("Single-sport events require their sport to be trained")
    func eventSportMustBeSelected() {
        let objective = TrainingObjective.event(
            sport: .running,
            distance: EventDistance(kind: .run5K)
        )

        let issues = TrainingObjectiveValidator.issues(
            for: objective,
            selectedSports: [.cycling],
            asOf: date(2026, 9, 24),
            calendar: calendar
        )

        #expect(issues.contains(.missingTrainingSport(.running)))
    }

    @Test("Triathlon requires all three training sports")
    func triathlonRequiresAllDisciplines() {
        let objective = TrainingObjective.event(
            sport: .triathlon,
            distance: EventDistance(kind: .triathlonSprint)
        )

        let issues = TrainingObjectiveValidator.issues(
            for: objective,
            selectedSports: [.running],
            asOf: date(2026, 9, 24),
            calendar: calendar
        )

        #expect(issues.contains(.missingTrainingSport(.swimming)))
        #expect(issues.contains(.missingTrainingSport(.cycling)))
        #expect(!issues.contains(.missingTrainingSport(.running)))
    }

    @Test("New setup encoding retains both structured objective and legacy adapter")
    func setupRoundTrip() throws {
        let objective = TrainingObjective.event(
            sport: .running,
            distance: EventDistance(kind: .run10K),
            eventDate: date(2026, 12, 3),
            targetIntent: .performance
        )
        let setup = AthleteSetup(
            objective: objective,
            preferences: [SportPreference(sport: .running, sessionsPerWeek: 3)]
        )

        let data = try JSONEncoder().encode(setup)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let restored = try JSONDecoder().decode(AthleteSetup.self, from: data)

        #expect(json["objective"] != nil)
        #expect(json["goal"] as? String == "improveEndurance")
        #expect(restored.objective == objective)
        #expect(restored.goal == .improveEndurance)
    }
}
