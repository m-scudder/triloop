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
        #expect(tile(tiles, .adherence)?.value == "60%")
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

    @Test("Manual additions retain training time without changing generated adherence", arguments: [WorkoutOrigin.custom, .library, .imported])
    func manualAdditionsDoNotCount(origin: WorkoutOrigin) throws {
        let context = ModelContext(try container())
        let week = plan(sessions: 7, in: context)
        let workouts = week.orderedWorkouts
        workouts.prefix(3).forEach(report)
        for workout in workouts.suffix(2) {
            workout.origin = origin
            report(workout)
        }

        let tiles = TodayGlanceBuilder.tiles(plan: week, sessions: [])

        #expect(tile(tiles, .sessions)?.value == "3 / 5")
        #expect(tile(tiles, .training)?.value == "2 hr 30 min")
        #expect(tile(tiles, .adherence)?.value == "60%")
    }

    @Test("A single generated prescription has adherence independent of manual reports")
    func singlePrescription() throws {
        let context = ModelContext(try container())
        let week = plan(sessions: 3, in: context)
        let workouts = week.orderedWorkouts
        workouts[1].origin = .custom
        workouts[2].origin = .library
        workouts.forEach(report)

        let tiles = TodayGlanceBuilder.tiles(plan: week, sessions: [])

        #expect(tile(tiles, .sessions)?.value == "1 / 1")
        #expect(tile(tiles, .adherence)?.value == "100%")
    }

    @Test("Adherence includes all prescriptions before they are reported")
    func adherenceIncludesFullWeek() throws {
        let context = ModelContext(try container())
        let week = plan(sessions: 4, in: context)
        report(try #require(week.orderedWorkouts.first))

        let tiles = TodayGlanceBuilder.tiles(plan: week, sessions: [])

        #expect(tile(tiles, .adherence)?.value == "25%")
        #expect(tile(tiles, .history) == nil)
    }

    @Test("Nothing is ever said twice")
    func tilesAreUnique() throws {
        let context = ModelContext(try container())
        let week = plan(sessions: 4, in: context)

        // Nothing reported and nothing measured: the case that used to pad the
        // grid with two identical tiles.
        let tiles = TodayGlanceBuilder.tiles(plan: week, sessions: [])

        #expect(Set(tiles.map(\.id)).count == tiles.count)
        #expect(tile(tiles, .adherence)?.value == "0%")
        #expect(tile(tiles, .history) == nil)
    }

    @Test("Adherence counts completed sessions rather than averaging recorded duration")
    func adherenceCountsCompletedStatus() throws {
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
        report(workouts[1])

        let tiles = TodayGlanceBuilder.tiles(plan: week, sessions: [])
        #expect(short.awaitingFeedback)
        #expect(tile(tiles, .sessions)?.value == "2 / 4")
        #expect(tile(tiles, .adherence)?.value == "50%")
    }

    @Test("Three completed generated sessions out of five is 60 percent with missed and skipped prescriptions")
    func threeOfFiveWithMissedAndSkipped() throws {
        let context = ModelContext(try container())
        let week = plan(sessions: 5, in: context)
        let workouts = week.orderedWorkouts
        workouts.prefix(3).forEach(report)
        workouts[3].skip()
        #expect(workouts[4].isMissed(asOf: week.endDate.addingTimeInterval(86_400)))

        let tiles = TodayGlanceBuilder.tiles(plan: week, sessions: [])
        #expect(week.adherenceShare == 0.6)
        #expect(tile(tiles, .sessions)?.value == "3 / 5")
        #expect(tile(tiles, .adherence)?.value == "60%")
    }

    @Test("Manual-only weeks show activity without a zero-over-zero plan count", arguments: [WorkoutOrigin.custom, .library, .imported])
    func manualOnly(origin: WorkoutOrigin) throws {
        let context = ModelContext(try container())
        let week = plan(sessions: 2, in: context)
        for workout in week.trainingSessions {
            workout.origin = origin
            report(workout)
        }

        let tiles = TodayGlanceBuilder.tiles(plan: week, sessions: [])
        #expect(week.adherenceShare == nil)
        #expect(tile(tiles, .sessions)?.value == "2")
        #expect(tile(tiles, .sessions)?.label == "Sessions")
        #expect(tile(tiles, .training)?.value == "1 hr")
        #expect(tile(tiles, .training)?.label == "Reported Training")
        #expect(tile(tiles, .adherence) == nil)
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
        // Adherence still has something to say, so no placeholder is needed.
        #expect(tile(tiles, .adherence) != nil)
        #expect(tile(tiles, .history) == nil)
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

    @Test("The fixed pair is always there, and never duplicated")
    func alwaysFour() throws {
        let context = ModelContext(try container())
        let week = plan(sessions: 5, in: context)

        let empty = TodayGlanceBuilder.tiles(plan: week, sessions: [])
        #expect(tile(empty, .sessions) != nil)
        #expect(tile(empty, .training) != nil)
        #expect(Set(empty.map(\.id)).count == empty.count)

        week.orderedWorkouts.forEach(report)
        let measured = TodayGlanceBuilder.tiles(
            plan: week,
            sessions: [LoadedSession(date: monday, sport: .running, durationSeconds: 1_800, intensity: .easy)]
        )
        #expect(measured.count == 4)
        #expect(Set(measured.map(\.id)).count == measured.count)
    }
}
