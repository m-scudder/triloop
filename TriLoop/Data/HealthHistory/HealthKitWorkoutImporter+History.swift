#if DEBUG
import Foundation
import HealthKit

extension HealthKitWorkoutImporter: HealthHistoryReading {

    /// Every workout in the range, including types TriLoop does not train.
    ///
    /// Uses no predicate beyond the date range, so nothing is filtered out on
    /// the way in — the whole point is to see what is actually there.
    func workoutHistory(from startDate: Date, to endDate: Date) async throws -> [HealthWorkoutRecord] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthDataError.unavailableOnThisDevice
        }

        let range = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: [.strictStartDate]
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(range)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )

        let workouts = try await descriptor.result(for: store)

        return await withTaskGroup(of: (Int, HealthWorkoutRecord).self) { group in
            for (index, workout) in workouts.enumerated() {
                group.addTask {
                    var record = Self.describe(workout)
                    let effort = await self.effort(for: workout)
                    record.metrics.workoutEffort = effort.rated
                    record.metrics.estimatedWorkoutEffort = effort.estimated
                    return (index, record)
                }
            }

            var results: [(Int, HealthWorkoutRecord)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    static func describe(_ workout: HKWorkout) -> HealthWorkoutRecord {
        let sport = workout.workoutActivityType.sport

        return HealthWorkoutRecord(
            id: workout.uuid,
            activityName: workout.workoutActivityType.historyName,
            sport: sport,
            start: workout.startDate,
            end: workout.endDate,
            duration: workout.duration,
            distanceMeters: workout.historyDistanceMeters,
            averageHeartRate: workout.historyAverageHeartRate,
            energyKilocalories: workout.historySum(HKQuantityType(.activeEnergyBurned), in: .kilocalorie()),
            swimmingLengths: sport == .swimming ? workout.historySwimmingLengthCount : nil,
            metrics: HealthKitWorkoutImporter.recordedMetrics(of: workout, sport: sport),
            sourceName: workout.sourceRevision.source.name
        )
    }
}

private extension HKWorkout {
    /// Whichever distance the activity actually recorded, or `nil`.
    ///
    /// Reported as `nil` rather than `0` when absent: "no distance recorded" and
    /// "did not move" must stay distinguishable.
    var historyDistanceMeters: Double? {
        let types: [HKQuantityType] = switch workoutActivityType {
        case .swimming: [HKQuantityType(.distanceSwimming)]
        case .cycling: [HKQuantityType(.distanceCycling)]
        default: [HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)]
        }

        for type in types {
            if let value = historySum(type, in: .meter()), value > 0 { return value }
        }
        return nil
    }

    var historyAverageHeartRate: Double? {
        statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?
            .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }

    func historySum(_ type: HKQuantityType, in unit: HKUnit) -> Double? {
        statistics(for: type)?.sumQuantity()?.doubleValue(for: unit)
    }
}

extension HKWorkoutActivityType {
    /// A readable name for the history screen.
    ///
    /// Only covers what turns up in practice; anything else shows its raw value
    /// rather than being silently labelled "Other", which would hide it.
    var historyName: String {
        switch self {
        case .running: "Running"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .walking: "Walking"
        case .hiking: "Hiking"
        case .functionalStrengthTraining: "Functional Strength Training"
        case .traditionalStrengthTraining: "Traditional Strength Training"
        case .coreTraining: "Core Training"
        case .highIntensityIntervalTraining: "HIIT"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .rowing: "Rowing"
        case .elliptical: "Elliptical"
        case .stairClimbing, .stairs: "Stair Climbing"
        case .flexibility: "Flexibility"
        case .cooldown: "Cooldown"
        case .preparationAndRecovery: "Preparation and Recovery"
        case .mixedCardio: "Mixed Cardio"
        case .crossTraining: "Cross Training"
        case .dance, .cardioDance: "Dance"
        case .badminton: "Badminton"
        case .tennis: "Tennis"
        case .basketball: "Basketball"
        case .soccer: "Soccer"
        case .cricket: "Cricket"
        case .tableTennis: "Table Tennis"
        case .golf: "Golf"
        case .boxing, .kickboxing: "Boxing"
        case .martialArts: "Martial Arts"
        case .climbing: "Climbing"
        case .jumpRope: "Jump Rope"
        case .other: "Other"
        default: "Activity type \(rawValue)"
        }
    }
}
#endif
