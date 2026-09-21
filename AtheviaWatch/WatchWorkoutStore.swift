import Combine
import Foundation
import WatchConnectivity

@MainActor
final class WatchWorkoutStore: NSObject, ObservableObject {
    @Published private(set) var payload: WatchWorkoutListPayload
    @Published private(set) var connectionState: ConnectionState = .starting

    enum ConnectionState: Equatable {
        case starting
        case connected
        case waitingForPhone
    }

    private static let contextKey = "athevia.workout-list.v1"
    private static let cacheKey = "athevia.cached-workout-list.v1"

    override init() {
        payload = Self.loadCachedPayload()
        super.init()
        activate()
    }

    var workouts: [WatchWorkoutPayload] {
        payload.workouts.sorted { $0.date < $1.date }
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

        payload = decoded
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
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
