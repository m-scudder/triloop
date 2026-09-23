import Foundation
import SwiftData
import Testing

@testable import Athevia

@MainActor
struct OnboardingFlowTests {
    @Test func flowHasThreeDecisionScreens() {
        let flow = AthleteSetup.Stage.onboardingFlow
        #expect(flow == [.running, .days, .preview])
        for index in 0..<(flow.count - 1) {
            #expect(flow[index].next == flow[index + 1])
            #expect(flow[index + 1].previous == flow[index])
        }
    }

    @Test(arguments: AthleteSetup.Stage.allCases)
    func savedStagesStillDecode(_ stage: AthleteSetup.Stage) throws {
        let data = try JSONEncoder().encode(AthleteSetup(stage: stage))
        let restored = try JSONDecoder().decode(AthleteSetup.self, from: data)
        #expect(restored.stage == stage)
        #expect(AthleteSetup.Stage.onboardingFlow.contains(stage.consolidated) || stage == .complete)
    }

    @Test func legacyCommitmentResumesWithDefaults() throws {
        let context = ModelContext(try AtheviaModelContainer.make(inMemory: true))
        let profile = AthleteProfile(name: "", trainingStartDate: .now)
        profile.setup = AthleteSetup(stage: .commitment)
        context.insert(profile)
        try context.save()

        let model = OnboardingModel(context: context)
        #expect(model.stage == .days)
        #expect(!model.setup.preferences.isEmpty)
        #expect(!model.canAdvance)

        model.toggleDay(.monday)
        model.toggleDay(.wednesday)
        model.toggleDay(.friday)
        model.setSharedMaxDuration(60)

        #expect(model.canAdvance)
        model.advance()
        #expect(OnboardingModel(context: context).stage == .preview)
    }

    @Test func baselineAndPoolAnswersSurviveResume() throws {
        let container = try AtheviaModelContainer.make(inMemory: true)
        let model = OnboardingModel(context: ModelContext(container))
        model.jump(to: .swimming)
        model.toggleSport(.swimming)
        model.choose(running: .continuous20To30Minutes)
        model.choose(swimming: .continuous100)
        model.choose(cycling: .fortyFiveToSixty)
        model.setPoolLength(50)

        let resumed = OnboardingModel(context: ModelContext(container))
        #expect(resumed.stage == .running)
        #expect(resumed.setup.baseline.running == .continuous20To30Minutes)
        #expect(resumed.setup.baseline.swimming == .continuous100)
        #expect(resumed.setup.baseline.cycling == .fortyFiveToSixty)
        #expect(resumed.poolLengthMeters == 50)
        #expect(resumed.isSportSelected(.swimming))

        resumed.setPoolLength(0)
        #expect(!resumed.canAdvance)
    }

    @Test func compactFlowBuildsWithoutCommitting() throws {
        let container = try AtheviaModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let model = OnboardingModel(context: context)

        #expect(model.stage == .running)
        model.toggleSport(.running)
        model.choose(running: .continuous10Minutes)
        model.advance()
        #expect(model.stage == .days)

        model.choose(goal: .improveEndurance)
        model.toggleDay(.monday)
        model.toggleDay(.wednesday)
        model.setSharedMaxDuration(60)
        model.advance()

        #expect(model.stage == .preview)
        #expect(model.preview?.orderedWorkouts.count == 7)
        #expect(try context.fetchCount(FetchDescriptor<WeeklyPlan>()) == 0)

        let resumed = OnboardingModel(context: ModelContext(container))
        #expect(resumed.stage == .preview)
        resumed.buildPreview()
        #expect(resumed.preview != nil)
        resumed.start()

        #expect(try context.fetchCount(FetchDescriptor<WeeklyPlan>()) == 1)
        #expect(OnboardingModel(context: ModelContext(container)).setup.isComplete)
    }

    @Test func selectedStartDateSurvivesResumeAndDrivesPreview() throws {
        let container = try AtheviaModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let model = OnboardingModel(context: context)

        model.toggleSport(.running)
        model.choose(running: .continuous10Minutes)
        model.advance()

        model.toggleDay(.sunday)
        model.toggleDay(.monday)
        model.setSharedMaxDuration(60)

        let calendar = Calendar.current
        let sunday = calendar.nextDate(
            after: .now,
            matching: DateComponents(weekday: 1),
            matchingPolicy: .nextTimePreservingSmallerComponents
        ) ?? .now

        model.choose(startDate: sunday)

        let resumed = OnboardingModel(context: ModelContext(container))
        #expect(calendar.isDate(resumed.selectedStartDate, inSameDayAs: sunday))

        resumed.advance()
        let preview = try #require(resumed.preview)
        #expect(preview.trainingSessions.allSatisfy { $0.date >= calendar.startOfDay(for: sunday) })
    }

