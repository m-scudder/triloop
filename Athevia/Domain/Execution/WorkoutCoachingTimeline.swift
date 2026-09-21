import Foundation

/// A finite audio programme. Its gaps are the prescribed exercise/recovery
/// periods, not a separate silent loop used to keep a UI timer alive.
struct WorkoutCoachingTimeline: Equatable, Sendable {
    struct Cue: Equatable, Sendable {
        let time: TimeInterval
        let text: String
        let summaryText: String
        let briefText: String
    }

    let stepStarts: [TimeInterval]
    let duration: TimeInterval
    let cues: [Cue]

    init?(plan: WorkoutExecutionPlan, countdowns: Bool) {
        guard !plan.steps.isEmpty,
              plan.steps.allSatisfy({
                  guard let seconds = $0.durationSeconds else { return false }
                  return seconds.isFinite && seconds > 0 && seconds <= 6 * 3_600
              }) else { return nil }
        guard plan.steps.reduce(0, { $0 + ($1.durationSeconds ?? 0) }) <= 6 * 3_600 else { return nil }

        var starts: [TimeInterval] = []
        var cues: [Cue] = []
        var offset: TimeInterval = 0
        for (index, step) in plan.steps.enumerated() {
            let seconds = step.durationSeconds!
            starts.append(offset)
            var text = String(step.title.prefix(100)) + ". " + Self.spokenDuration(seconds) + "."
            if let repetition = step.repetitionLabel { text += " " + repetition + "." }
            if let intensity = step.targetIntensity { text += " " + intensity.displayName + " effort." }
            let summary = text
            if let instructions = step.instructions, !instructions.isEmpty {
                text += " " + String(instructions.prefix(240))
            }
            cues.append(Cue(time: offset, text: text, summaryText: summary, briefText: step.title))
            // Short sets should not be overwhelmed by countdown speech.
            if countdowns, seconds >= 30 {
                let next = index + 1 < plan.steps.count
                    ? " Next: " + String(plan.steps[index + 1].title.prefix(60)) + "."
                    : " Then your workout is complete."
                cues.append(Cue(time: offset + seconds - 10, text: "Ten seconds remaining." + next, summaryText: "Ten seconds remaining.", briefText: "Ten seconds."))
            }
            offset += seconds
        }
        guard offset.isFinite, offset <= 6 * 3_600 else { return nil }
        cues.append(Cue(time: offset, text: "Workout complete. Well done.", summaryText: "Workout complete.", briefText: "Workout complete."))
        self.stepStarts = starts
        self.duration = offset
        self.cues = cues
    }

    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 1)
        let minutes = total / 60
        let remainder = total % 60
        var parts: [String] = []
        if minutes > 0 { parts.append("\(minutes) " + (minutes == 1 ? "minute" : "minutes")) }
        if remainder > 0 { parts.append("\(remainder) " + (remainder == 1 ? "second" : "seconds")) }
        return parts.joined(separator: " and ")
    }
}

/// Converts the media clock into active time. Seeking after a skipped set must
/// reset the baseline so the skipped seconds never count as exercise.
struct WorkoutPlaybackClock: Equatable, Sendable {
    private(set) var position: TimeInterval = 0

    mutating func consume(_ position: TimeInterval) -> TimeInterval {
        guard position.isFinite, position >= self.position else { return 0 }
        let delta = position - self.position
        self.position = position
        return delta
    }

    mutating func seek(to position: TimeInterval) {
        self.position = max(position, 0)
    }
}
