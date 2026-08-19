import SwiftData
import SwiftUI

@main
struct TriLoopApp: App {
    private let modelContainer: ModelContainer
    private let storeOutcome: StoreOutcome
    private let autoImporter: WorkoutAutoImporter
    private let healthProvider: any HealthDataProviding

    init() {
        let (container, outcome) = TriLoopModelContainer.makeWithFallback()
        modelContainer = container
        storeOutcome = outcome
        healthProvider = HealthProviderResolver.current()
        autoImporter = WorkoutAutoImporter(container: container, provider: healthProvider)

        // Nothing is seeded at launch. A week comes from onboarding, in every
        // build — otherwise a debug install can never see the first-run flow,
        // and a seeded week collides with the one setup generates.

        // Registered here rather than from a view: HealthKit can launch the app
        // straight into the background, where no scene appears and a view's
        // `task` would never run to re-establish the observer.
        let importer = autoImporter
        if WorkoutAutoImporter.isEnabledByPreference {
            Task { await importer.setEnabled(true) }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeOutcome: storeOutcome, autoImporter: autoImporter)
                .environment(\.healthProvider, healthProvider)
        }
        .modelContainer(modelContainer)
    }
}
