import Foundation
import SwiftData
import Testing
@testable import TriLoop

/// §2: the tiles are context for today's session, so a figure is withheld
/// rather than shown before the evidence supports it.
@MainActor
@Suite("Today at a glance")
struct TodayGlanceTests {

    private let monday = Date(timeIntervalSince1970: 1_760_054_400)
    private let calendar = Calendar.current

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: TriLoopSchema.current,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// A week of `count` running sessions, each prescribed at 30 minutes.
    private func plan(sessions count: Int, in context: ModelContext) -> WeeklyPlan {
        let plan = WeeklyPlan(
            weekNumber: 1,
            startDate: monday,
            endDate: calendar.date(byAdding: .day, value: 6, to: monday) ?? monday,
            parameters: TrainingParameters()
        )
        context.insert(plan)

        for offset in 0..<count {
            let workout = PlannedWorkout(
                date: calendar.date(byAdding: .day, value: offset, to: monday) ?? monday,
                discipline: .running,
                title: "Run",
                targetRPE: RPERange(3, 4),
                prescribedDurationSeconds: 1_800
            )
            context.insert(workout)
            plan.workouts.append(workout)
        }
        return plan
    }

    private func report(_ workout: PlannedWorkout) {
        workout.recordCompletion(with: FeedbackDraft(rpe: 3, painScore: 0, recoveryFeeling: .good))
    }

    private func tile(_ tiles: [GlanceTile], _ slot: GlanceTile.Slot) -> GlanceTile? {
        tiles.first { $0.slot == slot }
    }

    // MARK: - Fixed tiles

    @Test("Sessions and training time are always present")
    func fixedTiles() throws {
        let context = ModelContext(try container())
        let week = plan(sessions: 5, in: context)
        week.orderedWorkouts.prefix(3).forEach(report)

        let tiles = TodayGlanceBuilder.tiles(plan: week, sessions: [])

        #expect(tile(tiles, .sessions)?.value == "3 / 5")
        #expect(tile(tiles, .training)?.value == "1 hr 30 min")
    }

    @Test("A week with no training sessions has nothing to show")
    func noTrainingSessions() throws {
        let context = ModelContext(try container())
        let plan = WeeklyPlan(
            weekNumber: 1,
            startDate: monday,
            endDate: monday,
            parameters: TrainingParameters()
        )
        context.insert(plan)

        #expect(TodayGlanceBuilder.tiles(plan: plan, sessions: []).isEmpty)
        #expect(TodayGlanceBuilder.tiles(plan: nil, sessions: []).isEmpty)
    }

    // MARK: - Adherence

