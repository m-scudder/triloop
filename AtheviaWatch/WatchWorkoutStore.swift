import Combine
import Foundation
import WatchConnectivity

@MainActor
final class WatchWorkoutStore: NSObject, ObservableObject {
    @Published private(set) var payload: WatchWorkoutListPayload
    @Published private(set) var connectionState: ConnectionState = .starting
    @Published private(set) var locallyCompletedWorkoutIDs: Set<UUID>

    enum ConnectionState: Equatable {
        case starting
        case connected
        case waitingForPhone
    }

    private static let contextKey = "athevia.workout-list.v1"
    private static let cacheKey = "athevia.cached-workout-list.v1"
    private static let completedKey = "athevia.completed-workout-ids.v1"

    override init() {
        let cached = Self.loadCachedPayload()
        locallyCompletedWorkoutIDs = Self.loadCompletedWorkoutIDs()
        #if DEBUG
        #if targetEnvironment(simulator)
        payload = cached.workouts.isEmpty && Self.shouldUseSimulatorFixture
            ? WatchSimulatorFixture.payload()
            : cached
        #else
        payload = cached
        #endif
        #else
        payload = cached
        #endif

        super.init()
        activate()
    }

    var workouts: [WatchWorkoutPayload] {
        payload.workouts.sorted { $0.date < $1.date }
    }

    var coachingSettings: WatchCoachingSettingsPayload {
        payload.coaching ?? .defaults
    }

    func isCompleted(_ workout: WatchWorkoutPayload) -> Bool {
        workout.status == .completed || locallyCompletedWorkoutIDs.contains(workout.id)
    }

    func markCompleted(_ workoutID: UUID) {
        locallyCompletedWorkoutIDs.insert(workoutID)
        persistCompletedWorkoutIDs()
    }

    var lastUpdatedText: String? {
        guard !payload.workouts.isEmpty else { return nil }
        return payload.generatedAt.formatted(date: .omitted, time: .shortened)
    }

    private func activate() {
        guard WCSession.isSupported() else {
            connectionState = .waitingForPhone
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()

        if let data = session.receivedApplicationContext[Self.contextKey] as? Data {
            consume(data)
        }
    }

    private func consume(_ data: Data) {
        guard let decoded = try? JSONDecoder.atheviaWatch.decode(WatchWorkoutListPayload.self, from: data),
              decoded.schemaVersion == WatchWorkoutListPayload.currentSchemaVersion else {
            return
        }

        UserDefaults.standard.set(GamingPalette.resolve(decoded.gamingPalette).rawValue, forKey: GamingPalette.preferenceKey)
        payload = decoded
        UserDefaults.standard.set(decoded.gamingThemeEnabled ?? false, forKey: AtheviaTheme.preferenceKey)

        let currentIDs = Set(decoded.workouts.map(\.id))
        locallyCompletedWorkoutIDs.formIntersection(currentIDs)
        for workout in decoded.workouts where workout.status == .completed {
            locallyCompletedWorkoutIDs.insert(workout.id)
        }
        persistCompletedWorkoutIDs()

        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

    private func persistCompletedWorkoutIDs() {
        UserDefaults.standard.set(
            locallyCompletedWorkoutIDs.map(\.uuidString),
            forKey: Self.completedKey
        )
    }

    #if DEBUG
    #if targetEnvironment(simulator)
    /// Simulator fixtures are opt-in so an intentional phone reset can be
    /// validated as truly empty. Enable with the launch argument
    /// `--athevia-watch-fixture` when standalone Watch development needs data.
    private static var shouldUseSimulatorFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("--athevia-watch-fixture")
    }
    #endif
    #endif

    private static func loadCompletedWorkoutIDs() -> Set<UUID> {
        let values = UserDefaults.standard.stringArray(forKey: completedKey) ?? []
        return Set(values.compactMap(UUID.init(uuidString:)))
    }

    private static func loadCachedPayload() -> WatchWorkoutListPayload {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let payload = try? JSONDecoder.atheviaWatch.decode(WatchWorkoutListPayload.self, from: data),
              payload.schemaVersion == WatchWorkoutListPayload.currentSchemaVersion else {
            return WatchWorkoutListPayload(weekStart: nil, workouts: [])
        }
        return payload
    }
}

extension WatchWorkoutStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.connectionState = activationState == .activated && error == nil
                ? .connected
                : .waitingForPhone

            if let data = session.receivedApplicationContext[Self.contextKey] as? Data {
                self.consume(data)
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext[Self.contextKey] as? Data else { return }
        Task { @MainActor in
            self.consume(data)
        }
    }
}

private extension JSONDecoder {
    static var atheviaWatch: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
