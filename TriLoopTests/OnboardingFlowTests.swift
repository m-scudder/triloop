import Foundation
import SwiftData
import Testing

@testable import TriLoop

@MainActor
struct OnboardingFlowTests {
    @Test func flowHasSevenScreens() {
        let flow = AthleteSetup.Stage.onboardingFlow
        #expect(flow == [.welcome, .goal, .running, .days, .safety, .health, .preview])
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
        let context = ModelContext(try TriLoopModelContainer.make(inMemory: true))
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
        #expect(model.canAdvance)
        model.advance()
        #expect(OnboardingModel(context: context).stage == .safety)
    }

    @Test func baselineAndPoolAnswersSurviveResume() throws {
        let container = try TriLoopModelContainer.make(inMemory: true)
        let model = OnboardingModel(context: ModelContext(container))
        model.jump(to: .swimming)
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
        resumed.setPoolLength(0)
        #expect(!resumed.canAdvance)
    }

    @Test func skippingConnectionsBuildsWithoutCommitting() throws {
        let container = try TriLoopModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let model = OnboardingModel(context: context)
        model.advance()
        #expect(model.stage == .goal)
        model.advance()
        #expect(model.stage == .running)
        model.advance()
        #expect(model.stage == .days)
        for weekday in Weekday.trainingWeek { model.toggleDay(weekday) }
        model.advance()
        #expect(model.stage == .safety)
        model.advance()
        #expect(model.stage == .health)
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

    @Test func returningToScheduleKeepsCustomCommitment() throws {
        let context = ModelContext(try TriLoopModelContainer.make(inMemory: true))
        let model = OnboardingModel(context: context)
        model.jump(to: .days)
        model.setSessions(1, for: .running)
        model.setSessions(0, for: .swimming)
        model.setTypicalMinutes(60, for: .cycling)
        model.toggleDay(.tuesday)
        model.toggleDay(.saturday)
        model.setMaxDuration(90, on: .saturday)
        let preferences = model.setup.preferences
        model.advance()
        model.goBack()
        #expect(model.stage == .days)
        #expect(model.setup.preferences == preferences)
        #expect(model.setup.schedule.availability(on: .saturday).maxDurationMinutes == 90)
        for sport in Sport.allCases { model.setSessions(0, for: sport) }
        #expect(!model.canAdvance)
    }
}