    @Test("Adherence is withheld until more than one session has been reported")
    func adherenceNeedsMoreThanOneSession() throws {
        let context = ModelContext(try container())
        let week = plan(sessions: 4, in: context)
        report(try #require(week.orderedWorkouts.first))

        let tiles = TodayGlanceBuilder.tiles(plan: week, sessions: [])

        #expect(tile(tiles, .adherence) == nil)
        #expect(tile(tiles, .history)?.value == "Building")
    }

    @Test("Adherence averages how much of each prescription was covered")
    func adherenceAverages() throws {
        let context = ModelContext(try container())
        let week = plan(sessions: 4, in: context)
        let workouts = week.orderedWorkouts

        // One session cut in half, one covered in full.
        let short = try #require(workouts.first)
        let summary = ImportedWorkoutSummary(
            healthKitUUID: UUID(),
            sport: .running,
            startDate: monday,
            endDate: monday.addingTimeInterval(900),
            duration: 900,
            metrics: RecordedMetrics()
        )
        context.insert(summary)
        short.attach(summary)
        report(short)
        report(workouts[1])

        #expect(tile(TodayGlanceBuilder.tiles(plan: week, sessions: []), .adherence)?.value == "75%")
    }

    // MARK: - Intensity

    @Test("A week dominated by one band is named, a mixed one is not")
    func intensityDescriptor() throws {
        let context = ModelContext(try container())
        let week = plan(sessions: 3, in: context)
        week.orderedWorkouts.forEach(report)

        let easy = [
            LoadedSession(date: monday, sport: .running, durationSeconds: 1_800, intensity: .easy),
            LoadedSession(date: monday, sport: .running, durationSeconds: 1_800, intensity: .easy),
            LoadedSession(date: monday, sport: .running, durationSeconds: 600, intensity: .hard)
        ]
        #expect(tile(TodayGlanceBuilder.tiles(plan: week, sessions: easy), .intensity)?.value == "Mostly Easy")

        let mixed = [
            LoadedSession(date: monday, sport: .running, durationSeconds: 1_800, intensity: .easy),
            LoadedSession(date: monday, sport: .running, durationSeconds: 1_800, intensity: .hard)
        ]
        #expect(tile(TodayGlanceBuilder.tiles(plan: week, sessions: mixed), .intensity)?.value == "Mixed")
    }

    @Test("Sessions with no measured intensity produce no intensity tile")
    func intensityUnavailable() throws {
        let context = ModelContext(try container())
        let week = plan(sessions: 3, in: context)
        week.orderedWorkouts.forEach(report)

        let unmeasured = [LoadedSession(date: monday, sport: .running, durationSeconds: 1_800)]
        let tiles = TodayGlanceBuilder.tiles(plan: week, sessions: unmeasured)

        #expect(tile(tiles, .intensity) == nil)
        #expect(tile(tiles, .history) != nil)
    }

    // MARK: - Recovery

    @Test("A reading outside its usual range takes the slot from intensity")
    func recoveryOutranksIntensity() throws {
        let context = ModelContext(try container())
        let week = plan(sessions: 3, in: context)
        week.orderedWorkouts.forEach(report)

        let sessions = [LoadedSession(date: monday, sport: .running, durationSeconds: 1_800, intensity: .easy)]
        let recovery = RecoverySignals(standings: [.heartRateVariability: .below])

        let tiles = TodayGlanceBuilder.tiles(plan: week, sessions: sessions, recovery: recovery)

        #expect(tile(tiles, .intensity) == nil)
        // §61: the tile names the indicator rather than compositing one score.
        #expect(tile(tiles, .recovery)?.value == "Below Range")
        #expect(tile(tiles, .recovery)?.label == "HRV")
    }

    @Test("Readings sitting inside their range leave the slot to intensity")
    func recoveryWithinRange() throws {
        let context = ModelContext(try container())
        let week = plan(sessions: 3, in: context)
        week.orderedWorkouts.forEach(report)

        let sessions = [LoadedSession(date: monday, sport: .running, durationSeconds: 1_800, intensity: .easy)]
        let recovery = RecoverySignals(standings: [.restingHeartRate: .withinRange])

        let tiles = TodayGlanceBuilder.tiles(plan: week, sessions: sessions, recovery: recovery)

        #expect(tile(tiles, .recovery) == nil)
        #expect(tile(tiles, .intensity)?.value == "Mostly Easy")
    }

    @Test("The most actionable flagged reading takes the slot, not the first alphabetically")
    func recoveryPriority() throws {
        let context = ModelContext(try container())
        let week = plan(sessions: 3, in: context)
        week.orderedWorkouts.forEach(report)

        let recovery = RecoverySignals(standings: [
            .cardioFitness: .below,
            .restingHeartRate: .above
        ])

        let tiles = TodayGlanceBuilder.tiles(plan: week, sessions: [], recovery: recovery)

        #expect(tile(tiles, .recovery)?.label == "Resting HR")
        #expect(tile(tiles, .recovery)?.value == "Above Range")
    }

    // MARK: - Shape

    @Test("There are always exactly four tiles once a week has sessions")
    func alwaysFour() throws {
        let context = ModelContext(try container())
        let week = plan(sessions: 5, in: context)

        #expect(TodayGlanceBuilder.tiles(plan: week, sessions: []).count == 4)

        week.orderedWorkouts.forEach(report)
        #expect(TodayGlanceBuilder.tiles(plan: week, sessions: []).count == 4)
    }
}
