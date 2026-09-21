import Foundation
import WatchKit

final class AtheviaWatchApplicationDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        NotificationCenter.default.post(
            name: .atheviaActiveWorkoutRecoveryRequested,
            object: nil
        )
    }
}

extension Notification.Name {
    static let atheviaActiveWorkoutRecoveryRequested = Notification.Name(
        "AtheviaActiveWorkoutRecoveryRequested"
    )
}
