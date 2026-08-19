import Foundation
import Testing
@testable import TriLoop

@Suite("Intensity distribution")
struct IntensityDistributionTests {

    private let monday = Date(timeIntervalSince1970: 1_760_000_000)

    private func session(
        _ sport: Sport,
        minutes: Double?,
        intensity: WorkoutIntensity?,
        dayOffset: Int = 0
    ) -> LoadedSession {
        LoadedSession(
            date: monday.addingTimeInterval(Double(dayOffset) * 86_400),
            sport: sport,
            durationSeconds: minutes.map { $0 * 60 },
            intensity: intensity
        )
    }

    @Test("Time is split across the three bands")
    func splitsTime() throws {
        let distribution = try #require(
            IntensityDistributionPolicy.distribution(for: [
                session(.running, minutes: 60, intensity: .easy),
                session(.cycling, minutes: 30, intensity: .easy, dayOffset: 1),
                session(.running, minutes: 20, intensity: .moderate, dayOffset: 3),
                session(.running, minutes: 10, intensity: .hard, dayOffset: 5)
            ]).value
        )

        #expect(distribution.totalSeconds == 120 * 60)
        #expect(abs(distribution.share(.easy) - 0.75) < 0.0001)
        #expect(abs(distribution.share(.moderate) - (1.0 / 6.0)) < 0.0001)
        #expect(distribution.measured == 4)
    }

    @Test("Shares sum to one")
    func sharesSumToOne() throws {
        let distribution = try #require(
            IntensityDistributionPolicy.distribution(for: [
                session(.running, minutes: 45, intensity: .easy),
                session(.swimming, minutes: 25, intensity: .moderate, dayOffset: 2),
                session(.cycling, minutes: 15, intensity: .hard, dayOffset: 4)
            ]).value
        )
        let total = WorkoutIntensity.allCases.reduce(0.0) { $0 + distribution.share($1) }
        #expect(abs(total - 1.0) < 0.0001)
    }

    @Test("Sessions without an intensity are counted as unmeasured")
    func unclassifiedSessions() throws {
        let distribution = try #require(
            IntensityDistributionPolicy.distribution(for: [
                session(.running, minutes: 60, intensity: .easy),
                session(.swimming, minutes: 30, intensity: nil, dayOffset: 2)
            ]).value
        )
        // The unclassified swim must not be quietly folded into easy.
        #expect(distribution.share(.easy) == 1.0)
        #expect(distribution.unmeasured == 1)
        #expect(distribution.isPartial)
    }

    @Test("An intensity with no duration cannot be weighted")
    func intensityWithoutDuration() {
        #expect(
            IntensityDistributionPolicy.distribution(for: [
                session(.running, minutes: nil, intensity: .hard)
            ]) == .unavailable
        )
    }

    @Test("Nothing classified means unavailable, not all-easy")
    func nothingClassified() {
        let result = IntensityDistributionPolicy.distribution(for: [
            session(.running, minutes: 60, intensity: nil)
        ])
        #expect(result == .unavailable)
        #expect(result.value?.share(.easy) != 1.0)
    }

    @Test("Drilling into one sport ignores the others")
    func perSportDrillDown() throws {
        let sessions = [
            session(.running, minutes: 60, intensity: .hard),
            session(.cycling, minutes: 60, intensity: .easy, dayOffset: 2)
        ]

        let running = try #require(IntensityDistributionPolicy.distribution(for: sessions, sport: .running).value)
        #expect(running.share(.hard) == 1.0)

        let cycling = try #require(IntensityDistributionPolicy.distribution(for: sessions, sport: .cycling).value)
        #expect(cycling.share(.easy) == 1.0)
    }

    @Test("A sport with no sessions has no distribution")
    func absentSport() {
        #expect(
            IntensityDistributionPolicy.distribution(
                for: [session(.running, minutes: 60, intensity: .easy)],
                sport: .swimming
            ) == .unavailable
        )
    }

    @Test("Only sports actually trained are offered for drill-down")
    func sportsPresent() {
        let sports = IntensityDistributionPolicy.sportsPresent(in: [
            session(.running, minutes: 60, intensity: .easy),
            session(.running, minutes: 30, intensity: .easy, dayOffset: 2),
            session(.cycling, minutes: 30, intensity: .easy, dayOffset: 3)
        ])
        #expect(sports == [.running, .cycling])
    }
}

@Suite("Sport balance")
struct SportBalanceTests {

    private let monday = Date(timeIntervalSince1970: 1_760_000_000)

    private func session(
        _ sport: Sport,
        minutes: Double,
        load: Double? = nil,
        dayOffset: Int = 0
    ) -> LoadedSession {
        LoadedSession(
            date: monday.addingTimeInterval(Double(dayOffset) * 86_400),
            sport: sport,
            load: load.map { SessionLoad(value: $0, provenance: .reportedEffort) },
            durationSeconds: minutes * 60
        )
    }

    @Test("Time share is proportional to minutes trained")
    func timeShare() throws {
        let balance = try #require(
            SportBalancePolicy.balance(of: [
                session(.running, minutes: 60),
                session(.cycling, minutes: 30, dayOffset: 2),
                session(.swimming, minutes: 30, dayOffset: 4)
            ]).value
        )
        #expect(abs(balance.timeShare(.running) - 0.5) < 0.0001)
        #expect(abs(balance.timeShare(.cycling) - 0.25) < 0.0001)
    }

    @Test("Load share differs from time share when intensity differs")
    func loadShareDiffersFromTime() throws {
        let balance = try #require(
            SportBalancePolicy.balance(of: [
                session(.running, minutes: 60, load: 480),
                session(.cycling, minutes: 60, load: 120, dayOffset: 2)
            ]).value
        )
        // Equal time, very unequal training — which is the point of keeping both.
        #expect(abs(balance.timeShare(.running) - 0.5) < 0.0001)
        #expect(abs((balance.loadShare(.running) ?? 0) - 0.8) < 0.0001)
    }

    @Test("With no load measured, load share is absent rather than zero")
    func noLoadMeasured() throws {
        let balance = try #require(
            SportBalancePolicy.balance(of: [session(.running, minutes: 60)]).value
        )
        #expect(!balance.hasLoad)
        #expect(balance.loadShare(.running) == nil)
    }

    @Test("Nothing trained means no balance")
    func nothingTrained() {
        #expect(SportBalancePolicy.balance(of: []) == .unavailable)
    }

    @Test("Planned and actual are compared per sport")
    func plannedVersusActual() throws {
        let comparisons = SportBalancePolicy.compare(
            planned: [
                session(.running, minutes: 60),
                session(.cycling, minutes: 60, dayOffset: 2)
            ],
            actual: [
                session(.running, minutes: 90),
                session(.cycling, minutes: 30, dayOffset: 2)
            ]
        )

        let running = try #require(comparisons.first { $0.sport == .running })
        #expect(abs(running.plannedShare - 0.5) < 0.0001)
        #expect(abs(running.actualShare - 0.75) < 0.0001)
        #expect(running.difference > 0)
    }

    @Test("A planned sport that never happened is reported as a shortfall")
    func plannedButNotDone() throws {
        let comparisons = SportBalancePolicy.compare(
            planned: [
                session(.running, minutes: 60),
                session(.swimming, minutes: 60, dayOffset: 2)
            ],
            actual: [session(.running, minutes: 60)]
        )

        // The swim must appear, or a skipped discipline disappears from view.
        let swimming = try #require(comparisons.first { $0.sport == .swimming })
        #expect(swimming.actualShare == 0)
        #expect(swimming.difference < 0)
    }
}
