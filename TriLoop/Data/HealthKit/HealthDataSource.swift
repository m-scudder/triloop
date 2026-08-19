import Foundation
import SwiftUI

/// Where health data comes from.
///
/// Live is the only option in a shipping build. The simulated case exists so
/// the intelligence layer and its UI can be developed against controlled data
/// without months of real training — and it sits *at the provider boundary*, so
/// everything downstream is the production path either way.
enum HealthDataSource: String, CaseIterable, Sendable {
    case live
    #if DEBUG
    case simulated
    #endif

    var displayName: String {
        switch self {
        case .live: "Live Health Data"
        #if DEBUG
        case .simulated: "Simulated Data"
        #endif
        }
    }
}

private struct HealthProviderKey: EnvironmentKey {
    /// Previews and any view rendered outside the app get a stub rather than a
    /// live `HKHealthStore`, which would prompt for permission.
    static let defaultValue: any HealthDataProviding = StubHealthDataProvider()
}

extension EnvironmentValues {
    /// The provider a view should read health data through.
    ///
    /// Views must never construct `HealthKitWorkoutImporter` themselves: doing
    /// so pins them to live data and makes the simulated source unreachable.
    var healthProvider: any HealthDataProviding {
        get { self[HealthProviderKey.self] }
        set { self[HealthProviderKey.self] = newValue }
    }
}
