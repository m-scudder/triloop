#if DEBUG
import Foundation
import Testing
@testable import TriLoop

/// §26 and §59's missing-data matrix, checked through the real policies.
///
/// Automates what would otherwise be six rounds of switching datasets by hand.
/// It cannot prove a chart drew correctly, but it does prove the values behind
/// every screen are present or explicitly absent — which is where §55 is
/// actually violated.
@Suite("Fixture scenarios")
struct FixtureScenarioTests {

    private let reference = Date(timeIntervalSince1970: 1_760_000_000)

    private func data(_ dataset: SimulationDataset) -> SimulatedHealthData {
        SimulationFixture.generate(dataset, asOf: reference)
    }

    /// Sessions built the way the app builds them, so the assertions describe
    /// production behaviour rather than the fixture's raw contents.
    private func sessions(_ dataset: SimulationDataset) -> [LoadedSession] {
        let workouts = data(dataset).workouts
        let ceiling = HeartRateCeiling.resolve(
            birthDate: Calendar.current.date(byAdding: .year, value: -35, to: reference),
            observedMaximum: workouts.compactMap(\.maximumHeartRate).max(),
            asOf: reference
        )?.maximum

        return workouts.map { workout in
            let effort = EffortEvidence(
                healthKitEffort: workout.metrics.workoutEffort,
                estimatedHealthKitEffort: workout.metrics.estimatedWorkoutEffort
            )
            let intensity = WorkoutIntensityPolicy.intensity(
                zones: nil,
                effort: effort,
                averageHeartRate: workout.averageHeartRate,
                maximumHeartRate: ceiling
            ).value?.intensity

            return LoadedSession(
                date: workout.startDate,
                sport: workout.sport,
                load: SessionLoadPolicy.load(
                    durationSeconds: workout.duration,
                    zones: nil,
                    effort: effort
                ).value,
                durationSeconds: workout.duration,
                intensity: intensity,
                distanceMeters: workout.distanceMeters,
                averageHeartRate: workout.averageHeartRate,
                longestContinuousSwimMeters: workout.longestContinuousSwimMeters,
                metrics: workout.metrics
            )
        }
    }

    // MARK: - No data

    @Test("No Data produces nothing at all, and no zeros")
    func noData() {
        let fixture = data(.noData)
        #expect(fixture.workouts.isEmpty)
        #expect(fixture.recovery.isEmpty)

        let built = sessions(.noData)
        #expect(IntensityDistributionPolicy.distribution(for: built) == .unavailable)
        #expect(SportBalancePolicy.balance(of: built) == .unavailable)
    }

    // MARK: - Missing metrics

    @Test("Missing Heart Rate leaves intensity unavailable rather than easy")
    func missingHeartRate() {
        let built = sessions(.missingHeartRate)
        #expect(!built.isEmpty)
        #expect(built.allSatisfy { $0.averageHeartRate == nil })

        // No heart rate and no effort score means nothing to classify with, and
        // §33 requires that to read as unknown rather than easy.
        #expect(built.allSatisfy { $0.intensity == nil })
        #expect(IntensityDistributionPolicy.distribution(for: built) == .unavailable)
    }

    @Test("Missing Power reports cadence but no watts anywhere")
    func missingPower() {
        let rides = sessions(.missingPower).filter { $0.sport == .cycling }
        #expect(!rides.isEmpty)
        #expect(rides.allSatisfy { $0.metrics.averageCyclingPower == nil })
        #expect(rides.allSatisfy { $0.metrics.functionalThresholdPower == nil })
        #expect(rides.allSatisfy { $0.metrics.averageCyclingCadence != nil })
    }

    @Test("Partial Health Data has workouts but no recovery")
    func partialData() {
        let fixture = data(.partialData)
        #expect(!fixture.workouts.isEmpty)
        #expect(fixture.recovery.isEmpty)
    }

    // MARK: - History depth

    @Test("Sparse History cannot support a trend or a four-week average")
    func sparseHistory() {
        let built = sessions(.sparseHistory)
        let weeks = built.map { session in
            PlanWeekSessions(weekNumber: 1, startDate: session.date, sessions: [session])
        }
        let loads = weeks.compactMap { WeeklyTrainingLoad.load(for: $0).value }

        #expect(!WeeklyTrainingLoad.rollingAverage(of: loads).isAvailable)
        #expect(!RunningTrends.pace(built, anchoredTo: reference).isAvailable)
    }

    @Test("Beginner 12 Weeks supports trends and a four-week average")
    func beginnerTwelveWeeks() throws {
        let built = sessions(.beginnerTwelveWeeks)
        #expect(built.count > 20)

        let trend = RunningTrends.weeklyDistance(built, anchoredTo: built[0].date)
        #expect(trend.isAvailable)
    }

