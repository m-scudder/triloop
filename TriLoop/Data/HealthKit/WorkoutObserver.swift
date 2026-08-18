import Foundation
import HealthKit

/// Wakes TriLoop when a workout is saved to HealthKit, so a finished session
/// links itself without the athlete remembering to import.
///
/// `HKObserverQuery` only says *that* something changed, never what — the
/// handler is expected to run its own fetch, which here is the ordinary import.
final class WorkoutObserver: @unchecked Sendable {
    private let store = HKHealthStore()
    private var query: HKObserverQuery?

    /// - Parameter onChange: Runs on every notification. Must finish before the
    ///   observer reports completion, so it is awaited rather than fired off.
    func start(onChange: @escaping @Sendable () async -> Void) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthDataError.unavailableOnThisDevice
        }
        guard query == nil else { return }

        let workoutType = HKObjectType.workoutType()

        let observer = HKObserverQuery(
            sampleType: workoutType,
            predicate: nil
        ) { _, completionHandler, _ in
            // The completion handler must be called even when the import fails,
            // or the system keeps re-delivering the same notification.
            Task {
                await onChange()
                completionHandler()
            }
        }

        store.execute(observer)
        query = observer

        // Workouts have no minimum cadence, unlike step count, so immediate
        // delivery is honoured rather than quietly downgraded to hourly.
        try await store.enableBackgroundDelivery(for: workoutType, frequency: .immediate)
    }

    func stop() async {
        if let query {
            store.stop(query)
            self.query = nil
        }
        try? await store.disableBackgroundDelivery(for: HKObjectType.workoutType())
    }

    var isRunning: Bool { query != nil }
}
