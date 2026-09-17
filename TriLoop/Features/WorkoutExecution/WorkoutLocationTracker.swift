import Combine
import CoreLocation
import Foundation

struct WorkoutLocationSnapshot: Equatable, Sendable {
    var distanceMeters: Double = 0
    var currentSpeedMetersPerSecond: Double?
    var route: [RecordedRoutePoint] = []
}

/// Records the route for an in-app outdoor run or ride.
///
/// Tracking deliberately follows the workout player's active/paused state. A
/// pause clears the previous accepted location so resuming never draws a fake
/// straight line across the break. Poor/stale fixes and implausible jumps are
/// discarded before they can affect distance or pace.
final class WorkoutLocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Permission: Equatable {
        case unknown
        case requesting
        case allowed
        case denied
        case restricted
        case unavailable
    }

    @Published private(set) var snapshot = WorkoutLocationSnapshot()
    @Published private(set) var permission: Permission = .unknown

    private let manager = CLLocationManager()
    private let sport: Sport
    private var lastAccepted: CLLocation?
    private var wantsTracking = false
    private var isPaused = false

    init(sport: Sport) {
        self.sport = sport
        super.init()

        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.pausesLocationUpdatesAutomatically = false
        // Background-mode-dependent flags are configured in `beginUpdates()`
        // once we actually have authorization. Setting them here would crash if
        // the app were ever built without the `location` UIBackgroundMode.
        // `locationManagerDidChangeAuthorization` fires right after the
        // delegate is set, so we don't need to seed `permission` here.
    }

    var isSupported: Bool {
        sport == .running || sport == .cycling
    }

    func start() {
        guard isSupported else { return }
        wantsTracking = true
        isPaused = false
        snapshot = WorkoutLocationSnapshot()
        lastAccepted = nil

        // See requester: skip `CLLocationManager.locationServicesEnabled()`.
        switch manager.authorizationStatus {
        case .notDetermined:
            permission = .requesting
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            permission = .allowed
            beginUpdates()
        case .denied:
            permission = .denied
        case .restricted:
            permission = .restricted
        @unknown default:
            permission = .unavailable
        }
    }

    func pause() {
        guard wantsTracking else { return }
        isPaused = true
        manager.stopUpdatingLocation()
        lastAccepted = nil
        snapshot.currentSpeedMetersPerSecond = nil
    }

    func resume() {
        guard wantsTracking else { return }
        isPaused = false
        lastAccepted = nil
        if permission == .allowed {
            beginUpdates()
        }
    }

    func stop() {
        wantsTracking = false
        isPaused = false
        manager.stopUpdatingLocation()
        lastAccepted = nil
        snapshot.currentSpeedMetersPerSecond = nil
    }

    func discard() {
        stop()
        snapshot = WorkoutLocationSnapshot()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshPermission(manager.authorizationStatus)
        if wantsTracking, !isPaused, permission == .allowed {
            beginUpdates()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard wantsTracking, !isPaused else { return }

        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            accept(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let clError = error as? CLError, clError.code == .denied else { return }
        refreshPermission(manager.authorizationStatus)
    }

    private func beginUpdates() {
        // With the location background mode enabled on the app target, this lets
        // an active workout continue collecting fixes when the screen locks or
        // TriLoop moves to the background.
        if hasLocationBackgroundMode {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
        manager.startUpdatingLocation()
    }

    private var hasLocationBackgroundMode: Bool {
        guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            return false
        }
        return modes.contains("location")
    }

    private func refreshPermission(_ status: CLAuthorizationStatus) {
        permission = switch status {
        case .notDetermined: .unknown
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedAlways, .authorizedWhenInUse: .allowed
        @unknown default: .unavailable
        }
    }

    private func accept(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 35,
              abs(location.timestamp.timeIntervalSinceNow) <= 15 else { return }

        if let previous = lastAccepted {
            let time = location.timestamp.timeIntervalSince(previous.timestamp)
            guard time > 0 else { return }

            let segment = location.distance(from: previous)
            let segmentSpeed = segment / time
            guard segmentSpeed <= maximumPlausibleSpeed else { return }

            snapshot.distanceMeters += segment
            snapshot.currentSpeedMetersPerSecond = validSpeed(location.speed) ?? segmentSpeed
        } else {
            snapshot.currentSpeedMetersPerSecond = validSpeed(location.speed)
        }

        lastAccepted = location
        snapshot.route.append(
            RecordedRoutePoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
                timestamp: location.timestamp
            )
        )
    }

    private func validSpeed(_ speed: CLLocationSpeed) -> Double? {
        guard speed >= 0, speed <= maximumPlausibleSpeed else { return nil }
        return speed
    }

    private var maximumPlausibleSpeed: Double {
        switch sport {
        case .running: 15       // 54 km/h: generous enough for GPS variance.
        case .cycling: 45       // 162 km/h: rejects jumps without clipping descents.
        case .swimming: 6
        }
    }
}