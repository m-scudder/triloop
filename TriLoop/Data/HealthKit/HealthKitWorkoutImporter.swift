import Foundation
import HealthKit

/// Reads completed workouts from HealthKit and normalizes them.
///
/// `HKHealthStore` is safe to use across threads but is not annotated
/// `Sendable`, hence the unchecked conformance.
final class HealthKitWorkoutImporter: HealthDataProviding, @unchecked Sendable {
    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceSwimming)
        ]
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

        return try await descriptor.result(for: store).compactMap(Self.normalize)
    }

    private func requestStatus() async throws -> HKAuthorizationRequestStatus {
        try await withCheckedThrowingContinuation { continuation in
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
            source: workout.sourceRevision.source.bundleIdentifier
        )
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

    /// Pool swims record one lap event per length, carrying the pool length in
    /// metadata. Open-water swims have no laps, so this is empty for them.
    var swimmingLengths: [SwimLength] {
        (workoutEvents ?? [])
            .filter { $0.type == .lap }
            .compactMap { event in
                guard let quantity = event.metadata?[HKMetadataKeyLapLength] as? HKQuantity else {
                    return nil
                }
                return SwimLength(
                    interval: event.dateInterval,
                    meters: quantity.doubleValue(for: .meter())
                )
            }
    }
}
