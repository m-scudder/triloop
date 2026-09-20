import Foundation

/// Chooses the provider the app runs on.
///
/// The simulated branch is compiled out of Release entirely, so a shipping
/// build has no path — accidental or otherwise — to anything but HealthKit.
enum HealthProviderResolver {

    #if DEBUG
    /// Which source the athlete picked in Developer tools.
    static var selected: HealthDataSource {
        get {
            UserDefaults.standard.string(forKey: key)
                .flatMap(HealthDataSource.init(rawValue:)) ?? .live
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    private static let key = "healthDataSource"
    #endif

    /// Resolved once at launch: swapping providers mid-session would leave
    /// views holding a provider the rest of the app has moved on from.
    static func current() -> any HealthDataProviding {
        #if DEBUG
        switch selected {
        case .live: HealthKitWorkoutImporter()
        case .simulated: SimulatedHealthDataProvider()
        }
        #else
        HealthKitWorkoutImporter()
        #endif
    }
}
