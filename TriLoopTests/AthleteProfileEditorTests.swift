import Foundation
import Testing
@testable import TriLoop

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
}
