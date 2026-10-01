import Foundation

@testable import Athevia

@MainActor
enum CoachTestFixture {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    static func date(
        year: Int = 2026,
        month: Int = 9,
        day: Int = 28
    ) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        ) ?? .now
    }

    static func setup(
        baseline: AthleteBaseline? = nil,
        objective: TrainingObjective = TrainingObjective(kind: .generalFitness),
        schedule: AthleteSchedule = .everyDay(maxDurationMinutes: 60),
        preferences: [SportPreference] = [
            SportPreference(sport: .running, sessionsPerWeek: 2, typicalMinutes: 45),
            SportPreference(sport: .swimming, sessionsPerWeek: 2, typicalMinutes: 45),
            SportPreference(sport: .cycling, sessionsPerWeek: 2, typicalMinutes: 45)
        ]
    ) -> AthleteSetup {
        let resolvedBaseline = baseline ?? AthleteBaseline(
            running: .regular5K,
            swimming: .continuous50,
            cycling: .thirtyToFortyFive,
            assessedAt: date(year: 2026, month: 8, day: 1)
        )

        return AthleteSetup(
            objective: objective,
            baseline: resolvedBaseline,
            schedule: schedule,
            preferences: preferences,
            stage: .complete,
            completedAt: date()
        )
    }

    static func profile(
        id: UUID = UUID(),
        setup: AthleteSetup? = nil
    ) -> AthleteProfile {
        AthleteProfile(
            id: id,
            name: "Coach Test Athlete",
            experienceLevel: .developing,
            trainingStartDate: date(),
            setup: setup ?? self.setup()
        )
    }

    static func seedPlan(startDate: Date? = nil) -> WeeklyPlan {
        SeedWeekOne.makePlan(
            startDate: startDate ?? date(),
            calendar: calendar
        )
    }

    static func importedPlan(
        sport: Sport,
        date: Date,
        distanceMeters: Double?,
        duration: TimeInterval = 30 * 60,
        longestContinuousSwimMeters: Double? = nil,
        weekNumber: Int = 1
    ) -> WeeklyPlan {
        let workout = PlannedWorkout(
            date: date,
            discipline: sport.discipline,
            title: "Recorded \(sport.displayName)"
        )
        let imported = ImportedWorkout(
            healthKitUUID: UUID(),
            sport: sport,
            startDate: date,
            endDate: calendar.date(
                byAdding: .second,
                value: Int(duration),
                to: date
            ) ?? date,
            duration: duration,
            distanceMeters: distanceMeters,
            longestContinuousSwimMeters: longestContinuousSwimMeters,
            source: "com.apple.Health"
        )
        workout.attach(ImportedWorkoutSummary(imported))
        // Imported evidence represents a completed session. Capability
        // assessment intentionally ignores unresolved planned workouts.
        workout.completedAt = imported.endDate

        return WeeklyPlan(
            weekNumber: weekNumber,
            startDate: calendar.startOfDay(for: date),
            endDate: calendar.date(
                byAdding: .day,
                value: 6,
                to: calendar.startOfDay(for: date)
            ) ?? date,
            status: .active,
            workouts: [workout]
        )
    }

    static func context(
        profile: AthleteProfile,
        plans: [WeeklyPlan],
        healthWorkouts: [ImportedWorkout] = [],
        healthAccess: CoachHealthAccess = .authorized,
        asOf now: Date? = nil
    ) -> AthleteContextSnapshot {
        AthleteContextBuilder(calendar: calendar).build(
            profile: profile,
            plans: plans,
            healthWorkouts: healthWorkouts,
            healthAccess: healthAccess,
            asOf: now ?? date()
        )!
    }
}
