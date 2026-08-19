import Foundation
import HealthKit

/// Reads completed workouts from HealthKit and normalizes them.
///
/// `HKHealthStore` is safe to use across threads but is not annotated
/// `Sendable`, hence the unchecked conformance.
final class HealthKitWorkoutImporter: HealthDataProviding, @unchecked Sendable {
    /// Shared with the recovery and history extensions, which query the same
    /// store rather than opening their own.
    let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        let workoutTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceSwimming),
            HKQuantityType(.runningSpeed),
            HKQuantityType(.runningPower),
            HKQuantityType(.runningStrideLength),
            HKQuantityType(.runningGroundContactTime),
            HKQuantityType(.runningVerticalOscillation),
            HKQuantityType(.cyclingSpeed),
            HKQuantityType(.cyclingCadence),
            HKQuantityType(.cyclingPower),
            HKQuantityType(.cyclingFunctionalThresholdPower),
            HKQuantityType(.workoutEffortScore),
            HKQuantityType(.estimatedWorkoutEffortScore)
        ]
        return workoutTypes.union(Self.recoveryReadTypes)
    }

    /// HealthKit never discloses whether *read* access was granted — that is a
    /// privacy guarantee, not an omission. `.authorized` here means only that the
    /// permission sheet has already been shown; a denied read returns no samples
    /// rather than an error, which is indistinguishable from having no workouts.
    var authorizationStatus: HealthAuthorizationStatus {
        get async {
            guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
            switch try? await requestStatus() {
            case .unnecessary: return .authorized
            case .shouldRequest: return .notDetermined
            default: return .notDetermined
            }
        }
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthDataError.unavailableOnThisDevice
        }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func workouts(from startDate: Date, to endDate: Date) async throws -> [ImportedWorkout] {
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
        return await withEffort(workouts)
    }

    /// Fills in each workout's effort score.
    ///
    /// Concurrent because every workout needs its own relationship query, and a
    /// year of history run serially would take noticeably long.
    func withEffort(_ workouts: [HKWorkout]) async -> [ImportedWorkout] {
        await withTaskGroup(of: (Int, ImportedWorkout)?.self) { group in
            for (index, workout) in workouts.enumerated() {
                group.addTask {
                    guard var imported = Self.normalize(workout) else { return nil }
                    let effort = await self.effort(for: workout)
                    imported.metrics.workoutEffort = effort.rated
                    imported.metrics.estimatedWorkoutEffort = effort.estimated
                    return (index, imported)
                }
            }

            var results: [(Int, ImportedWorkout)] = []
            for await result in group {
                if let result { results.append(result) }
            }
            // The task group finishes out of order; the caller expects the sort
            // the query asked for.
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Apple's effort scores for one workout.
    ///
    /// §27 keeps the rated and estimated scores apart: one is the athlete's own
    /// judgement, the other is the system guessing.
    func effort(for workout: HKWorkout) async -> (rated: Double?, estimated: Double?) {
        let related = HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil)

        async let rated = effortValue(HKQuantityType(.workoutEffortScore), related: related)
        async let estimated = effortValue(HKQuantityType(.estimatedWorkoutEffortScore), related: related)
        return (await rated, await estimated)
    }

    private func effortValue(_ type: HKQuantityType, related: NSPredicate) async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: related)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        return try? await descriptor.result(for: store)
            .first?
            .quantity
            .doubleValue(for: .appleEffortScore())
    }

    func dailyActivity(on date: Date) async throws -> DailyActivity {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthDataError.unavailableOnThisDevice
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        let range = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])

        async let steps = sum(HKQuantityType(.stepCount), in: range)
        async let distance = sum(HKQuantityType(.distanceWalkingRunning), in: range)

        return DailyActivity(
            steps: try await steps.map { Int($0.doubleValue(for: .count())) },
            distanceMeters: try await distance.map { $0.doubleValue(for: .meter()) }
        )
    }

    private func sum(_ type: HKQuantityType, in predicate: NSPredicate) async throws -> HKQuantity? {
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        return try await descriptor.result(for: store)?.sumQuantity()
    }

    func hourlySteps(on date: Date) async throws -> [SamplePoint] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        return try await steps(from: start, to: end, bucket: DateComponents(hour: 1))
    }

    func dailySteps(from startDate: Date, to endDate: Date) async throws -> [SamplePoint] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
        return try await steps(from: start, to: end, bucket: DateComponents(day: 1))
    }

    private func steps(
        from start: Date,
        to end: Date,
        bucket: DateComponents
    ) async throws -> [SamplePoint] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(
                type: HKQuantityType(.stepCount),
                predicate: HKQuery.predicateForSamples(withStart: start, end: end)
            ),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: bucket
        )

        let collection = try await descriptor.result(for: store)
        var points: [SamplePoint] = []

        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            let steps = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0
            points.append(SamplePoint(date: statistics.startDate, value: steps))
        }
        return points
    }

    func samples(forWorkout id: UUID) async throws -> WorkoutSamples {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthDataError.unavailableOnThisDevice
        }
        guard let workout = try await workout(with: id) else { return WorkoutSamples() }

        // Scoped by time rather than by workout association: samples recorded
        // alongside a session are not always linked to it, and an association
        // filter silently returns nothing when they are not.
        let scope = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: [.strictStartDate]
        )
        let minute = DateComponents(minute: 1)

        async let heartRate = series(
            HKQuantityType(.heartRate),
            unit: .heartRate,
            options: .discreteAverage,
            scope: scope,
            workout: workout,
            interval: minute
        )
        async let cadence = series(
            HKQuantityType(.stepCount),
            unit: .count(),
            options: .cumulativeSum,
            scope: scope,
            workout: workout,
            interval: minute
        )
        async let distance = series(
            workout.workoutActivityType.sport?.healthKitDistanceType ?? HKQuantityType(.distanceWalkingRunning),
            unit: .meter(),
            options: .cumulativeSum,
            scope: scope,
            workout: workout,
            interval: minute
        )
        async let energy = series(
            HKQuantityType(.activeEnergyBurned),
            unit: .kilocalorie(),
            options: .cumulativeSum,
            scope: scope,
            workout: workout,
            interval: minute
        )

        return WorkoutSamples(
            heartRate: try await heartRate,
            cadence: try await cadence,
            distancePerMinute: try await distance,
            energy: try await energy,
            swimLengths: Self.lengthPoints(from: workout)
        )
    }

    private func workout(with id: UUID) async throws -> HKWorkout? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForObject(with: id))],
            sortDescriptors: [],
            limit: 1
        )
        return try await descriptor.result(for: store).first
    }

    /// Bucketed rather than raw: a 30 minute run can hold hundreds of heart-rate
    /// samples, which is far more than a chart can show usefully.
    private func series(
        _ type: HKQuantityType,
        unit: HKUnit,
        options: HKStatisticsOptions,
        scope: NSPredicate,
        workout: HKWorkout,
        interval: DateComponents
    ) async throws -> [SamplePoint] {
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: scope),
            options: options,
            anchorDate: workout.startDate,
            intervalComponents: interval
        )

        let collection = try await descriptor.result(for: store)
        var points: [SamplePoint] = []

        collection.enumerateStatistics(from: workout.startDate, to: workout.endDate) { statistics, _ in
            let quantity = options == .cumulativeSum
                ? statistics.sumQuantity()
                : statistics.averageQuantity()
            guard let value = quantity?.doubleValue(for: unit) else { return }
            points.append(SamplePoint(date: statistics.startDate, value: value))
        }
        return points
    }

    private static func lengthPoints(from workout: HKWorkout) -> [SwimLengthPoint] {
        let lengths = workout.swimmingLengths.sorted { $0.interval.start < $1.interval.start }
        var points: [SwimLengthPoint] = []
        var previousEnd: Date?

        for (index, length) in lengths.enumerated() {
            let rested = previousEnd.map { length.interval.start.timeIntervalSince($0) > restThreshold } ?? false
            points.append(
                SwimLengthPoint(
                    index: index + 1,
                    start: length.interval.start,
                    seconds: length.interval.duration,
                    meters: length.meters,
                    followedRest: rested
                )
            )
            previousEnd = length.interval.end
        }
        return points
    }

    private func requestStatus() async throws -> HKAuthorizationRequestStatus {        try await withCheckedThrowingContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    /// Returns `nil` for anything TriLoop does not train, so a yoga session or a
    /// walk never lands in the training analysis.
    static func normalize(_ workout: HKWorkout) -> ImportedWorkout? {
        guard let sport = workout.workoutActivityType.sport else { return nil }
        let lengths = sport == .swimming ? workout.swimmingLengths : []

        return ImportedWorkout(
            healthKitUUID: workout.uuid,
            sport: sport,
            startDate: workout.startDate,
            endDate: workout.endDate,
            duration: workout.duration,
            distanceMeters: workout.sum(sport.healthKitDistanceType, in: .meter()),
            averageHeartRate: workout.average(HKQuantityType(.heartRate), in: .heartRate),
            maximumHeartRate: workout.maximum(HKQuantityType(.heartRate), in: .heartRate),
            elevationAscendedMeters: workout.elevationAscendedMeters,
            swimmingLengths: lengths.isEmpty ? nil : lengths.count,
            swimmingStrokeCount: workout.sum(HKQuantityType(.swimmingStrokeCount), in: .count()),
            longestContinuousSwimMeters: Self.longestContinuous(in: lengths),
            metrics: Self.recordedMetrics(of: workout, sport: sport),
            source: workout.sourceRevision.source.bundleIdentifier
        )
    }

    /// Sport-specific sensor values, taken only where they mean something.
    ///
    /// §27: none of these may be required. A first-generation watch reports
    /// speed and nothing else, and a rider without a power meter has no watts —
    /// both are normal, so every reading here is allowed to be absent.
    ///
    /// A nil sport is an activity TriLoop does not train, which still has an
    /// effort score and nothing sport-specific worth reading.
    static func recordedMetrics(of workout: HKWorkout, sport: Sport?) -> RecordedMetrics {
        var metrics = RecordedMetrics(averageCadence: averageCadence(of: workout))

        // Effort is deliberately not read here. It is stored as samples *related*
        // to the workout rather than collected by it, so workout statistics
        // never return it — see `effort(for:)`.

        switch sport {
        case .running:
            metrics.averageRunningSpeed = workout.average(HKQuantityType(.runningSpeed), in: .metersPerSecond)
            metrics.averageRunningPower = workout.average(HKQuantityType(.runningPower), in: .watt())
            metrics.averageStrideLength = workout.average(HKQuantityType(.runningStrideLength), in: .meter())
            metrics.averageGroundContactTime = workout.average(
                HKQuantityType(.runningGroundContactTime),
                in: .secondUnit(with: .milli)
            )
            metrics.averageVerticalOscillation = workout.average(
                HKQuantityType(.runningVerticalOscillation),
                in: .meterUnit(with: .centi)
            )

        case .cycling:
            metrics.averageCyclingSpeed = workout.average(HKQuantityType(.cyclingSpeed), in: .metersPerSecond)
            metrics.averageCyclingCadence = workout.average(HKQuantityType(.cyclingCadence), in: .rpm)
            metrics.averageCyclingPower = workout.average(HKQuantityType(.cyclingPower), in: .watt())
            // FTP is deliberately not read here. It is a standing athlete value
            // like VO₂ max, not something a ride measures, so workout statistics
            // never carry it. It needs its own most-recent-sample query.

        case .swimming:
            break

        case nil:
            break
        }

        return metrics
    }
    /// Steps per minute across the session. Only meaningful on foot, so a ride's
    /// incidental steps are not reported as cadence.
    private static func averageCadence(of workout: HKWorkout) -> Double? {
        guard workout.workoutActivityType == .running, workout.duration > 0 else { return nil }
        guard let steps = workout.sum(HKQuantityType(.stepCount), in: .count()) else { return nil }
        return steps / (workout.duration / 60)
    }

    /// A pause of more than this between lengths counts as rest, ending the
    /// continuous block. Turns take a couple of seconds, so the threshold has to
    /// sit above a turn and below a deliberate stop.
    private static let restThreshold: TimeInterval = 8

    /// Longest run of consecutive lengths with no rest between them.
    static func longestContinuous(in lengths: [SwimLength]) -> Double? {
        guard !lengths.isEmpty else { return nil }

        var longest: Double = 0
        var current: Double = 0
        var previousEnd: Date?

        for length in lengths.sorted(by: { $0.interval.start < $1.interval.start }) {
            if let previousEnd, length.interval.start.timeIntervalSince(previousEnd) > restThreshold {
                current = 0
            }
            current += length.meters
            longest = max(longest, current)
            previousEnd = length.interval.end
        }

        return longest > 0 ? longest : nil
    }
}