    @Test func scheduleUsesOneSharedDurationAndSelectedSports() throws {
        let context = ModelContext(try AtheviaModelContainer.make(inMemory: true))
        let model = OnboardingModel(context: context)

        model.jump(to: .running)
        model.toggleSport(.running)
        model.toggleSport(.cycling)
        model.jump(to: .days)

        model.toggleDay(.monday)
        model.toggleDay(.tuesday)
        model.toggleDay(.thursday)
        model.toggleDay(.saturday)
        model.setSharedMaxDuration(60)

        #expect(model.sharedTrainingMinutes == 60)
        #expect(model.setup.schedule.days.allSatisfy { $0.maxDurationMinutes == 60 })
        #expect(model.canAdvance)

        model.advance()

        #expect(model.stage == .preview)
        #expect(model.setup.preferences.first(where: { $0.sport == .running })?.isTrained == true)
        #expect(model.setup.preferences.first(where: { $0.sport == .cycling })?.isTrained == true)
        #expect(model.setup.preferences.first(where: { $0.sport == .swimming })?.isTrained != true)

        let frequencies = WeekShapePlanner.frequencies(
            from: model.setup.preferences,
            schedule: model.setup.schedule
        )
        #expect(frequencies.first(where: { $0.sport == .running })?.sessions == 2)
        #expect(frequencies.first(where: { $0.sport == .cycling })?.sessions == 2)
    }

    @Test func returningToScheduleRequiresGoingForwardAgain() throws {
        let context = ModelContext(try AtheviaModelContainer.make(inMemory: true))
        let model = OnboardingModel(context: context)

        model.jump(to: .running)
        model.toggleSport(.running)
        model.jump(to: .days)
        model.toggleDay(.tuesday)
        model.toggleDay(.saturday)
        model.setSharedMaxDuration(90)
        model.advance()

        #expect(model.stage == .preview)

        model.jump(to: .days)
        #expect(model.stage == .days)
        #expect(model.sharedTrainingMinutes == 90)
        #expect(model.setup.schedule.availability(on: .saturday).maxDurationMinutes == 90)

        model.advance()
        #expect(model.stage == .preview)
    }

    @Test func eventMustMatchSelectedTrainingSportsBeforePreview() throws {
        let context = ModelContext(try AtheviaModelContainer.make(inMemory: true))
        let model = OnboardingModel(context: context)

        model.toggleSport(.running)
        model.advance()
        model.toggleDay(.monday)
        model.toggleDay(.wednesday)
        model.setSharedMaxDuration(45)

        model.choose(
            objective: .event(
                sport: .triathlon,
                distance: EventDistance(kind: .triathlonSprint)
            )
        )

        #expect(!model.canAdvance)
        #expect(model.objectiveValidationIssues.contains(.missingTrainingSport(.swimming)))
        #expect(model.objectiveValidationIssues.contains(.missingTrainingSport(.cycling)))

        model.choose(
            objective: .event(
                sport: .running,
                distance: EventDistance(kind: .run5K)
            )
        )

        #expect(model.objectiveValidationIssues.isEmpty)
        #expect(model.canAdvance)
    }

    @Test func pastEventDateCannotAdvanceToPreview() throws {
        let context = ModelContext(try AtheviaModelContainer.make(inMemory: true))
        let model = OnboardingModel(context: context)

        model.toggleSport(.running)
        model.advance()
        model.toggleDay(.monday)
        model.toggleDay(.wednesday)
        model.setSharedMaxDuration(45)

        let yesterday = Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: Calendar.current.startOfDay(for: .now)
        ) ?? .now
        model.choose(
            objective: .event(
                sport: .running,
                distance: EventDistance(kind: .run5K),
                eventDate: yesterday
            )
        )

        #expect(!model.canAdvance)
        #expect(model.objectiveValidationIssues.contains(.eventDateInPast))
    }
}
