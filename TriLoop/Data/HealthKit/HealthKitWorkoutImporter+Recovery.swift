import Foundation
import HealthKit

extension HealthKitWorkoutImporter {

    /// Read types behind §40's recovery and fitness metrics.
    ///
    /// Requested alongside the workout types so the athlete sees one permission
    /// sheet rather than two.
    static var recoveryReadTypes: Set<HKObjectType> {
        [
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.vo2Max),
            HKQuantityType(.heartRateRecoveryOneMinute),
            HKCategoryType(.sleepAnalysis)
        ]
    }

    func recoverySeries(
        _ metric: RecoveryMetric,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [SamplePoint] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthDataError.unavailableOnThisDevice
        }

        // Sleep is recorded as periods rather than readings, so it is totalled
        // per night instead of averaged per day.
        if metric == .sleepDuration {
            return try await sleepSeries(from: startDate, to: endDate)
        }

        guard let (type, unit) = Self.quantity(for: metric) else { return [] }

        let range = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: range),
            options: .discreteAverage,
            anchorDate: Calendar.current.startOfDay(for: startDate),
            intervalComponents: DateComponents(day: 1)
        )

        let results = try await descriptor.result(for: store)
        var points: [SamplePoint] = []

        results.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
            // A day with no reading contributes nothing: §55 forbids filling the
            // gap with a zero that would flatten every baseline.
            guard let value = statistics.averageQuantity()?.doubleValue(for: unit) else { return }
            points.append(SamplePoint(date: statistics.startDate, value: value))
        }

        return points
    }

    private static func quantity(for metric: RecoveryMetric) -> (HKQuantityType, HKUnit)? {
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

        return switch metric {
        case .restingHeartRate:
            (HKQuantityType(.restingHeartRate), beatsPerMinute)
        case .heartRateVariability:
            (HKQuantityType(.heartRateVariabilitySDNN), .secondUnit(with: .milli))
        case .cardioFitness:
            (
                HKQuantityType(.vo2Max),
                HKUnit(from: "ml/kg*min")
            )
        case .heartRateRecovery:
            (HKQuantityType(.heartRateRecoveryOneMinute), beatsPerMinute)
        case .sleepDuration:
            nil
        }
    }

    /// Hours asleep per night, attributed to the day the athlete woke up.
    ///
    /// Sleep crosses midnight, so bucketing by sample start would split one
    /// night across two days and halve both.
    private func sleepSeries(from startDate: Date, to endDate: Date) async throws -> [SamplePoint] {
        let range = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: range)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )

        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]

        let calendar = Calendar.current
        var hoursByDay: [Date: Double] = [:]

        for sample in try await descriptor.result(for: store) where asleep.contains(sample.value) {
            let day = calendar.startOfDay(for: sample.endDate)
            hoursByDay[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 3_600
        }

        return hoursByDay
            .map { SamplePoint(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
    }
}
