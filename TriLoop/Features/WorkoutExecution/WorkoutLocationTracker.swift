import CoreLocation
import Foundation
import Observation

struct WorkoutLocationSnapshot: Equatable, Sendable {
    var distanceMeters: Double
    var currentSpeedMetersPerSecond: Double?
    var routePoints: [RecordedRoutePoint]
}

/// GPS recorder used only while TriLoop is executing an outdoor run or ride.
///
/// It deliberately owns no workout state: pause/resume comes from the execution
/// engine, and the final snapshot is copied into the workout result. This keeps
/// GPS failure from ever stopping the workout timer itself.
@MainActor
@Observable
final class WorkoutLocationTracker: NSObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case idle
        case requestingPermission
        case tracking
        case paused
        case unavailable(String)
    }

    private let manager = CLLocationManager()
    private let sport: Sport
    private var lastAcceptedLocation: CLLocation?
    private var lastRouteLocation: CLLocation?
    private var shouldStartWhenAuthorized = false

    private(set) var state: State = .idle
    private(set) var distanceMeters: Double = 0
    private(set) var currentSpeedMetersPerSecond: Double?
    private(set) var routePoints: [RecordedRoutePoint] = []

    var isSupportedSport: Bool {
        sport == .running || sport == .cycling
    }

    var snapshot: WorkoutLocationSnapshot {
        WorkoutLocationSnapshot(
            distanceMeters: distanceMeters,
            currentSpeedMetersPerSecond: currentSpeedMetersPerSecond,
            routePoints: routePoints
        )
    }

    init(sport: Sport) {
        self.sport = sport
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 1
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    func start() {
        guard isSupportedSport else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdates()
        case .notDetermined:
            shouldStartWhenAuthorized = true
            state = .requestingPermission
            manager.requestWhenInUseAuthorization()
        case .denied:
            state = .unavailable("Location access is off. The workout timer will continue without GPS.")
        case .restricted:
            state = .unavailable("Location is restricted on this device. The workout timer will continue without GPS.")
        @unknown default:
            state = .unavailable("Location is unavailable. The workout timer will continue without GPS.")
        }
    }

    func pause() {
        guard isSupportedSport else { return }
        manager.stopUpdatingLocation()
        lastAcceptedLocation = nil
        currentSpeedMetersPerSecond = nil
        if case .tracking = state { state = .paused }
    }

    func resume() {
        guard isSupportedSport else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginUpdates()
        default:
            start()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        lastAcceptedLocation = nil
        currentSpeedMetersPerSecond = nil
        if case .unavailable = state { return }
        state = .idle
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard shouldStartWhenAuthorized else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            shouldStartWhenAuthorized = false
            beginUpdates()
        case .denied, .restricted:
            shouldStartWhenAuthorized = false
            state = .unavailable("Location access was not granted. The workout timer will continue without GPS.")
        case .notDetermined:
            break
        @unknown default:
            shouldStartWhenAuthorized = false
            state = .unavailable("Location is unavailable. The workout timer will continue without GPS.")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            accept(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code != .locationUnknown else { return }
        currentSpeedMetersPerSecond = nil
    }

    private func beginUpdates() {
        lastAcceptedLocation = nil
        state = .tracking
        manager.startUpdatingLocation()
    }

    private func accept(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 35,
              abs(location.timestamp.timeIntervalSinceNow) < 15 else { return }

        if let previous = lastAcceptedLocation {
            let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
            guard seconds > 0 else { return }

            let delta = location.distance(from: previous)
            let calculatedSpeed = delta / seconds
            guard calculatedSpeed <= maximumReasonableSpeed else {
                // Drop a GPS jump without making it the new anchor point.
                return
            }

            if delta >= 1 {
                distanceMeters += delta
            }
        }

        lastAcceptedLocation = location
        if location.speed >= 0, location.speed <= maximumReasonableSpeed {
            currentSpeedMetersPerSecond = location.speed
        } else {
            currentSpeedMetersPerSecond = nil
        }

        appendRoutePointIfNeeded(location)
    }

    private func appendRoutePointIfNeeded(_ location: CLLocation) {
        if let previous = lastRouteLocation {
            let distance = location.distance(from: previous)
            let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
            guard distance >= 3 || seconds >= 5 else { return }
        }

        routePoints.append(
            RecordedRoutePoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
                timestamp: location.timestamp
            )
        )
        lastRouteLocation = location
    }

    private var maximumReasonableSpeed: CLLocationSpeed {
        switch sport {
        case .running: 12       // 43 km/h: generous enough for GPS noise/sprints.
        case .cycling: 35      // 126 km/h: catches jumps without rejecting descents.
        case .swimming: 5
        }
    }
}
