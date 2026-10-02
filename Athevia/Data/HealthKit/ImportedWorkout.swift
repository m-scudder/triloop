import CryptoKit
import Foundation

/// Stable identity supplied by whichever service delivered a workout.
///
/// The persisted model still stores the UUID in its legacy `healthKitUUID`
/// column for schema compatibility, but the ingestion layer no longer assumes
/// that UUID came from HealthKit. External providers derive the same UUID from
/// their provider key + activity id on every sync.
struct WorkoutImportIdentity: Equatable, Hashable, Sendable {
    let providerID: String
    let externalID: String
    let stableUUID: UUID

    var alias: WorkoutImportAlias {
        WorkoutImportAlias(
            providerID: providerID,
            externalID: externalID
        )
    }

    static func appleHealth(_ uuid: UUID) -> WorkoutImportIdentity {
        WorkoutImportIdentity(
            providerID: "appleHealth",
            externalID: uuid.uuidString.lowercased(),
            stableUUID: uuid
        )
    }

    static func external(
        providerID: String,
        externalID: String
    ) -> WorkoutImportIdentity {
        let canonical = providerID.lowercased()
            + ":"
            + externalID
        let digest = SHA256.hash(
            data: Data(canonical.utf8)
        )
        var bytes = Array(digest.prefix(16))

        // RFC 4122 variant + name-based version bits. The SHA-256 payload is
        // only used as a deterministic namespace hash, not for security.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))

        return WorkoutImportIdentity(
            providerID: providerID,
            externalID: externalID,
            stableUUID: uuid
        )
    }
}

struct WorkoutImportAlias: Codable, Equatable, Hashable, Sendable {
    let providerID: String
    let externalID: String
}

/// A completed workout, normalized away from HealthKit.
///
/// §10: HealthKit types stay at the boundary. Nothing downstream of the provider
/// knows `HKWorkout` exists, which is what keeps the matcher and the training
/// engine testable without entitlements or a device.
struct ImportedWorkout: Equatable, Sendable, Identifiable {
    /// Provider-neutral identity used for repeat-import and cross-source
    /// de-duplication.
    let identity: WorkoutImportIdentity
    let sport: Sport
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distanceMeters: Double?
    let averageHeartRate: Double?
    let maximumHeartRate: Double?
    let elevationAscendedMeters: Double?
    /// Pool lengths swum, from the workout's lap events.
    let swimmingLengths: Int?
    let swimmingStrokeCount: Double?
    /// Longest distance swum without stopping. §14 progresses on continuous
    /// swimming, which total distance alone cannot show.
    let longestContinuousSwimMeters: Double?
    /// Sensor values that need no schema column of their own.
    var metrics: RecordedMetrics
    /// Exact Athevia plan identity when the workout was recorded by Athevia Watch.
    let plannedWorkoutID: UUID?
    /// Fraction of the concrete structured prescription completed on Athevia Watch.
    let prescriptionCompletion: Double?
    let completedPrescriptionSteps: Int?
    let totalPrescriptionSteps: Int?
    /// Bundle identifier of the app that recorded it, e.g. Apple's Workout app.
    let source: String?

    var id: UUID { identity.stableUUID }
    var importID: UUID { identity.stableUUID }

    /// Compatibility for HealthKit-specific code/tests while callers migrate to
    /// provider-neutral identity.
    var healthKitUUID: UUID { importID }

    /// Explicit activity semantics for downstream matching and capability.
    /// `sport` remains the legacy single-sport carrier for compatibility.
    var discipline: Discipline {
        metrics.multisportSegments.isEmpty ? sport.discipline : .multisport
    }

    init(
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
        metrics: RecordedMetrics = RecordedMetrics(),
        plannedWorkoutID: UUID? = nil,
        prescriptionCompletion: Double? = nil,
        completedPrescriptionSteps: Int? = nil,
        totalPrescriptionSteps: Int? = nil,
        source: String? = nil
    ) {
        self.identity = .appleHealth(healthKitUUID)
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
        self.plannedWorkoutID = plannedWorkoutID
        self.prescriptionCompletion = prescriptionCompletion
        self.completedPrescriptionSteps = completedPrescriptionSteps
        self.totalPrescriptionSteps = totalPrescriptionSteps
        self.source = source
    }

    init(
        identity: WorkoutImportIdentity,
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
        metrics: RecordedMetrics = RecordedMetrics(),
        plannedWorkoutID: UUID? = nil,
        prescriptionCompletion: Double? = nil,
        completedPrescriptionSteps: Int? = nil,
        totalPrescriptionSteps: Int? = nil,
        source: String? = nil
    ) {
        self.identity = identity
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
        self.plannedWorkoutID = plannedWorkoutID
        self.prescriptionCompletion = prescriptionCompletion
        self.completedPrescriptionSteps = completedPrescriptionSteps
        self.totalPrescriptionSteps = totalPrescriptionSteps
        self.source = source
    }
}

extension ImportedWorkout {
    /// Feeds the training engine. Completion is supplied by the caller, which is
    /// the only party that knows what was planned.
    func result(completion: Double, prescribedRestSeconds: TimeInterval? = nil) -> WorkoutResult {
        WorkoutResult(
            sport: sport,
            completion: completion,
            durationSeconds: duration,
            distanceMeters: distanceMeters,
            averageHeartRate: averageHeartRate,
            prescribedRestSeconds: prescribedRestSeconds
        )
    }
}
