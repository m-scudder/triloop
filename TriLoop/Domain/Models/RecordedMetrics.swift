import Foundation

/// Sensor-derived values from a completed workout that the plan does not need
/// to reason about structurally.
///
/// Stored as a single `Codable` attribute rather than one column per metric, the
/// same way `TrainingParameters` is. Adding a field here changes no `@Model`
/// shape, so the schema version does not move and no migration stage is needed —
/// which matters because the interesting metrics differ by sport and by watch,
/// and the list will keep growing.
///
/// Every field is optional: HealthKit records what the device happened to
/// capture, and absence is normal rather than an error.
struct RecordedMetrics: Codable, Equatable, Sendable {
    /// Steps per minute. A proxy for running cadence, taken from `stepCount`.
    var averageCadence: Double?

    init(averageCadence: Double? = nil) {
        self.averageCadence = averageCadence
    }

    /// Decoded key by key so a record written by an older build, which had fewer
    /// fields, still loads. The synthesized decoder would throw on the missing
    /// keys and take the whole workout summary with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func value<T: Decodable>(_ key: CodingKeys) -> T? {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? nil
        }

        averageCadence = value(.averageCadence)
    }

    var isEmpty: Bool { averageCadence == nil }
}
