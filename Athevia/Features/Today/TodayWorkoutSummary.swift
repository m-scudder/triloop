import Foundation

/// A one-line description of what the session is made of (§5).
///
/// Enough to know what is coming without reproducing the prescription — the
/// full recursive structure stays in Workout Detail.
enum WorkoutStructureSummary {

    static func text(for workout: PlannedWorkout) -> String? {
        let steps = workout.orderedSteps
        guard !steps.isEmpty else { return nil }

        if let repeats = steps.first(where: { $0.kind == .repeatBlock }) {
            return repeatSummary(repeats, sport: workout.discipline.sport)
                ?? shape(of: steps)
        }

        // A single continuous block reads better as its own sentence than as a
        // list of one.
        if steps.count == 1, let only = steps.first {
            return continuous(only, sport: workout.discipline.sport)
        }

        return shape(of: steps)
    }

    /// "4 × 5 min run / 1 min walk" or "6 × 50m · 20 sec rest".
    private static func repeatSummary(_ block: WorkoutStep, sport: Sport?) -> String? {
        guard let count = block.repeatCount, count > 0 else { return nil }

        let children = block.orderedChildren
        guard let work = children.first(where: { $0.kind == .work }) else { return nil }
        let rest = children.first { $0.kind == .recovery }

        guard let workText = measure(work, sport: sport) else { return nil }

        guard let rest, let restText = measure(rest, sport: sport) else {
            return "\(count) × \(workText)"
        }

        // Swimmers think in rest seconds, runners in the walk itself.
        let separator = sport == .swimming ? " · " : " / "
        let restLabel = sport == .swimming ? "\(restText) rest" : restText
        return "\(count) × \(workText)\(separator)\(restLabel)"
    }

    private static func continuous(_ step: WorkoutStep, sport: Sport?) -> String? {
        guard let measure = measure(step, sport: sport) else { return nil }
        guard let intensity = step.targetIntensity else { return measure }
        return "\(measure) \(intensity.displayName.lowercased())"
    }

    /// Falls back to naming the parts when the shape is more complex than one
    /// line can carry honestly.
    private static func shape(of steps: [WorkoutStep]) -> String? {
        var parts: [String] = []

        if steps.contains(where: { $0.kind == .warmUp }) { parts.append("Warm-up") }
        if let repeats = steps.first(where: { $0.kind == .repeatBlock })?.repeatCount {
            parts.append("\(repeats) repeats")
        } else if steps.contains(where: { $0.kind == .work }) {
            parts.append("Main set")
        }
        if steps.contains(where: { $0.kind == .cooldown }) { parts.append("Cool-down") }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Distance for swimmers, time for everyone else.
    private static func measure(_ step: WorkoutStep, sport: Sport?) -> String? {
        if sport == .swimming, let metres = step.distanceMeters, metres > 0 {
            return "\(Int(metres))m"
        }
        guard let seconds = step.durationSeconds, seconds > 0 else {
            if let metres = step.distanceMeters, metres > 0 {
                return TrainingFormatter.distance(meters: metres)
            }
            return nil
        }
        return TrainingFormatter.intervalDuration(seconds: seconds)
    }
}

/// One short execution cue per session (§7).
///
/// Deterministic and deliberately brief. Its job is to tell the athlete how to
/// run the session, not to explain the training theory behind it.
enum TodayCoachingCue {

    static func text(for workout: PlannedWorkout) -> String? {
        guard let sport = workout.discipline.sport else { return nil }

        // Intensity leads: how hard a session should feel matters more than
        // which sport it is.
        if let target = workout.targetRPE {
            if target.upper <= 4 { return easy(sport) }
            if target.lower >= 7 { return hard(sport) }
            return steady(sport)
        }

        return easy(sport)
    }

    private static func easy(_ sport: Sport) -> String {
        switch sport {
        case .running: "Keep this comfortable. You should be able to talk."
        case .swimming: "Focus on relaxed breathing and a steady rhythm."
        case .cycling: "Ride steadily, not hard."
        }
    }

    private static func steady(_ sport: Sport) -> String {
        switch sport {
        case .running: "Settle into a rhythm you could hold a little longer."
        case .swimming: "Hold your form as the set goes on."
        case .cycling: "Keep the effort even rather than surging."
        }
    }

    private static func hard(_ sport: Sport) -> String {
        switch sport {
        case .running: "Work hard on the efforts, easy in between."
        case .swimming: "Push the repeats and take the full rest."
        case .cycling: "Commit to the efforts and recover properly between them."
        }
    }
}

/// Effort in language a beginner can act on (§6).
enum TodayEffort {

    static func text(for range: RPERange?) -> String? {
        guard let range else { return nil }
        return "\(descriptor(for: range)) · \(TrainingFormatter.rpe(range))"
    }

    private static func descriptor(for range: RPERange) -> String {
        switch range.upper {
        case ...2: "Very easy"
        case 3...4: "Easy"
        case 5...6: "Steady"
        case 7...8: "Hard"
        default: "Very hard"
        }
    }
}
