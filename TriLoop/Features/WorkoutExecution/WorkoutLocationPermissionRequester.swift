import Combine
import CoreLocation
import Foundation

/// Owns the system location authorization request shown before an outdoor
/// iPhone workout begins. Keeping this outside the full-screen player avoids
/// racing the permission sheet against the player's presentation animation.
@MainActor
final class WorkoutLocationPermissionRequester: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Result: Equatable {
        case allowed
        case denied
        case unavailable
    }

    private let manager = CLLocationManager()
    private var completion: ((Result) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func request(_ completion: @escaping (Result) -> Void) {
        // Skip the class-level `locationServicesEnabled()` gate: Apple flags it
        // as main-thread-blocking. If services are off, iOS reports `.denied`
        // through `authorizationStatus`/the delegate callback anyway.
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            completion(.allowed)
        case .notDetermined:
            self.completion = completion
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            completion(.denied)
        @unknown default:
            completion(.unavailable)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let completion else { return }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            self.completion = nil
            completion(.allowed)
        case .denied, .restricted:
            self.completion = nil
            completion(.denied)
        case .notDetermined:
            break
        @unknown default:
            self.completion = nil
            completion(.unavailable)
        }
    }
}
