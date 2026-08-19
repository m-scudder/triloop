#if DEBUG
import Foundation

/// How many workouts actually carried a given metric.
///
/// §18: the point is to learn what this device really records. A metric that is
/// 0 / 17 is not a bug — it usually means the hardware never produced it.
struct MetricCoverage: Identifiable, Equatable, Sendable {
    let name: String
    /// Workouts where the metric could meaningfully exist.
    let applicable: Int
    let available: Int

    var id: String { name }

    /// §19: absent everywhere despite being applicable is worth looking at;
    /// absent because nothing could have recorded it is not.
    var isEntirelyAbsent: Bool { applicable > 0 && available == 0 }

    var summary: String {
        applicable == 0 ? "Not applicable" : "\(available) / \(applicable)"
    }
}

/// Builds the §18 metric coverage report from real historical workouts.
///
/// Applicability is per sport: cycling power on a run is not a missing metric,
/// it is a meaningless one, and counting it as missing would make every report
/// look broken.
enum HistoricalMetricCoverage {

    static func report(for records: [HealthWorkoutRecord]) -> [MetricCoverage] {
        [
            coverage("Heart Rate", records, applies: { _ in true }, has: { $0.averageHeartRate != nil }),
            coverage("Active Energy", records, applies: { _ in true }, has: { $0.energyKilocalories != nil }),
            coverage("Workout Effort", records, applies: { _ in true }, has: { $0.metrics.appleEffort != nil }),

            coverage("Running Speed", records, applies: running, has: { $0.metrics.averageRunningSpeed != nil }),
            coverage("Running Power", records, applies: running, has: { $0.metrics.averageRunningPower != nil }),
            coverage("Stride Length", records, applies: running, has: { $0.metrics.averageStrideLength != nil }),
            coverage("Ground Contact Time", records, applies: running, has: { $0.metrics.averageGroundContactTime != nil }),
            coverage("Vertical Oscillation", records, applies: running, has: { $0.metrics.averageVerticalOscillation != nil }),

            coverage("Cycling Speed", records, applies: cycling, has: { $0.metrics.averageCyclingSpeed != nil }),
            coverage("Cycling Cadence", records, applies: cycling, has: { $0.metrics.averageCyclingCadence != nil }),
            coverage("Cycling Power", records, applies: cycling, has: { $0.metrics.averageCyclingPower != nil }),

            coverage("Swim Lengths", records, applies: swimming, has: { ($0.swimmingLengths ?? 0) > 0 }),
            coverage("Distance", records, applies: { $0.sport != nil }, has: { $0.distanceMeters != nil })
        ]
    }

    private static let running: (HealthWorkoutRecord) -> Bool = { $0.sport == .running }
    private static let cycling: (HealthWorkoutRecord) -> Bool = { $0.sport == .cycling }
    private static let swimming: (HealthWorkoutRecord) -> Bool = { $0.sport == .swimming }

    private static func coverage(
        _ name: String,
        _ records: [HealthWorkoutRecord],
        applies: (HealthWorkoutRecord) -> Bool,
        has: (HealthWorkoutRecord) -> Bool
    ) -> MetricCoverage {
        let applicable = records.filter(applies)
        return MetricCoverage(
            name: name,
            applicable: applicable.count,
            available: applicable.count(where: has)
        )
    }
}

/// The per-workout ✓/✗ list from §20.
extension HealthWorkoutRecord {
    struct MetricPresence: Identifiable, Equatable, Sendable {
        let name: String
        let isPresent: Bool

        var id: String { name }
    }

    /// Only metrics that could apply to this activity, so a swim is never shown
    /// as missing cycling power.
    var metricPresence: [MetricPresence] {
        var entries: [MetricPresence] = [
            MetricPresence(name: "Heart Rate", isPresent: averageHeartRate != nil),
            MetricPresence(name: "Active Energy", isPresent: energyKilocalories != nil),
            MetricPresence(name: "Workout Effort", isPresent: metrics.appleEffort != nil)
        ]

        switch sport {
        case .running:
            entries += [
                MetricPresence(name: "Distance", isPresent: distanceMeters != nil),
                MetricPresence(name: "Running Speed", isPresent: metrics.averageRunningSpeed != nil),
                MetricPresence(name: "Step Cadence", isPresent: metrics.averageCadence != nil),
                MetricPresence(name: "Running Power", isPresent: metrics.averageRunningPower != nil),
                MetricPresence(name: "Stride Length", isPresent: metrics.averageStrideLength != nil),
                MetricPresence(name: "Ground Contact Time", isPresent: metrics.averageGroundContactTime != nil),
                MetricPresence(name: "Vertical Oscillation", isPresent: metrics.averageVerticalOscillation != nil)
            ]

        case .cycling:
            entries += [
                MetricPresence(name: "Distance", isPresent: distanceMeters != nil),
                MetricPresence(name: "Cycling Speed", isPresent: metrics.averageCyclingSpeed != nil),
                MetricPresence(name: "Cycling Cadence", isPresent: metrics.averageCyclingCadence != nil),
                MetricPresence(name: "Cycling Power", isPresent: metrics.averageCyclingPower != nil)
            ]

        case .swimming:
            entries += [
                MetricPresence(name: "Distance", isPresent: distanceMeters != nil),
                MetricPresence(name: "Swim Lengths", isPresent: (swimmingLengths ?? 0) > 0)
            ]

        case nil:
            break
        }

        return entries
    }
}
#endif
