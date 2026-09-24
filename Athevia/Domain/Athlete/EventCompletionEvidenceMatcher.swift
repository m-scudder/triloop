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
