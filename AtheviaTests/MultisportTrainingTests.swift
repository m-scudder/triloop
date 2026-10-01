import Foundation
import Testing

@testable import Athevia

@Suite("Multisport training")
struct MultisportTrainingTests {
    @Test("Brick requires triathlon specific phase and availability")
    func brickEligibility() {
        let policy = MultisportTrainingPolicy()
        let journey = TrainingJourney(
            phase: .specific,
            weeksRemaining: 4,
            readiness: EventReadiness(status: .building, sports: []),
            weeklyObjectives: [.init(sport: nil, kind: .brickTransition, priority: 4)],
            sportPriorities: []
        )
        let objective = TrainingObjective.event(
            sport: .triathlon,
            distance: EventDistance(kind: .triathlonSprint)
        )

        #expect(policy.canScheduleBrick(
            journey: journey,
            objective: objective,
            schedule: .everyDay()
        ))
    }

    @Test("Run only event never receives a brick")
    func noRunOnlyBrick() {
        let policy = MultisportTrainingPolicy()
        let journey = TrainingJourney(
            phase: .specific,
            weeksRemaining: 4,
            readiness: EventReadiness(status: .onTrack, sports: []),
            weeklyObjectives: [.init(sport: nil, kind: .brickTransition, priority: 2)],
            sportPriorities: []
        )

        #expect(!policy.canScheduleBrick(
            journey: journey,
            objective: .event(sport: .running, distance: EventDistance(kind: .run10K)),
            schedule: .everyDay()
        ))
    }

    @Test("Recovery blocks brick")
    func recoveryBlocksBrick() {
        let policy = MultisportTrainingPolicy()
        let journey = TrainingJourney(
            phase: .specific,
            weeksRemaining: 4,
            readiness: EventReadiness(status: .needsAttention, sports: []),
            weeklyObjectives: [.init(sport: nil, kind: .brickTransition, priority: 4)],
            sportPriorities: []
        )

        #expect(!policy.canScheduleBrick(
            journey: journey,
            objective: .event(sport: .triathlon, distance: EventDistance(kind: .triathlonSprint)),
            schedule: .everyDay(),
            recoveringSports: [.running]
        ))
    }

    @Test("Weak swimmer stays on fundamentals")
    func weakSwimmer() {
        let policy = MultisportTrainingPolicy()
        #expect(policy.swimKind(baseline: .none, phase: .specific) == .swimFundamentals)
        #expect(policy.swimKind(baseline: .continuous25, phase: .specific) == .swimFundamentals)
    }

    @Test("Open water is never implicit")
    func openWaterRequiresConsent() {
        let policy = MultisportTrainingPolicy()
        #expect(policy.swimKind(baseline: .continuous200Plus, phase: .specific) != .swimOpenWater)
        #expect(policy.swimKind(
            baseline: .continuous200Plus,
            phase: .specific,
            openWater: OpenWaterTrainingConsent(
                explicitlyConfirmed: true,
                hasSafeVenue: true,
                hasSupervisionOrBuddy: true
            )
        ) == .swimOpenWater)
    }

    @Test("Taper and race week reduce workload")
    func taperReduces() {
        let policy = MultisportTrainingPolicy()
        #expect(policy.workloadMultiplier(for: .taper) < 1)
        #expect(policy.workloadMultiplier(for: .raceWeek) <= policy.workloadMultiplier(for: .taper))
    }

    @Test("Post event becomes recovery rather than progression")
    func postEventRecovery() {
        let policy = MultisportTrainingPolicy()
        #expect(policy.workloadMultiplier(for: .recovery) == 0)
    }

    @Test("Brick step ordering is deterministic")
    func brickOrdering() {
        let workout = MultisportPrescribedSessions.brick(
            on: .now,
            parameters: TrainingParameters(),
            prescription: BrickPrescription(
                bikeSeconds: 1_800,
                transitionSeconds: 300,
                runSeconds: 600,
                targetIntensity: .easy
            )
        )

        #expect(workout.orderedSteps.map(\.title) == [
            "Easy bike", "Bike before your run", "Change from bike to run", "Easy run after cycling", "Easy walk"
        ])
    }
}