/// One pool length, taken from a lap event.
struct SwimLength: Equatable, Sendable {
    let interval: DateInterval
    let meters: Double
}

extension HKWorkoutActivityType {
    var sport: Sport? {
        switch self {
        case .running: .running
        case .cycling: .cycling
        case .swimming: .swimming
        default: nil
        }
    }
}

extension Sport {
    var healthKitDistanceType: HKQuantityType {
        switch self {
        case .running: HKQuantityType(.distanceWalkingRunning)
        case .cycling: HKQuantityType(.distanceCycling)
        case .swimming: HKQuantityType(.distanceSwimming)
        }
    }
}

private extension HKUnit {
    static let heartRate = HKUnit.count().unitDivided(by: .minute())
    static let metersPerSecond = HKUnit.meter().unitDivided(by: .second())
    static let rpm = HKUnit.count().unitDivided(by: .minute())
}

/// `totalDistance` and friends are deprecated; statistics are the supported path
/// and correctly return `nil` when a metric was never recorded.
private extension HKWorkout {
    func sum(_ type: HKQuantityType, in unit: HKUnit) -> Double? {
        statistics(for: type)?.sumQuantity()?.doubleValue(for: unit)
    }

    func average(_ type: HKQuantityType, in unit: HKUnit) -> Double? {
        statistics(for: type)?.averageQuantity()?.doubleValue(for: unit)
    }

    func maximum(_ type: HKQuantityType, in unit: HKUnit) -> Double? {
        statistics(for: type)?.maximumQuantity()?.doubleValue(for: unit)
    }

    var elevationAscendedMeters: Double? {
        (metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter())
    }

    /// Pool swims record one lap event per length. The pool length lives on the
    /// *workout* — `HKMetadataKeyLapLength` is documented as "may be set on an
    /// HKWorkout object" — so reading it off the event finds nothing. Open-water
    /// swims have no laps, so this is empty for them.
    var swimmingLengths: [SwimLength] {
        let poolLength = (metadata?[HKMetadataKeyLapLength] as? HKQuantity)?
            .doubleValue(for: .meter())

        return (workoutEvents ?? [])
            .filter { $0.type == .lap }
            .compactMap { event in
                let eventLength = (event.metadata?[HKMetadataKeyLapLength] as? HKQuantity)?
                    .doubleValue(for: .meter())
                guard let meters = eventLength ?? poolLength else { return nil }
                return SwimLength(interval: event.dateInterval, meters: meters)
            }
    }
}

#if DEBUG
extension HKWorkout {
    /// Bridges the file-private lap reading to the history tool.
    var historySwimmingLengthCount: Int { swimmingLengths.count }
}
#endif

