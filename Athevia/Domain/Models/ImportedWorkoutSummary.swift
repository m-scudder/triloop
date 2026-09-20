import Foundation
import SwiftData

/// Normalized record of a workout imported from HealthKit.
///
/// HealthKit remains the source of truth (§34); this stores only the values the
/// training engine needs, keyed by `healthKitUUID` so a repeated import updates
/// nothing and duplicates nothing.
@Model
final class ImportedWorkoutSummary {
    var id: UUID
    @Attribute(.unique) var healthKitUUID: UUID
    var sport: Sport
    var startDate: Date
    var endDate: Date
    var duration: TimeInterval
    var distanceMeters: Double?
    var averageHeartRate: Double?
    var maximumHeartRate: Double?
    var elevationAscendedMeters: Double?
    var swimmingLengths: Int?
    var swimmingStrokeCount: Double?
    var longestContinuousSwimMeters: Double?
    /// Extensible bag of sensor values. New metrics go in here rather than
    /// becoming columns, so the schema version does not move.
    ///
    /// Optional because SwiftData does not apply a Swift default to rows that
    /// were stored without the property: the generated getter casts whatever is
    /// there, and a non-optional type traps on the `nil`.
    var metrics: RecordedMetrics?
    var source: String?
    var importedAt: Date

    var workout: PlannedWorkout?

    init(
        id: UUID = UUID(),
        healthKitUUID: UUID,
        sport: Sport,
        startDate: Date,
        endDate: Date,
        duration: TimeInterval,
        distanceMeters: Double? = nil,
        averageHeartRate: Double? = nil,
        maximumHeartRate: Double? = nil,
        elevationAscendedMeters: Double? = nil,
        swimmingLengths: Int? = nil,
        swimmingStrokeCount: Double? = nil,
        longestContinuousSwimMeters: Double? = nil,
        metrics: RecordedMetrics? = nil,
        source: String? = nil,
        importedAt: Date = .now
    ) {
        self.id = id
        self.healthKitUUID = healthKitUUID
        self.sport = sport
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.maximumHeartRate = maximumHeartRate
        self.elevationAscendedMeters = elevationAscendedMeters
        self.swimmingLengths = swimmingLengths
        self.swimmingStrokeCount = swimmingStrokeCount
        self.longestContinuousSwimMeters = longestContinuousSwimMeters
        self.metrics = metrics
        self.source = source
        self.importedAt = importedAt
    }

    convenience init(_ imported: ImportedWorkout, importedAt: Date = .now) {
        self.init(
            healthKitUUID: imported.healthKitUUID,
            sport: imported.sport,
            startDate: imported.startDate,
            endDate: imported.endDate,
            duration: imported.duration,
            distanceMeters: imported.distanceMeters,
            averageHeartRate: imported.averageHeartRate,
            maximumHeartRate: imported.maximumHeartRate,
            elevationAscendedMeters: imported.elevationAscendedMeters,
            swimmingLengths: imported.swimmingLengths,
            swimmingStrokeCount: imported.swimmingStrokeCount,
            longestContinuousSwimMeters: imported.longestContinuousSwimMeters,
            metrics: imported.metrics,
            source: imported.source,
            importedAt: importedAt
        )
    }

    var imported: ImportedWorkout {
        ImportedWorkout(
            healthKitUUID: healthKitUUID,
            sport: sport,
            startDate: startDate,
            endDate: endDate,
            duration: duration,
            distanceMeters: distanceMeters,
            averageHeartRate: averageHeartRate,
            maximumHeartRate: maximumHeartRate,
            elevationAscendedMeters: elevationAscendedMeters,
            swimmingLengths: swimmingLengths,
            swimmingStrokeCount: swimmingStrokeCount,
            longestContinuousSwimMeters: longestContinuousSwimMeters,
            metrics: metrics ?? RecordedMetrics(),
            source: source
        )
    }
}
