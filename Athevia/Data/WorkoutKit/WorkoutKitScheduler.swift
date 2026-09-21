import Foundation
import WorkoutKit
import WatchConnectivity
import Combine

/// Schedules Athevia workouts into Apple's Workout app.
///
/// §5: Athevia does not replace the Workout app. It hands over a structured
/// workout and later reads the result back from HealthKit.
struct WorkoutKitScheduler: WorkoutScheduling {
    var calendar: Calendar = .current

    var isSupported: Bool {
        WorkoutScheduler.isSupported
    }

    func authorizationState() async -> WorkoutSchedulingAuthorization {
        await Self.map(WorkoutScheduler.shared.authorizationState)
    }

    func requestAuthorization() async -> WorkoutSchedulingAuthorization {
        Self.map(await WorkoutScheduler.shared.requestAuthorization())
    }

    func schedule(_ workout: PlannedWorkout, at date: Date) async throws {
        guard WorkoutScheduler.isSupported else {
            throw WorkoutSchedulingError.unavailable
        }
        guard let plan = WorkoutPlanBuilder.plan(for: workout) else {
            throw WorkoutSchedulingError.unsupportedWorkout
        }
        guard await requestAuthorization() == .authorized else {
            throw WorkoutSchedulingError.notAuthorized
        }

        // WorkoutKit identifies a scheduled workout by plan *and* date, so the
        // components retain the intended starting time.
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        await WorkoutScheduler.shared.schedule(plan, at: components)

        // Read back local acceptance. This does not acknowledge Watch delivery.
        guard await scheduledWorkoutIDs().contains(plan.id) else {
            throw WorkoutSchedulingError.notAccepted
        }
    }

    func scheduledWorkouts() async -> [ScheduledWorkoutSummary] {
        await WorkoutScheduler.shared.scheduledWorkouts.map { entry in
            ScheduledWorkoutSummary(
                id: entry.plan.id,
                displayName: Self.displayName(of: entry.plan),
                date: calendar.date(from: entry.date),
                isComplete: entry.complete
            )
        }
    }

    func removeScheduled(ids: Set<UUID>) async {
        // Removal needs the original plan and date, so the entries are matched
        // from the schedule itself rather than rebuilt.
        for entry in await WorkoutScheduler.shared.scheduledWorkouts
        where ids.contains(entry.plan.id) {
            await WorkoutScheduler.shared.remove(entry.plan, at: entry.date)
        }
    }

    func removeAllScheduled() async {
        await WorkoutScheduler.shared.removeAllWorkouts()
    }

    private static func displayName(of plan: WorkoutPlan) -> String? {
        if case .custom(let custom) = plan.workout {
            return custom.displayName
        }
        return nil
    }

    private static func map(
        _ state: WorkoutScheduler.AuthorizationState
    ) -> WorkoutSchedulingAuthorization {
        switch state {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .notDetermined
        }
    }
}


/// Pairing is separate from WorkoutKit support and live message reachability.
/// No companion Watch app is required for Apple's Workout app integration.
@MainActor
final class WatchAvailability: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchAvailability()
    @Published private(set) var canSchedule = false

    private override init() {
        super.init()
        refresh()
    }

    func refresh() {
        guard WCSession.isSupported() else {
            canSchedule = false
            return
        }
        let session = WCSession.default
        session.delegate = self
        guard session.activationState == .activated else {
            canSchedule = false
            if session.activationState == .notActivated { session.activate() }
            return
        }
        // isReachable requires a running companion app; it is not a test for
        // whether WorkoutKit can queue a workout for Apple's Workout app.
        canSchedule = session.isPaired && WorkoutScheduler.isSupported
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            // Do not immediately retry a failed activation.
            guard activationState == .activated, error == nil else {
                self.canSchedule = false
                return
            }
            self.refresh()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in self.canSchedule = false }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.canSchedule = false
            WCSession.default.activate()
        }
    }
}
