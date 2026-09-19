import Foundation

/// Only completed evidence belongs on a shared activity; targets are not results.
struct WorkoutShareSnapshot {
    let title: String
    let discipline: Discipline
    let date: Date
    let duration: TimeInterval?
    let distanceMeters: Double?
    let speedMetersPerSecond: Double?
    let route: [RecordedRoutePoint]

    @MainActor
    init(workout: PlannedWorkout) {
        let summary = workout.importedSummary
        title = workout.title
        discipline = workout.discipline
        date = summary?.startDate ?? workout.completedAt ?? workout.date
        duration = Self.positive(summary?.duration)
        distanceMeters = Self.positive(summary?.distanceMeters)
        speedMetersPerSecond = Self.positive(workout.discipline == .cycling
            ? summary?.metrics?.averageCyclingSpeed
            : summary?.metrics?.averageRunningSpeed)
        route = summary?.metrics?.route ?? []
    }

    var paceOrSpeed: String? {
        let derivedSpeed: Double? = {
            guard let distanceMeters, let duration else { return nil }
            return distanceMeters / duration
        }()
        guard let speed = Self.positive(speedMetersPerSecond ?? derivedSpeed) else { return nil }
        if discipline == .cycling {
            return String(format: "%.1f", speed * 3.6)
        }
        let seconds = (discipline == .swimming ? 100 : 1_000) / speed
        guard seconds.isFinite, seconds >= 1, seconds < 86_400 else { return nil }
        let rounded = Int(seconds.rounded())
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }

    var paceLabel: String {
        switch discipline {
        case .cycling: "Avg speed · km/h"
        case .swimming: "Avg pace · /100 m"
        default: "Avg pace · /km"
        }
    }

    var distanceText: String? {
        distanceMeters.map { String(format: "%.2f", $0 / 1_000) }
    }

    var durationText: String? {
        guard let duration, duration < Double(Int.max) else { return nil }
        let seconds = Int(duration.rounded())
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}