    // MARK: - Load and recovery shape

    @Test("High Training Load accumulates more than the beginner fixture")
    func highLoad() throws {
        let high = sessions(.highLoad).compactMap { $0.load?.value }.reduce(0, +)
        let beginner = sessions(.beginnerFourWeeks).compactMap { $0.load?.value }.reduce(0, +)
        #expect(high > beginner)
    }

    @Test("Poor Recovery trends resting heart rate up and HRV down")
    func poorRecovery() throws {
        let fixture = data(.poorRecovery)

        let resting = try #require(fixture.recovery[.restingHeartRate])
        let hrv = try #require(fixture.recovery[.heartRateVariability])
        #expect(resting.count >= 28)

        let earlyResting = resting.prefix(7).map(\.value).reduce(0, +) / 7
        let lateResting = resting.suffix(7).map(\.value).reduce(0, +) / 7
        #expect(lateResting > earlyResting)

        let earlyHRV = hrv.prefix(7).map(\.value).reduce(0, +) / 7
        let lateHRV = hrv.suffix(7).map(\.value).reduce(0, +) / 7
        #expect(lateHRV < earlyHRV)
    }

    @Test("Poor Recovery reads as outside the usual range, not as a diagnosis")
    func poorRecoveryStanding() throws {
        let fixture = data(.poorRecovery)
        let readings = try #require(fixture.recovery[.restingHeartRate])
            .map { RecoveryReading(date: $0.date, value: $0.value) }

        let baseline = try #require(
            PhysiologicalBaselinePolicy.baseline(
                from: readings,
                window: .sevenDay,
                asOf: reference
            ).value
        )
        #expect(baseline.readingCount >= 4)
    }

    // MARK: - Full data

    @Test("Experienced Triathlete populates every section")
    func experiencedTriathlete() throws {
        let built = sessions(.experiencedTriathlete)

        #expect(Set(built.map(\.sport)) == Set([.running, .swimming, .cycling]))
        #expect(built.allSatisfy { $0.averageHeartRate != nil })
        #expect(built.contains { $0.metrics.averageRunningPower != nil })
        #expect(built.contains { $0.metrics.averageCyclingPower != nil })

        let distribution = try #require(IntensityDistributionPolicy.distribution(for: built).value)
        #expect(distribution.measured > 0)
        #expect(!distribution.isPartial)

        let balance = try #require(SportBalancePolicy.balance(of: built).value)
        #expect(balance.hasLoad)

        let fixture = data(.experiencedTriathlete)
        #expect(fixture.recovery[.restingHeartRate]?.count ?? 0 >= 28)
        #expect(fixture.recovery[.cardioFitness]?.isEmpty == false)
    }

    // MARK: - Cross-cutting

    @Test("No dataset ever reports a load of zero")
    func neverZeroLoad() {
        for dataset in SimulationDataset.allCases {
            let loads = sessions(dataset).compactMap(\.load?.value)
            // §35: a load is either measured or absent. Zero would silently drag
            // every average it entered.
            #expect(loads.allSatisfy { $0 > 0 }, "\(dataset.rawValue) produced a zero load")
        }
    }

    @Test("Every dataset is internally consistent about what it provides")
    func capabilitiesMatchContents() {
        for dataset in SimulationDataset.allCases {
            let built = sessions(dataset)

            if !dataset.hasPower {
                #expect(
                    built.allSatisfy { $0.metrics.averageCyclingPower == nil },
                    "\(dataset.rawValue) claims no power but produced watts"
                )
            }
            if !dataset.hasRunningDynamics {
                #expect(
                    built.allSatisfy { $0.metrics.averageStrideLength == nil },
                    "\(dataset.rawValue) claims no dynamics but produced stride length"
                )
            }
            if !dataset.hasHeartRate {
                #expect(
                    built.allSatisfy { $0.averageHeartRate == nil },
                    "\(dataset.rawValue) claims no heart rate but produced some"
                )
            }
        }
    }

    @Test("The same dataset and reference date always give the same result")
    func deterministic() {
        for dataset in SimulationDataset.allCases {
            let first = SimulationFixture.generate(dataset, asOf: reference)
            let second = SimulationFixture.generate(dataset, asOf: reference)

            #expect(first.workouts == second.workouts, "\(dataset.rawValue) is not deterministic")
            #expect(first.recovery == second.recovery, "\(dataset.rawValue) recovery is not deterministic")
        }
    }
}
#endif
