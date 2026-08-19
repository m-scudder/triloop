#if DEBUG
import Foundation

/// One workout exactly as HealthKit holds it, before TriLoop's opinions apply.
///
/// Deliberately not `ImportedWorkout`: that type only models the three sports
/// TriLoop trains, so functional training, walks and HIIT cannot be expressed in
/// it at all. This exists to *look* at a real history, including everything the
/// importer would discard.
struct HealthWorkoutRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let activityName: String
    /// Non-nil only when TriLoop trains this activity.
    let sport: Sport?
    let start: Date
    let end: Date
    let duration: TimeInterval
    let distanceMeters: Double?
    let averageHeartRate: Double?
    let energyKilocalories: Double?
    let swimmingLengths: Int?
    /// The same sensor values the importer would store, so the coverage report
    /// describes production ingestion rather than a parallel reading of Health.
    var metrics: RecordedMetrics
    let sourceName: String?

    var isTrainedByTriLoop: Bool { sport != nil }
}

/// Read-only access to raw workout history.
///
/// Separate from `HealthDataProviding` on purpose: this never feeds training,
/// never writes, and exists only so a real history can be inspected. Keeping it
/// off the production protocol means it cannot be reached by accident.
protocol HealthHistoryReading: Sendable {
    func workoutHistory(from startDate: Date, to endDate: Date) async throws -> [HealthWorkoutRecord]
}
#endif
