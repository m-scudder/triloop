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
/// Requires same-day metric agreement and a unique candidate on both sides.
/// Adjacent days need a plan identifier, which normalized recordings do not carry.
struct WorkoutMatcher: Sendable {
    var calendar: Calendar = .current
    var toleranceDays: Int = 0

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
            let score: Double
        }

        var candidates: [Candidate] = []

        for (plannedIndex, session) in sessions.enumerated() {
            guard let sport = session.discipline.sport,
                  !session.isSkipped, session.importedSummary == nil else { continue }
            let plannedDay = calendar.startOfDay(for: session.date)

            // A session cannot be done before its day arrives. Without this the
            // tolerance window reaches forward, and today's ride marks
            // tomorrow's ride complete before the athlete has done it.
            guard plannedDay <= today else { continue }

            for (importedIndex, activity) in imported.enumerated() where activity.sport == sport {
                let activityDay = calendar.startOfDay(for: activity.startDate)
                let offset = calendar.dateComponents([.day], from: plannedDay, to: activityDay).day ?? 0
                guard offset == 0, activity.startDate <= now,
                      activity.duration.isFinite, activity.duration > 0 else { continue }

                var similarities: [Double] = []
                if let target = session.estimatedDurationSeconds, target > 0 {
                    let ratio = activity.duration / target
                    guard ratio >= 0.65, ratio <= 1.5 else { continue }
                    similarities.append(min(ratio, 1 / ratio))
                }
                if let target = session.estimatedDistanceMeters, target > 0,
                   let actual = activity.distanceMeters {
                    let ratio = actual / target
                    guard ratio.isFinite, ratio >= 0.65, ratio <= 1.5 else { continue }
                    similarities.append(min(ratio, 1 / ratio))
                }
                guard !similarities.isEmpty else { continue }

                candidates.append(
                    Candidate(
                        plannedIndex: plannedIndex,
                        importedIndex: importedIndex,
                        dayOffset: offset,
                        score: similarities.reduce(0, +) / Double(similarities.count)
                    )
                )
            }
        }

        var usedPlanned: Set<Int> = []
        var usedImported: Set<Int> = []
        var matches: [WorkoutMatch] = []

        for candidate in candidates {
            let alternatives = candidates.filter {
                ($0.plannedIndex == candidate.plannedIndex || $0.importedIndex == candidate.importedIndex)
                    && !($0.plannedIndex == candidate.plannedIndex && $0.importedIndex == candidate.importedIndex)
            }
            guard alternatives.allSatisfy({ candidate.score - $0.score > 0.15 }) else { continue }
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
