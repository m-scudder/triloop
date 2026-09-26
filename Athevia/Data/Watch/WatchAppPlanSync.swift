import Foundation
import SwiftData

@MainActor
enum WatchAppPlanSync {
    static let contextKey = "athevia.workout-list.v1"
    private static let lastQueuedAtKey = "athevia.watch.last-queued-at"

    static var lastQueuedAt: Date? {
        UserDefaults.standard.object(forKey: lastQueuedAtKey) as? Date
    }

    @discardableResult
    static func sync(_ plan: WeeklyPlan?) -> Bool {
        let payload = payload(for: plan)
        do {
            let data = try JSONEncoder.atheviaWatch.encode(payload)
            WatchAvailability.shared.updateWatchAppContext([contextKey: data])
            UserDefaults.standard.set(Date.now, forKey: lastQueuedAtKey)
            return true
        } catch {
            return false
        }
    }

    static func fingerprint(_ plan: WeeklyPlan?) -> String {
        let coaching = coachingSettings
        let coachingFingerprint = [
            String(coaching.enabled),
            String(coaching.countdowns),
            String(coaching.volume),
            String(AtheviaTheme.stored().isGaming)
        ].joined(separator: ":")

        guard let plan else { return "no-current-plan|" + coachingFingerprint }
        return plan.orderedWorkouts
            .filter(\.discipline.isTrainingSession)
            .map(workoutFingerprint)
            .joined(separator: "|") + "|" + coachingFingerprint
    }

    private static func payload(for plan: WeeklyPlan?) -> WatchWorkoutListPayload {
        guard let plan else {
            return WatchWorkoutListPayload(
                weekStart: nil,
                workouts: [],
                coaching: coachingSettings,
                gamingThemeEnabled: AtheviaTheme.stored().isGaming
            )
        }

        let workouts = plan.orderedWorkouts
            .filter(\.discipline.isTrainingSession)
            .map(WatchWorkoutPayload.init(workout:))

        return WatchWorkoutListPayload(
            weekStart: plan.startDate,
            workouts: workouts,
            coaching: coachingSettings,
            gamingThemeEnabled: AtheviaTheme.stored().isGaming
        )
    }

    private static var coachingSettings: WatchCoachingSettingsPayload {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(
            forKey: SharedAudioCoachingPreferences.enabledKey
        ) as? Bool ?? true
        let countdowns = defaults.object(
            forKey: SharedAudioCoachingPreferences.countdownsKey
        ) as? Bool ?? true
        let volume = defaults.object(
            forKey: SharedAudioCoachingPreferences.volumeKey
        ) as? Double ?? 0.8

        return WatchCoachingSettingsPayload(
            enabled: enabled,
            countdowns: countdowns,
            volume: min(max(volume, 0.1), 1)
        )
    }

    private static func workoutFingerprint(_ workout: PlannedWorkout) -> String {
        [
            workout.id.uuidString,
            String(workout.date.timeIntervalSince1970),
            workout.discipline.rawValue,
            workout.title,
            workout.goal,
            workout.status.rawValue,
            workout.orderedSteps.map(stepFingerprint).joined(separator: ",")
        ].joined(separator: ":")
    }

    private static func stepFingerprint(_ step: WorkoutStep) -> String {
        [
            step.id.uuidString,
            String(step.order),
            step.kind.rawValue,
            step.title,
            step.instructions ?? "",
            step.durationSeconds.map { String($0) } ?? "",
            step.distanceMeters.map { String($0) } ?? "",
            step.targetIntensity?.rawValue ?? "",
            step.repeatCount.map { String($0) } ?? "",
            step.orderedChildren.map(stepFingerprint).joined(separator: ";")
        ].joined(separator: "~")
    }
}

private extension WatchWorkoutPayload {
    init(workout: PlannedWorkout) {
        self.init(
            id: workout.id,
            date: workout.date,
            discipline: WatchWorkoutDiscipline(rawValue: workout.discipline.rawValue) ?? .running,
            title: workout.title,
            goal: workout.goal,
            estimatedDurationSeconds: workout.estimatedDurationSeconds,
            estimatedDistanceMeters: workout.estimatedDistanceMeters,
            status: WatchWorkoutStatus(rawValue: workout.status.rawValue) ?? .planned,
            steps: workout.orderedSteps.map(WatchWorkoutStepPayload.init(step:))
        )
    }
}

private extension WatchWorkoutStepPayload {
    init(step: WorkoutStep) {
        self.init(
            id: step.id,
            kind: WatchWorkoutStepKind(rawValue: step.kind.rawValue) ?? .work,
            title: step.title,
            instructions: step.instructions,
            durationSeconds: step.durationSeconds,
            distanceMeters: step.distanceMeters,
            targetIntensity: step.targetIntensity.flatMap { WatchWorkoutIntensity(rawValue: $0.rawValue) },
            repeatCount: step.repeatCount,
            children: step.orderedChildren.map(WatchWorkoutStepPayload.init(step:))
        )
    }
}

private extension JSONEncoder {
    static var atheviaWatch: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
