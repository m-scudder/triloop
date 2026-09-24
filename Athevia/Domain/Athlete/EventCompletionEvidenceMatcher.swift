import Foundation

struct EventCompletionEvidenceMatcher: Sendable {
    var calendar: Calendar = .current
    var distanceTolerance = 0.95

    func matches(
        event: AthleteEventGoal,
        imported: ImportedWorkout
    ) -> Bool {
        guard let eventDate = event.eventDate,
              calendar.isDate(imported.startDate, inSameDayAs: eventDate) else {
            return false
        }

        switch event.sport {
        case .running:
            return singleSport(
                .running,
                target: event.distance?.components.runMeters,
                imported: imported
            )
        case .cycling:
            return singleSport(
                .cycling,
                target: event.distance?.components.bikeMeters,
                imported: imported
            )
        case .swimming:
            return singleSport(
                .swimming,
                target: event.distance?.components.swimMeters,
                imported: imported
            )
        case .triathlon:
            guard imported.discipline == .multisport else { return false }
            let components = event.distance?.components
            return segment(.swimming, target: components?.swimMeters, imported: imported)
                && segment(.cycling, target: components?.bikeMeters, imported: imported)
                && segment(.running, target: components?.runMeters, imported: imported)
        }
    }


    func matches(
        event: AthleteEventGoal,
        summary: ImportedWorkoutSummary
    ) -> Bool {
        guard let eventDate = event.eventDate,
              calendar.isDate(summary.startDate, inSameDayAs: eventDate) else {
            return false
        }

        switch event.sport {
        case .running:
            return summary.discipline == .running
                && meets(summary.distanceMeters, target: event.distance?.components.runMeters)

        case .cycling:
            return summary.discipline == .cycling
                && meets(summary.distanceMeters, target: event.distance?.components.bikeMeters)

        case .swimming:
            return summary.discipline == .swimming
                && meets(summary.distanceMeters, target: event.distance?.components.swimMeters)

        case .triathlon:
            guard summary.discipline == .multisport else { return false }
            let components = event.distance?.components
            let segments = summary.metrics?.multisportSegments ?? []
            return meetsSegment(.swimming, target: components?.swimMeters, segments: segments)
                && meetsSegment(.cycling, target: components?.bikeMeters, segments: segments)
                && meetsSegment(.running, target: components?.runMeters, segments: segments)
        }
    }


    private func meets(_ distance: Double?, target: Double?) -> Bool {
        guard let target, target > 0 else { return distance != nil }
        return (distance ?? 0) >= target * distanceTolerance
    }

    private func meetsSegment(
        _ sport: Sport,
        target: Double?,
        segments: [RecordedMultisportSegment]
    ) -> Bool {
        guard let target, target > 0 else {
            return segments.contains { $0.sport == sport && $0.durationSeconds > 0 }
        }
        return segments.contains {
            $0.sport == sport && ($0.distanceMeters ?? 0) >= target * distanceTolerance
        }
    }

    private func singleSport(
        _ sport: Sport,
        target: Double?,
        imported: ImportedWorkout
    ) -> Bool {
        guard imported.discipline == sport.discipline else { return false }
        guard let target, target > 0 else { return imported.duration > 0 }
        guard let distance = imported.distanceMeters else { return false }
        return distance >= target * distanceTolerance
    }

    private func segment(
        _ sport: Sport,
        target: Double?,
        imported: ImportedWorkout
    ) -> Bool {
        guard let target, target > 0 else {
            return imported.metrics.multisportSegments.contains {
                $0.sport == sport && $0.durationSeconds > 0
            }
        }
        return imported.metrics.multisportSegments.contains {
            $0.sport == sport && ($0.distanceMeters ?? 0) >= target * distanceTolerance
        }
    }
}
