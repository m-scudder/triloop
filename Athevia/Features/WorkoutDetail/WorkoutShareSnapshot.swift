import Foundation

/// One headline value placed on the exported workout card.
struct WorkoutShareMetric: Equatable, Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

/// Only completed evidence belongs on a shared activity; targets are not results.
struct WorkoutShareSnapshot {
    let title: String
    let discipline: Discipline
    let date: Date
    let duration: TimeInterval?
    let distanceMeters: Double?
    let speedMetersPerSecond: Double?
    let route: [RecordedRoutePoint]
    let multisportSegments: [RecordedMultisportSegment]

    @MainActor
    init(workout: PlannedWorkout, titleOverride: String? = nil) {
        let summary = workout.importedSummary
        title = titleOverride ?? Self.shareTitle(for: workout.discipline)
        discipline = workout.discipline
        date = summary?.startDate ?? workout.completedAt ?? workout.date
        duration = Self.positive(summary?.duration)
        distanceMeters = Self.positive(summary?.distanceMeters)
        speedMetersPerSecond = Self.positive({
            switch workout.discipline {
            case .cycling:
                summary?.metrics?.averageCyclingSpeed
            case .running:
                summary?.metrics?.averageRunningSpeed
            default:
                nil
            }
        }())
        route = summary?.metrics?.route ?? []
        multisportSegments = summary?.metrics?.multisportSegments ?? []
    }

    var metrics: [WorkoutShareMetric] {
        switch discipline {
        case .running:
            return compact([
                distanceMetric,
                durationMetric,
                paceMetric
            ])

        case .swimming:
            return compact([
                distanceMetric,
                durationMetric,
                paceMetric
            ])

        case .cycling:
            return compact([
                distanceMetric,
                durationMetric,
                speedMetric
            ])

        case .multisport:
            return multisportMetrics

        case .recovery:
            return compact([durationMetric])

        case .rest:
            return []
        }
    }

    private var distanceMetric: WorkoutShareMetric? {
        guard let value = distanceText else { return nil }
        return WorkoutShareMetric(label: distanceLabel, value: value)
    }

    private var durationMetric: WorkoutShareMetric? {
        guard let value = durationText else { return nil }
        return WorkoutShareMetric(label: "Time", value: value)
    }

    private var paceMetric: WorkoutShareMetric? {
        guard let value = paceOrSpeed else { return nil }
        let label = discipline == .swimming ? "Avg pace · /100 m" : "Avg pace · /km"
        return WorkoutShareMetric(label: label, value: value)
    }

    private var speedMetric: WorkoutShareMetric? {
        guard let value = paceOrSpeed else { return nil }
        return WorkoutShareMetric(label: "Avg speed · km/h", value: value)
    }

    private var multisportMetrics: [WorkoutShareMetric] {
        var values: [WorkoutShareMetric] = []

        if let durationMetric {
            values.append(durationMetric)
        }

        let sportLegs = multisportSegments.filter { !$0.isTransition && $0.sport != nil }
        if !sportLegs.isEmpty {
            let uniqueSports = Set(sportLegs.compactMap(\.sport))
            values.append(
                WorkoutShareMetric(
                    label: uniqueSports.count == 1 ? "Sport" : "Sports",
                    value: "\(uniqueSports.count)"
                )
            )
            values.append(
                WorkoutShareMetric(
                    label: "Legs",
                    value: "\(sportLegs.count)"
                )
            )
        }

        return Array(values.prefix(3))
    }

    var paceOrSpeed: String? {
        let derivedSpeed: Double? = {
            guard let distanceMeters, let duration else { return nil }
            return distanceMeters / duration
        }()

        guard let speed = Self.positive(speedMetersPerSecond ?? derivedSpeed) else {
            return nil
        }

        if discipline == .cycling {
            return String(format: "%.1f", speed * 3.6)
        }

        guard discipline == .running || discipline == .swimming else {
            return nil
        }

        let seconds = (discipline == .swimming ? 100 : 1_000) / speed
        guard seconds.isFinite, seconds >= 1, seconds < 86_400 else { return nil }
        let rounded = Int(seconds.rounded())
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }

    var distanceText: String? {
        guard let distanceMeters else { return nil }

        if discipline == .swimming {
            return "\(Int(distanceMeters.rounded()))"
        }

        return String(format: "%.2f", distanceMeters / 1_000)
    }

    var distanceLabel: String {
        discipline == .swimming ? "Distance · m" : "Distance · km"
    }

    var durationText: String? {
        guard let duration, duration < Double(Int.max) else { return nil }
        let seconds = Int(duration.rounded())

        if seconds >= 3_600 {
            return String(
                format: "%d:%02d:%02d",
                seconds / 3_600,
                seconds / 60 % 60,
                seconds % 60
            )
        }

        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func shareTitle(for discipline: Discipline) -> String {
        switch discipline {
        case .running:
            "Run"
        case .swimming:
            "Swim"
        case .cycling:
            "Cycle"
        case .multisport:
            "Multisport"
        case .recovery:
            "Recovery"
        case .rest:
            "Workout"
        }
    }

    private func compact(_ values: [WorkoutShareMetric?]) -> [WorkoutShareMetric] {
        Array(values.compactMap { $0 }.prefix(3))
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}
