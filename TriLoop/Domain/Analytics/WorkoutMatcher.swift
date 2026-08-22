import Foundation

struct WorkoutMatch {
    let planned: PlannedWorkout
    let imported: ImportedWorkout
    /// Whole days between the planned date and the actual start. Zero is a
    /// same-day match.
    let dayOffset: Int
}

struct MatchResult {
    let matches: [WorkoutMatch]
    let unmatchedPlanned: [PlannedWorkout]
    let unmatchedImported: [ImportedWorkout]
}

/// Pairs planned sessions with what actually happened.
///
/// Sport and date do the work: a planned workout carries no time of day, so
/// there is nothing more precise to match on until WorkoutKit gives us our own
/// identifiers in Phase 6.
struct WorkoutMatcher: Sendable {
    var calendar: Calendar = .current
    /// How many days late (or early) an activity may be and still count. One day
    /// covers the common case of training after midnight or a day slipping.
    var toleranceDays: Int = 1

    func match(
        planned: [PlannedWorkout],
        with imported: [ImportedWorkout],
        asOf now: Date = .now
    ) -> MatchResult {
        let sessions = planned.filter { $0.discipline.isTrainingSession }
        let today = calendar.startOfDay(for: now)

        struct Candidate {
            let plannedIndex: Int
            let importedIndex: Int
            let dayOffset: Int
            let secondsFromPlannedDay: TimeInterval
        }

        var candidates: [Candidate] = []

        for (plannedIndex, session) in sessions.enumerated() {
            guard let sport = session.discipline.sport else { continue }
            let plannedDay = calendar.startOfDay(for: session.date)

            // A session cannot be done before its day arrives. Without this the
            // tolerance window reaches forward, and today's ride marks
            // tomorrow's ride complete before the athlete has done it.
            guard plannedDay <= today else { continue }

            for (importedIndex, activity) in imported.enumerated() where activity.sport == sport {
                let activityDay = calendar.startOfDay(for: activity.startDate)
                let offset = calendar.dateComponents([.day], from: plannedDay, to: activityDay).day ?? 0
                guard abs(offset) <= toleranceDays else { continue }

                candidates.append(
                    Candidate(
                        plannedIndex: plannedIndex,
                        importedIndex: importedIndex,
                        dayOffset: offset,
                        secondsFromPlannedDay: abs(activity.startDate.timeIntervalSince(plannedDay))
                    )
                )
            }
        }

        // Closest match wins, and each side is used at most once, so two runs in
        // one day cannot both claim the same planned session.
        candidates.sort {
            ($0.dayOffset.magnitude, $0.secondsFromPlannedDay)
                < ($1.dayOffset.magnitude, $1.secondsFromPlannedDay)
        }

        var usedPlanned: Set<Int> = []
        var usedImported: Set<Int> = []
        var matches: [WorkoutMatch] = []

        for candidate in candidates {
            guard !usedPlanned.contains(candidate.plannedIndex),
                  !usedImported.contains(candidate.importedIndex) else { continue }

            usedPlanned.insert(candidate.plannedIndex)
            usedImported.insert(candidate.importedIndex)
            matches.append(
                WorkoutMatch(
                    planned: sessions[candidate.plannedIndex],
                    imported: imported[candidate.importedIndex],
                    dayOffset: candidate.dayOffset
                )
            )
        }

        return MatchResult(
            matches: matches.sorted { $0.planned.date < $1.planned.date },
            unmatchedPlanned: sessions.enumerated()
                .filter { !usedPlanned.contains($0.offset) }
                .map(\.element),
            unmatchedImported: imported.enumerated()
                .filter { !usedImported.contains($0.offset) }
                .map(\.element)
        )
    }
}

extension PlannedWorkout {
    /// How much of the prescription the activity actually covered, 0...1.
    ///
    /// Swimming is judged on distance and the other sports on duration, matching
    /// how each is prescribed. Returns 1 when there is nothing to compare against,
    /// since a session that happened is better evidence than no evidence.
    func completionRatio(for imported: ImportedWorkout) -> Double {
        let ratio: Double?

        if discipline == .swimming, let target = estimatedDistanceMeters, target > 0 {
            ratio = imported.distanceMeters.map { $0 / target }
        } else if let target = estimatedDurationSeconds, target > 0 {
            ratio = imported.duration / target
        } else {
            ratio = nil
        }

        guard let ratio else { return 1 }
        return min(max(ratio, 0), 1)
    }
}
