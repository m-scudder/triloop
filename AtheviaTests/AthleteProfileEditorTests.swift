import Foundation
import Testing
@testable import Athevia

/// §10.1.1.11: a preference edit and a training edit must not be confused, in
/// either direction. Over-reporting would ask the athlete to rebuild their week
/// for nothing; under-reporting would silently leave an incompatible plan.
@Suite("Athlete profile editing")
struct AthleteProfileEditorTests {

    private func setup() -> AthleteSetup {
        AthleteSetup(
            goal: .improveEndurance,
            baseline: AthleteBaseline(
                running: .continuous10Minutes,
                swimming: .continuous50,
                stroke: .freestyle,
                cycling: .twentyToThirty
            ),
            birthDate: Calendar.current.date(byAdding: .year, value: -30, to: .now),
            schedule: .everyDay(),
            preferences: [
                SportPreference(sport: .running, sessionsPerWeek: 2),
                SportPreference(sport: .swimming, sessionsPerWeek: 2)
            ],
            stage: .complete,
            completedAt: .now
        )
    }

    private func impact(_ change: (inout AthleteSetup) -> Void) -> ProfileEditImpact {
        let original = setup()
        var updated = original
        change(&updated)
        return AthleteProfileEditor.impact(from: original, to: updated)
    }

    @Test("An unchanged profile is not a change at all")
    func noChange() {
        #expect(AthleteProfileEditor.impact(from: setup(), to: setup()) == .safe)
    }

    @Test("The training goal reaches the plan")
    func goalIsTrainingImpacting() {
        #expect(impact { $0.goal = .generalFitness }.reasons == [.goal])
    }

    @Test("Each sport baseline is reported separately")
    func baselinesAreTrainingImpacting() {
        #expect(impact { $0.baseline.running = .regular5K }.reasons == [.runningBaseline])
        #expect(impact { $0.baseline.swimming = .continuous200Plus }.reasons == [.swimmingBaseline])
        #expect(impact { $0.baseline.cycling = .sixtyPlus }.reasons == [.cyclingBaseline])
    }

    @Test("Closing a training day changes what can be prescribed")
    func availabilityIsTrainingImpacting() {
        let result = impact { current in
            var days = current.schedule.days
            days[1].isAvailable = false
            current.schedule = AthleteSchedule(days: days)
        }

        #expect(result.reasons == [.availability])
    }

    @Test("Asking for more sessions changes what can be prescribed")
    func commitmentIsTrainingImpacting() {
        let result = impact { current in
            current.preferences = [
                SportPreference(sport: .running, sessionsPerWeek: 4),
                SportPreference(sport: .swimming, sessionsPerWeek: 2)
            ]
        }

        #expect(result.reasons == [.weeklyCommitment])
    }

    @Test("Reordering the same commitment is not a change")
    func commitmentOrderIsNotAChange() {
        let result = impact { current in
            current.preferences = [
                SportPreference(sport: .swimming, sessionsPerWeek: 2),
                SportPreference(sport: .running, sessionsPerWeek: 2)
            ]
        }

        #expect(result == .safe)
    }

    @Test("Date of birth only anchors zones, so it is a safe edit")
    func birthDateIsSafe() {
        let result = impact { current in
            current.birthDate = Calendar.current.date(byAdding: .year, value: -40, to: .now)
        }

        #expect(result == .safe)
    }

    @Test("Several edits at once are all reported")
    func multipleReasons() {
        let result = impact { current in
            current.goal = .generalFitness
            current.baseline.running = .regular5K
        }

        #expect(result.reasons == [.goal, .runningBaseline])
        #expect(result.isTrainingImpacting)
    }

    @Test("Changing event distance is reported without pretending the objective kind changed")
    func changingEvent() {
        var original = setup()
        original.objective = .event(
            sport: .running,
            distance: EventDistance(kind: .run5K)
        )
        var updated = original
        updated.objective = .event(
            sport: .running,
            distance: EventDistance(kind: .run10K)
        )

        #expect(AthleteProfileEditor.impact(from: original, to: updated).reasons == [.event])
    }

    @Test("Changing only the event date is reported separately")
    func changingEventDate() {
        let calendar = Calendar(identifier: .gregorian)
        let first = calendar.date(from: DateComponents(year: 2026, month: 12, day: 1))
        let second = calendar.date(from: DateComponents(year: 2026, month: 12, day: 15))

        var original = setup()
        original.objective = .event(
            sport: .running,
            distance: EventDistance(kind: .run5K),
            eventDate: first
        )
        var updated = original
        updated.objective.event?.eventDate = second

        #expect(AthleteProfileEditor.impact(from: original, to: updated).reasons == [.eventDate])
    }

    @Test("Changing target intent is a training-impacting event edit")
    func changingTargetIntent() {
        var original = setup()
        original.objective = .event(
            sport: .triathlon,
            distance: EventDistance(kind: .triathlonSprint),
            targetIntent: .complete
        )
        var updated = original
        updated.objective.event?.targetIntent = .performance

        #expect(AthleteProfileEditor.impact(from: original, to: updated).reasons == [.targetIntent])
    }

    @Test("Clearing an event changes the training objective")
    func clearingEvent() {
        var original = setup()
        original.objective = .event(
            sport: .running,
            distance: EventDistance(kind: .run5K)
        )
        var updated = original
        updated.objective = TrainingObjective(kind: .generalFitness)

        #expect(AthleteProfileEditor.impact(from: original, to: updated).reasons == [.goal])
    }
}
