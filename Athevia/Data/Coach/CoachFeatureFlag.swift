import Foundation

/// Live external-model transport is intentionally not shipped yet. The local
/// deterministic coach is enabled by default in Debug so it can be exercised,
/// while Release stays off until an authenticated server proxy, provider data
/// terms and explicit AI-data consent are configured.
enum CoachFeatureFlag {
    static let preferenceKey = "athevia.history-aware-coach.enabled.v1"

    static var isEnabled: Bool {
        #if DEBUG
        if UserDefaults.standard.object(forKey: preferenceKey) != nil {
            return UserDefaults.standard.bool(forKey: preferenceKey)
        }
        return true
        #else
        return UserDefaults.standard.bool(forKey: preferenceKey)
        #endif
    }
}
